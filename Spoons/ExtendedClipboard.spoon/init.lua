--- === ExtendedClipboard ===
---
--- Ten numbered clipboard registers (0-9), in the vim sense: copy into a slot,
--- paste out of a slot, and the slots survive a Hammerspoon reload.
---
--- Everything here is meant to be driven from hotkeys.json through BindForge,
--- so every entry point is a METHOD TAKING THE SLOT NUMBER -- one function,
--- ten bindings, instead of ten near-identical closures (which is what the
--- first version of this file was, all of it commented out):
---
---   spoon.ExtendedClipboard:copyTo   with args [1]  -- clipboard  -> slot 1
---   spoon.ExtendedClipboard:pasteFrom with args [1] -- slot 1 -> clipboard + ⌘V
---   spoon.ExtendedClipboard:loadFrom with args [1]  -- slot 1 -> clipboard only
---   spoon.ExtendedClipboard:showSlots               -- chooser over all slots
---
--- Slots are stored in hs.settings, NOT a file under data/: that directory is a
--- submodule which auto-commits, and a clipboard register churning every few
--- seconds would bury real layout changes in noise.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "ExtendedClipboard"
obj.version = "0.2.0"
obj.author = "<d.edens@email>"
obj.homepage = ""
obj.license = "MIT - https://opensource.org/licenses/MIT"

local log = hs.logger.new("ExtClip")

--- ExtendedClipboard.settingsKey
--- Variable
--- hs.settings key the register table is persisted under.
obj.settingsKey = "ExtendedClipboard.slots"

--- ExtendedClipboard.autoPaste
--- Variable
--- When true (the default), `pasteFrom` sends ⌘V after loading the slot, so one
--- key both recalls and pastes. Set false to only load the clipboard.
obj.autoPaste = true

--- ExtendedClipboard.alertLength
--- Variable
--- How much of the slot's text an on-screen alert shows before eliding.
obj.alertLength = 60

--- ExtendedClipboard.publishToMqtt
--- Variable
--- When true, every copy also runs `rost vars/clip<N> <text>` so the register
--- is readable from the other machines. Off by default: it shells out on every
--- copy, and clipboard content is exactly the kind of thing not to spray onto a
--- broker without meaning to.
obj.publishToMqtt = false

--- ExtendedClipboard.publishCommand
--- Variable
--- The command used when publishToMqtt is on. Gets ` vars/clip<N> <text>`.
obj.publishCommand = "rost"

-- Slot 0 is a real slot, so the valid range is 0..9 -- ten registers.
local SLOT_MIN, SLOT_MAX = 0, 9

-- In-memory mirror of the persisted table, keyed by slot STRING ("0".."9"):
-- hs.settings round-trips through a plist, which has no integer keys.
local slots = nil

local function load()
    if slots then return slots end
    local stored = hs.settings.get(obj.settingsKey)
    slots = (type(stored) == "table") and stored or {}
    return slots
end

local function save()
    hs.settings.set(obj.settingsKey, slots or {})
end

-- Accept 3, "3", or "clip3"; reject anything outside 0-9. Returns the string
-- key, or nil plus a message.
local function slotKey(slot)
    local n = tonumber(tostring(slot):match("%-?%d+") or "")
    if not n or n < SLOT_MIN or n > SLOT_MAX or n % 1 ~= 0 then
        return nil, "slot must be " .. SLOT_MIN .. "-" .. SLOT_MAX ..
            " (got " .. tostring(slot) .. ")"
    end
    return tostring(n)
end

-- One-line preview for alerts and the chooser: newlines become ⏎, long text is
-- cut at alertLength.
local function preview(text, limit)
    if type(text) ~= "string" then return "" end
    local flat = text:gsub("%s*\n%s*", " ⏎ "):gsub("^%s+", ""):gsub("%s+$", "")
    limit = limit or obj.alertLength
    if #flat > limit then flat = flat:sub(1, limit - 1) .. "…" end
    return flat
end

local function publish(key, text)
    if not obj.publishToMqtt then return end
    local quoted = "'" .. tostring(text):gsub("'", "'\\''") .. "'"
    hs.execute(obj.publishCommand .. " vars/clip" .. key .. " " .. quoted)
end

--- ExtendedClipboard:copyTo(slot)
--- Method
--- Store the current clipboard in `slot` (0-9). Returns the stored text or nil.
function obj:copyTo(slot)
    local key, err = slotKey(slot)
    if not key then
        log.w(err)
        hs.alert.show("Clip: " .. err)
        return nil
    end

    local text = hs.pasteboard.getContents()
    if not text or text == "" then
        hs.alert.show("Clip " .. key .. ": clipboard is empty (or not text)")
        return nil
    end

    load()[key] = { text = text, at = os.time() }
    save()
    publish(key, text)
    hs.alert.show("Clip " .. key .. " ← " .. preview(text))
    return text
end

--- ExtendedClipboard:loadFrom(slot)
--- Method
--- Put `slot`'s text on the clipboard WITHOUT pasting. Returns the text or nil.
function obj:loadFrom(slot)
    local key, err = slotKey(slot)
    if not key then
        log.w(err)
        hs.alert.show("Clip: " .. err)
        return nil
    end

    local entry = load()[key]
    local text = entry and entry.text
    if not text then
        hs.alert.show("Clip " .. key .. " is empty")
        return nil
    end

    hs.pasteboard.setContents(text)
    return text
end

--- ExtendedClipboard:pasteFrom(slot)
--- Method
--- Load `slot` onto the clipboard and paste it into the focused app (unless
--- ExtendedClipboard.autoPaste is false).
---
--- The paste is a real ⌘V keystroke rather than typing the text out: typing is
--- slow for anything long, and mangles apps that autocomplete or auto-indent.
--- The clipboard is deliberately LEFT holding the slot -- restoring the
--- previous contents afterwards races the app that is still reading the
--- pasteboard, and the whole point of a register is to keep it handy.
function obj:pasteFrom(slot)
    local text = self:loadFrom(slot)
    if not text then return nil end

    local key = slotKey(slot)
    if self.autoPaste then
        -- A beat for the pasteboard change to land before the keystroke; some
        -- apps read the pasteboard on the keydown itself.
        hs.timer.doAfter(0.05, function()
            hs.eventtap.keyStroke({ "cmd" }, "v", 0)
        end)
    end
    hs.alert.show("Clip " .. key .. " → " .. preview(text))
    return text
end

--- ExtendedClipboard:clearSlot(slot)
--- Method
--- Empty one register.
function obj:clearSlot(slot)
    local key, err = slotKey(slot)
    if not key then
        hs.alert.show("Clip: " .. err)
        return
    end
    load()[key] = nil
    save()
    hs.alert.show("Clip " .. key .. " cleared")
end

--- ExtendedClipboard:clearAll()
--- Method
--- Empty every register.
function obj:clearAll()
    slots = {}
    save()
    hs.alert.show("All clip slots cleared")
end

--- ExtendedClipboard:slots()
--- Method
--- The register table as { [0-9] = {text=, at=} }, for scripts and menus.
function obj:getSlots()
    local out = {}
    for key, entry in pairs(load()) do
        local n = tonumber(key)
        if n then out[n] = entry end
    end
    return out
end

--- ExtendedClipboard:showSlots()
--- Method
--- Chooser over all ten registers; picking one pastes it. Bind this to a single
--- key when you would rather not spend ten of them.
function obj:showSlots()
    local choices = {}
    local stored = load()
    for n = SLOT_MIN, SLOT_MAX do
        local entry = stored[tostring(n)]
        choices[#choices + 1] = {
            text = tostring(n) .. "  " .. (entry and preview(entry.text, 90) or "(empty)"),
            subText = entry and ("saved " .. os.date("%Y-%m-%d %H:%M", entry.at))
                or "no contents",
            slot = n,
            valid = entry ~= nil,
        }
    end

    local chooser = hs.chooser.new(function(choice)
        if choice and choice.valid then obj:pasteFrom(choice.slot) end
    end)
    chooser:placeholderText("Clipboard register → paste")
    chooser:choices(choices)
    chooser:show()
end

function obj:init()
    load()
    return self
end

return obj
