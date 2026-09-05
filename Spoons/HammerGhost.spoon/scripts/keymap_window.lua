-- Spoons/HammerGhost.spoon/scripts/keymap_window.lua
--
-- The keyboard-grid editor for hotkeys.json — a Logitech-Options-style view of
-- every hotkey, editable in place.
--
-- It is a window of its own rather than a card in control_panel.lua for two
-- reasons: a keyboard grid needs far more width than that 680x520 panel, and
-- control_panel.lua inlines its markup in a Lua long-string, so building here
-- would have forked exactly the page that Phases 2 (artifact) and 3 (http)
-- reuse. The Mad Tinker Dashboard opens this window, so it is still reached
-- from the same place.
--
-- The page itself is host-agnostic: assets/keymap.js renders and edits, and
-- talks only to window.KeymapTransport (assets/keymap_transport_hs.js). Swap
-- that one file and the same editor runs somewhere else.

local editor_window = dofile(hs.spoons.resourcePath("editor_window.lua"))

local M = {}

-- Reach the binder the same way hotkeys.lua does. require() is enough: the
-- module guards itself as a singleton on _G, so this is the very same table
-- holding the live hs.hotkey handles, not a second copy that would stack
-- shadowed duplicates on every combo.
local function binder()
    local ok, B = pcall(require, 'HotkeyBinder')
    if not ok then
        hs.logger.new("HammerGhost"):e("Keymap: HotkeyBinder unavailable: " .. tostring(B))
        return nil
    end
    return B
end

--- Everything the page needs in one payload.
--- Problems are merged from two sources so a key can show as broken whether it
--- failed to bind (macOS owns the combo) or binds but points at a function that
--- no longer exists.
function M.buildPayload()
    local B = binder()
    if not B then return { bindings = {}, modifierSets = {}, actionTypes = {}, problems = {} } end

    local problems = {}
    for _, err in ipairs(B.errors or {}) do
        local id, msg = err:match("^([^:]+):%s*(.+)$")
        if id then problems[id] = msg end
    end
    for _, bad in ipairs(B.verify()) do
        problems[bad.id] = bad.error
    end

    -- The action-type registry is what the "action" kind offers. getActionTypesForUI
    -- strips the handler closures: hs.json.encode returns nil for any table
    -- holding a function, which would silently blank the dropdown.
    local actionTypes = {}
    local asys = rawget(_G, "_HammerGhostActionSystem")
    if asys and asys.getActionTypesForUI then
        actionTypes = asys.getActionTypesForUI()
    end

    return {
        bindings = (B.config or {}).bindings or {},
        modifierSets = (B.config or {}).modifierSets or {},
        actionTypes = actionTypes,
        problems = problems,
    }
end

--- Push the current table into the page.
function M.refresh(win)
    if not win then return end
    local payload = hs.json.encode(M.buildPayload())
    if not payload then
        hs.logger.new("HammerGhost"):e("Keymap: could not encode payload")
        return
    end
    win:evaluateJavaScript(string.format("window.Keymap.render(%s)", payload))
end

-- hs.json.encode REQUIRES a table and throws on a bare string ("incorrect type
-- 'string' for argument 1"). Wrapping in an array and stripping the brackets
-- borrows Hammerspoon's own escaping instead of hand-rolling one.
local function jsonString(s)
    return (hs.json.encode({ tostring(s or "") }):sub(2, -2))
end

--- Report a one-line result into the editor's status area.
local function say(win, text)
    if not win then return end
    win:evaluateJavaScript(string.format("window.Keymap.setStatus(%s)", jsonString(text)))
end

--- Handle one hammerspoon:// message from the page.
--- The payload convention matches the other editor windows: the whole query
--- string is one encodeURIComponent(JSON.stringify(...)) blob.
function M.handleURL(spoon, url)
    local win = spoon.keymapEditor
    local cmd, args = url:match("hammerspoon://([^?]+)%??(.*)")
    if not cmd then return end

    local B = binder()
    if not B then return end

    if cmd == "keymapData" then
        M.refresh(win)

    elseif cmd == "keymapSave" then
        local binding = M.decode(args)
        if not binding then return say(win, "Could not read that change.") end

        local ok, err = B.setBinding(binding)
        if ok then
            say(win, "Saved and applied " .. tostring(binding.id) .. ".")
        else
            -- A refused bind is the normal failure here (macOS owns the combo),
            -- and the binder has already recorded why.
            local why = err or (B.errors[#B.errors] or "see the Hammerspoon console")
            say(win, "Saved, but not bound: " .. tostring(why))
        end
        M.refresh(win)

    elseif cmd == "keymapDelete" then
        local payload = M.decode(args)
        if not payload or not payload.id then return say(win, "Could not read that change.") end
        local removed = B.deleteBinding(payload.id)
        say(win, removed and ("Deleted " .. payload.id .. ".") or "Nothing to delete.")
        M.refresh(win)

    elseif cmd == "keymapReload" then
        B.load()
        local n = B.applyAll()
        say(win, "Reloaded from disk: " .. n .. " bound.")
        M.refresh(win)
    end
end

-- Percent-decode then JSON-decode a bridge payload, or nil (having said so) if
-- it is malformed. Callers must bail on nil rather than write half a binding.
function M.decode(args)
    if not args or args == "" then return nil end
    local decoded = args:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
    local ok, value = pcall(hs.json.decode, decoded)
    if not ok or type(value) ~= "table" then
        hs.logger.new("HammerGhost"):e("Keymap: bad bridge payload: " .. tostring(decoded))
        return nil
    end
    return value
end

function M.create(spoon)
    local screen = hs.screen.mainScreen():frame()
    -- Wide by default: the function row alone is 12 keys across.
    local w = math.min(1180, screen.w - 80)
    local h = math.min(820, screen.h - 80)
    return editor_window.create({
        x = screen.x + math.floor((screen.w - w) / 2),
        y = screen.y + math.floor((screen.h - h) / 2),
        w = w,
        h = h,
        title = "⌘ Keymap",
        html = "keymap.html",
        js = "keymap.js",
        extraJs = { "keymap_transport_hs.js" },
        handler = function(url) M.handleURL(spoon, url) end,
    })
end

return M
