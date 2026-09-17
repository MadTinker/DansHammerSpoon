-- PadForge/PcfgCodec.lua
--
-- Reads and surgically rewrites the <ACK05> device block inside an XPPen
-- .pcfg export (PenTableLists XML). The file also holds profiles for every
-- other tablet model XPPen ships, so this module never parses or
-- re-serializes the whole document -- it isolates the <ACK05>...</ACK05>
-- substring by exact string search and only ever replaces one <Kn>...</Kn>
-- node inside it, byte-for-byte everywhere else.
--
-- Format, reverse-engineered from a real export (2026-09-17):
--   <K7 Motid="7" id="1" Show="1" Actid="5">1|Command+Shift+G|Command+Shift+G|16777250:55+16777248:56+71:5</K7>
-- Body is "1|Label|DisplayCombo|EncodedCombo" where EncodedCombo is
-- "qtKeyCode:macVirtualKeycode" pairs joined by "+", modifiers first. The
-- second number in each pair is the actual macOS virtual keycode -- the same
-- currency hs.keycodes.map speaks -- so no keycode table of our own is needed
-- for the mac side. id="0" + no body means "still the firmware default";
-- id="1" + a body means "user override". Actid is a fixed per-slot capability
-- tag (K7 is always Actid=5 in this file, K8 always Actid=6, etc.) -- it is
-- never invented, only carried through unchanged.
--
-- Deliberately unsupported (out of scope for reusing existing Hammerspoon
-- hotkeys, which always pair a modifier with a real key):
--   * pure modifier-chord slots ("2|label|3+2+4" bodies, no base key)
--   * non-keystroke actions (e.g. Actid=6's "3|label|N" switch-monitor form)
--   * per-application override profiles under <Apps> (only the global
--     CommonAPP profile -- the four mode tabs the desktop app's main screen
--     shows -- is editable here)
--   * the ring (<R>/<W1>-<W4>) -- display-only for now
-- Touching any of those on save would misparse; callers should treat a node
-- outside the modelled shape as read-only and leave it alone.

local Codec = {}

-- ─────────────────────────────────────────────────────────────────────────────
-- Qt::Key codes for the first half of each encoded pair.
-- ─────────────────────────────────────────────────────────────────────────────
-- Printable ASCII (letters, digits, most punctuation) is just its ASCII value
-- in Qt -- confirmed against the sample ("G" -> 71). Everything else is a
-- fixed Qt::Key enum value; the ones below are the keys a shortcut pad
-- actually uses. Modifiers are included because they appear as ordinary
-- pair entries alongside the base key, not as a separate bitfield.
local QT_KEY = {
    escape = 0x01000000, tab = 0x01000001, backspace = 0x01000003,
    ["return"] = 0x01000004, delete = 0x01000007,
    home = 0x01000010, ["end"] = 0x01000011,
    left = 0x01000012, up = 0x01000013, right = 0x01000014, down = 0x01000015,
    pageup = 0x01000016, pagedown = 0x01000017,
    shift = 0x01000020, ctrl = 0x01000021, cmd = 0x01000022, alt = 0x01000023,
    capslock = 0x01000024,
    space = 0x20,
}
for i = 1, 12 do QT_KEY["f" .. i] = 0x01000030 + (i - 1) end

-- Canonical modifier order for the encoded/display strings: matches the
-- ⌃⌥⇧⌘ convention macOS itself uses for badges.
local MOD_ORDER = { "ctrl", "alt", "shift", "cmd" }
local MOD_GLYPH = { ctrl = "Control", alt = "Option", shift = "Shift", cmd = "Command" }

-- Slots the file actually lets you override (see header note on K1/K2/K11).
Codec.EDITABLE_KEYS = { "K3", "K4", "K5", "K6", "K7", "K8", "K9", "K10" }
Codec.FIXED_KEYS = { "K1", "K2", "K11" } -- shown, not editable

Codec.MODES = { "K", "K_1", "K_2", "K_3" }
Codec.MODE_LABELS = { K = "I", K_1 = "II", K_2 = "III", K_3 = "IV" }

-- ─────────────────────────────────────────────────────────────────────────────
-- Encoding a combo the user picked in the UI
-- ─────────────────────────────────────────────────────────────────────────────

--- mods: array of "ctrl"/"alt"/"shift"/"cmd". key: a name hs.keycodes.map
--- knows ("g", "f1", "return", "down", ...). Returns display, encoded, err.
function Codec.encodeCombo(mods, key)
    key = (key or ""):lower()
    local vk = hs.keycodes.map[key]
    if not vk then
        return nil, nil, "Unknown key: " .. tostring(key)
    end

    local qt = QT_KEY[key]
    if not qt then
        if #key == 1 then
            qt = string.byte(key:upper())
        else
            return nil, nil, "No Qt keycode known for: " .. key
        end
    end

    local displayParts, encodedParts = {}, {}
    local seen = {}
    for _, m in ipairs(mods or {}) do seen[m] = true end
    for _, m in ipairs(MOD_ORDER) do
        if seen[m] then
            table.insert(displayParts, MOD_GLYPH[m])
            table.insert(encodedParts, QT_KEY[m] .. ":" .. hs.keycodes.map[m])
        end
    end

    local keyDisplay = key:upper()
    if key == "return" then keyDisplay = "↵"
    elseif key == "escape" then keyDisplay = "⎋"
    elseif key == "up" or key == "down" or key == "left" or key == "right" then
        keyDisplay = ({ up = "↑", down = "↓", left = "←", right = "→" })[key]
    end
    table.insert(displayParts, keyDisplay)
    table.insert(encodedParts, qt .. ":" .. vk)

    local display = table.concat(displayParts, "+")
    return display, table.concat(encodedParts, "+")
end

-- hs.keycodes.map uses "cmd"/"alt"/"ctrl"/"shift" for the modifier keys
-- themselves too (as key-you-can-bind-to entries) -- verified present on a
-- recent Hammerspoon build. If a build ever lacks one, encodeCombo below
-- surfaces it as "Unknown key" rather than silently emitting a bad pair.

--- Build a full body string ("1|Label|Display|Encoded") for writing into the
--- file. label defaults to the display string.
function Codec.buildBody(mods, key, label)
    local display, encoded, err = Codec.encodeCombo(mods, key)
    if not display then return nil, err end
    label = (label and label ~= "") and label or display
    -- Pipes/newlines in a label would corrupt the field layout; the editor
    -- should never let one through, but refuse rather than emit garbage.
    if label:find("[|\n\r]") then return nil, "Label cannot contain | or a newline" end
    return "1|" .. label .. "|" .. display .. "|" .. encoded
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Reading
-- ─────────────────────────────────────────────────────────────────────────────

--- Find the <ACK05>...</ACK05> substring's byte range in the raw file text.
local function findDeviceBlock(text)
    local s, e1 = text:find("<ACK05>", 1, true)
    if not s then return nil, nil, "No <ACK05> block in this file" end
    local _, e2 = text:find("</ACK05>", e1, true)
    if not e2 then return nil, nil, "Unterminated <ACK05> block" end
    return s, e2
end

--- Within the device block, the CommonAPP section (the four global mode
--- tabs) precedes <Apps> -- isolate it so a same-named tag under a
--- per-application override is never mistaken for the global one.
local function findCommonAppBlock(deviceText)
    local s, e1 = deviceText:find("<CommonAPP>", 1, true)
    if not s then return nil, nil, "No <CommonAPP> in device block" end
    local _, e2 = deviceText:find("</CommonAPP>", e1, true)
    if not e2 then return nil, nil, "Unterminated <CommonAPP>" end
    return s, e2
end

--- Find one <mode>...</mode> block (mode e.g. "K_2") within commonAppText.
local function findModeBlock(commonAppText, mode)
    -- "<K_2 " / "<K_2>" and the matching "</K_2>". "K" alone must not match
    -- "K_1" etc, so require the char right after the name to be '>' or space.
    local openPat = "<" .. mode .. "[ >]"
    local s, tagEnd = commonAppText:find(openPat)
    if not s then return nil, nil, "No <" .. mode .. "> block" end
    local _, e2 = commonAppText:find("</" .. mode .. ">", tagEnd, true)
    if not e2 then return nil, nil, "Unterminated <" .. mode .. ">" end
    return s, e2
end

--- Parse one <Kn .../> or <Kn ...>body</Kn> node starting at or after `from`
--- within `text`. Returns a table {raw, nStart, nEnd, motid, id, show, actid,
--- body} or nil.
local function parseKeyNode(text, keyName, from)
    local openPat = "<" .. keyName .. "%s+([^>]-)/>"
    local s, e, attrs = text:find(openPat, from)
    if s then
        return {
            raw = text:sub(s, e), nStart = s, nEnd = e,
            selfClosed = true, attrs = attrs, body = nil,
        }
    end
    openPat = "<" .. keyName .. "%s+([^>]-)>(.-)</" .. keyName .. ">"
    local s2, e2, attrs2, body2 = text:find(openPat, from)
    if not s2 then return nil end
    return {
        raw = text:sub(s2, e2), nStart = s2, nEnd = e2,
        selfClosed = false, attrs = attrs2, body = body2,
    }
end

local function attr(attrs, name)
    return attrs:match(name .. '="([^"]*)"')
end

--- Load a .pcfg file and return the editable model:
---   { path, raw, modes = { K = { K3 = {motid,actid,id,label,display,encoded}, ... }, ... } }
--- `raw` is kept so save() can splice back into the exact original bytes.
function Codec.load(path)
    local file = io.open(path, "r")
    if not file then return nil, "Could not open " .. tostring(path) end
    local raw = file:read("*a")
    file:close()

    local ds, de, derr = findDeviceBlock(raw)
    if not ds then return nil, derr end
    local deviceText = raw:sub(ds, de)

    local cs, ce, cerr = findCommonAppBlock(deviceText)
    if not cs then return nil, cerr end
    local commonAppText = deviceText:sub(cs, ce)

    local modes = {}
    for _, mode in ipairs(Codec.MODES) do
        local ms, me, merr = findModeBlock(commonAppText, mode)
        if not ms then return nil, merr end
        local modeText = commonAppText:sub(ms, me)
        local keys = {}
        for _, keyName in ipairs(Codec.EDITABLE_KEYS) do
            local node = parseKeyNode(modeText, keyName, 1)
            if not node then return nil, "Missing " .. keyName .. " in mode " .. mode end
            local id, motid, actid = attr(node.attrs, "id"), attr(node.attrs, "Motid"), attr(node.attrs, "Actid")
            local label, display, encoded
            if not node.selfClosed and node.body and node.body ~= "" then
                local count, l, d, enc = node.body:match("^(%d+)|([^|]*)|([^|]*)|(.*)$")
                if count == "1" then label, display, encoded = l, d, enc end
                -- Any other shape (pure-modifier chord, special action) is
                -- left with label/display/encoded nil -- the UI shows it as
                -- "not editable here" rather than guessing.
            end
            keys[keyName] = {
                motid = motid, actid = actid, id = id,
                custom = (id == "1"), label = label, display = display, encoded = encoded,
                recognized = (id ~= "1") or (display ~= nil),
            }
        end
        for _, keyName in ipairs(Codec.FIXED_KEYS) do
            local node = parseKeyNode(modeText, keyName, 1)
            if node then
                keys[keyName] = { fixed = true, actid = attr(node.attrs, "Actid") }
            end
        end
        modes[mode] = keys
    end

    return { path = path, raw = raw, modes = modes }
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Writing
-- ─────────────────────────────────────────────────────────────────────────────

--- Rewrite one key's assignment and save to disk (same path, in place).
--- model: the table Codec.load() returned (its .raw is used as the source of
--- truth; call Codec.load() again after saving rather than reusing model).
--- mode: e.g. "K_2". keyName: e.g. "K7". mods/key/label: the new assignment.
function Codec.save(model, mode, keyName, mods, key, label)
    local body, berr = Codec.buildBody(mods, key, label)
    if not body then return false, berr end

    local raw = model.raw
    local ds, de, derr = findDeviceBlock(raw)
    if not ds then return false, derr end

    local cs, ce, cerr = findCommonAppBlock(raw:sub(ds, de))
    if not cs then return false, cerr end
    -- Offsets found within substrings must be translated back to `raw`
    -- coordinates before splicing, since each find() above worked on a copy.
    local commonAppStart = ds + cs - 1

    local commonAppText = raw:sub(commonAppStart, ds + ce - 1)
    local ms, me, merr = findModeBlock(commonAppText, mode)
    if not ms then return false, merr end
    local modeStart = commonAppStart + ms - 1

    local modeText = raw:sub(modeStart, commonAppStart + me - 1)
    local node = parseKeyNode(modeText, keyName, 1)
    if not node then return false, "Missing " .. keyName .. " in mode " .. mode end

    local motid = attr(node.attrs, "Motid")
    local actid = attr(node.attrs, "Actid") -- carried through unchanged, see header
    local newAttrs = string.format('Motid="%s" id="1" Show="1" Actid="%s"', motid, actid)
    local newNode = "<" .. keyName .. " " .. newAttrs .. ">" .. body .. "</" .. keyName .. ">"

    local nodeStart = modeStart + node.nStart - 1
    local nodeEnd = modeStart + node.nEnd - 1

    local newRaw = raw:sub(1, nodeStart - 1) .. newNode .. raw:sub(nodeEnd + 1)

    local file, ferr = io.open(model.path, "w")
    if not file then return false, "Could not write " .. tostring(model.path) .. ": " .. tostring(ferr) end
    file:write(newRaw)
    file:close()

    model.raw = newRaw
    return true
end

return Codec
