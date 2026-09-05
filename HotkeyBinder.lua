---@diagnostic disable: lowercase-global, undefined-global
-- HotkeyBinder.lua
-- Applies the declarative binding table in hotkeys.json.
--
-- Why this exists: hotkeys.lua used to be ~150 hs.hotkey.bind calls, each
-- closing over an inline Lua function. Nothing outside Lua could read a binding,
-- and nothing at all could rewrite one -- editing a hotkey meant editing source.
-- This module makes a binding DATA: addressable by id, serialisable to JSON, and
-- rebindable at runtime. The keymap editor surfaces (HammerGhost tab, artifact,
-- httpserver) are all just editors for that same file.

-- Singleton (mirrors action_system.lua). hotkeys.lua require()s this module, but
-- the HammerGhost keymap UI dofile()s its scripts -- and dofile does NOT consult
-- package.loaded. A second copy starts with an empty `handles` table, so
-- applyAll() cannot delete the hotkeys the first copy owns: instead of replacing
-- them it stacks a second binding on every combo, and Hammerspoon silently
-- shadows the old one (deleting the new one later RE-ENABLES the stale one).
-- Stash the first instance on a global; later loads get it back.
if rawget(_G, "_HotkeyBinder") then
    return _G._HotkeyBinder
end

local HyperLogger = require('HyperLogger')
local log = _G.AppLogger or HyperLogger.new()
local __FILE__ = 'HotkeyBinder.lua'

local HotkeyBinder = {}
_G._HotkeyBinder = HotkeyBinder

HotkeyBinder.path = hs.configdir .. "/hotkeys.json"
HotkeyBinder.config = nil
HotkeyBinder.handles = {}  -- id -> hs.hotkey object, so a single binding can be replaced
HotkeyBinder.errors = {}   -- load/bind problems, surfaced to the keymap UI

-- ─────────────────────────────────────────────────────────────────────────────
-- Path resolution
-- ─────────────────────────────────────────────────────────────────────────────

--- Resolve "WindowManager.applyLayout" or "spoon.KineticLatch:toggle" against
--- the global table. Returns fn, selfObj, err.
---
--- Deliberately resolved AT PRESS TIME, not at bind time. init.lua dofiles
--- hotkeys.lua (line 52) BEFORE loadSpoon("HammerGhost") (line 55), so spoon.*
--- and the action system genuinely do not exist while bindings are created.
--- Late resolution also means a module reloaded in the console is picked up
--- without rebinding anything.
local function resolvePath(path)
    if type(path) ~= "string" or path == "" then
        return nil, nil, "empty function path"
    end

    local objPath, method = path:match("^(.-):([%w_]+)$")
    local isMethod = objPath ~= nil
    local walk = isMethod and objPath or path

    local segs = {}
    for seg in walk:gmatch("[^.]+") do segs[#segs + 1] = seg end
    if #segs == 0 then return nil, nil, "malformed path '" .. path .. "'" end

    -- For a method call every segment is part of the object; for a plain call
    -- the last segment is the function name.
    local cur = _G
    local upto = isMethod and #segs or (#segs - 1)
    for i = 1, upto do
        if type(cur) ~= "table" then
            return nil, nil, "'" .. segs[i - 1] .. "' is not a table in '" .. path .. "'"
        end
        cur = cur[segs[i]]
        if cur == nil then
            return nil, nil, "'" .. segs[i] .. "' not found (in '" .. path .. "')"
        end
    end

    local fn = isMethod and cur[method] or (type(cur) == "table" and cur[segs[#segs]] or nil)
    if type(fn) ~= "function" then
        return nil, nil, "'" .. path .. "' is not a function (got " .. type(fn) .. ")"
    end

    return fn, (isMethod and cur or nil), nil
end

HotkeyBinder.resolvePath = resolvePath

-- ─────────────────────────────────────────────────────────────────────────────
-- Dispatch
-- ─────────────────────────────────────────────────────────────────────────────

local function reportFailure(binding, msg)
    log:e(string.format("hotkey %s (%s): %s", binding.id or "?",
        binding.description or "", msg), __FILE__, 79)
    hs.alert.show("Hotkey failed: " .. (binding.description or binding.id or "?")
        .. "\n" .. msg, 3)
end

--- Build the press handler for a binding. Two action kinds:
---   call   - dotted path into the loaded modules (everything migrated from
---            hotkeys.lua lands here)
---   action - hand off to HammerGhost's action_system, which brings the whole
---            macro vocabulary (runShell, mqttPublish, httpRequest, ...) to any
---            key without new Lua
local function makeHandler(binding)
    return function()
        local action = binding.action or {}
        local kind = action.kind or "none"

        if kind == "none" then
            return
        elseif kind == "call" then
            local fn, selfObj, err = resolvePath(action.fn)
            if not fn then return reportFailure(binding, err) end

            local args = action.args or {}
            local ok, callErr
            if selfObj then
                ok, callErr = pcall(fn, selfObj, table.unpack(args, 1, #args))
            else
                ok, callErr = pcall(fn, table.unpack(args, 1, #args))
            end
            if not ok then reportFailure(binding, tostring(callErr)) end
        elseif kind == "action" then
            -- action_system stashes itself on this global (it is dofile'd from
            -- several places and must be one shared registry).
            local asys = rawget(_G, "_HammerGhostActionSystem")
            if not asys then
                return reportFailure(binding, "HammerGhost action system not loaded")
            end
            local ok, callErr = pcall(asys.executeAction, {
                actionType = action.actionType,
                params = action.params or {},
            })
            if not ok then reportFailure(binding, tostring(callErr)) end
        else
            reportFailure(binding, "unknown action kind '" .. tostring(kind) .. "'")
        end
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Binding
-- ─────────────────────────────────────────────────────────────────────────────

--- Turn a binding's `mods` into a modifier list. Either a named set from
--- modifierSets ("hammer") or an explicit list ({"ctrl","cmd"}).
function HotkeyBinder.resolveMods(mods)
    if type(mods) == "string" then
        local sets = (HotkeyBinder.config or {}).modifierSets or {}
        local set = sets[mods]
        if not set then return nil, "unknown modifier set '" .. mods .. "'" end
        return set, nil
    elseif type(mods) == "table" then
        return mods, nil
    end
    return nil, "invalid mods (" .. type(mods) .. ")"
end

--- Drop a binding from HotkeyManager's display registry, so showCombinedList()
--- never advertises a hotkey that is no longer (or was never) bound.
function HotkeyBinder.unregisterFromManager(mods, key)
    local HotkeyManager = _G.HotkeyManager or require('HotkeyManager')
    if mods and HotkeyManager and HotkeyManager.unregisterBinding then
        HotkeyManager.unregisterBinding(mods, key)
    end
end

--- Bind one entry, replacing any previous handle for the same id.
function HotkeyBinder.bindOne(binding)
    if not binding.id then
        table.insert(HotkeyBinder.errors, "binding with no id, skipped")
        return false
    end

    -- Drop the previous handle and its display-registry entry first, or an edit
    -- would leave the old hotkey live and showCombinedList() showing both.
    HotkeyBinder.unbindOne(binding.id)

    if binding.enabled == false then return true end

    local mods, err = HotkeyBinder.resolveMods(binding.mods)
    if not mods then
        table.insert(HotkeyBinder.errors, binding.id .. ": " .. err)
        log:e("Cannot bind " .. binding.id .. ": " .. err, __FILE__, 152)
        return false
    end

    local handler = makeHandler(binding)

    -- noRepeat mirrors the old ", nil, function() end" tail: that no-op sat in
    -- the REPEAT slot (bind's 6th arg), suppressing key-repeat on toggles.
    -- Putting it in the release slot instead would silently re-enable repeat.
    local ok, handle = pcall(function()
        if binding.noRepeat then
            return hs.hotkey.bind(mods, binding.key, binding.description, handler, nil, function() end)
        end
        return hs.hotkey.bind(mods, binding.key, binding.description, handler)
    end)

    if not ok or not handle then
        local msg = binding.id .. ": bind failed (" .. tostring(handle) .. ")"
        table.insert(HotkeyBinder.errors, msg)
        log:e(msg, __FILE__, 168)
        -- hs.hotkey.bind returns nil when macOS already owns the combo
        -- (RegisterEventHotKey -9878). HotkeyManager's wrapper registers a
        -- binding BEFORE calling through, so the failed one is now sitting in
        -- the display registry with no handle to clean it up by -- and
        -- showCombinedList() would advertise a hotkey that does nothing.
        HotkeyBinder.unregisterFromManager(mods, binding.key)
        return false
    end

    HotkeyBinder.handles[binding.id] = handle
    return true
end

--- Remove a live binding by id (handle + display-registry entry).
function HotkeyBinder.unbindOne(id)
    local handle = HotkeyBinder.handles[id]
    if handle then
        pcall(function() handle:delete() end)
        HotkeyBinder.handles[id] = nil
    end

    -- Clear the display-registry entry even when there was no handle. A binding
    -- that failed to enable still got registered by HotkeyManager's wrapper, and
    -- keying the cleanup off the handle would strand it there until a full
    -- hs.reload built fresh registry tables.
    local entry = HotkeyBinder.find(id)
    if entry then
        HotkeyBinder.unregisterFromManager(HotkeyBinder.resolveMods(entry.mods), entry.key)
    end
    return handle ~= nil
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Config load / save
-- ─────────────────────────────────────────────────────────────────────────────

function HotkeyBinder.load()
    HotkeyBinder.errors = {}

    if not hs.fs.attributes(HotkeyBinder.path) then
        log:w("No hotkeys.json at " .. HotkeyBinder.path, __FILE__, 199)
        HotkeyBinder.config = { version = 1, modifierSets = {}, bindings = {} }
        return false
    end

    local ok, data = pcall(hs.json.read, HotkeyBinder.path)
    if not ok or type(data) ~= "table" then
        local msg = "hotkeys.json is not valid JSON: " .. tostring(data)
        table.insert(HotkeyBinder.errors, msg)
        log:e(msg, __FILE__, 207)
        -- Keep whatever is already bound rather than tearing the keyboard down
        -- over a syntax error mid-edit.
        HotkeyBinder.config = HotkeyBinder.config or
            { version = 1, modifierSets = {}, bindings = {} }
        return false
    end

    data.bindings = data.bindings or {}
    data.modifierSets = data.modifierSets or {}
    HotkeyBinder.config = data
    log:d("Loaded " .. #data.bindings .. " bindings from hotkeys.json", __FILE__, 217)
    return true
end

function HotkeyBinder.save()
    if not HotkeyBinder.config then return false, "nothing loaded" end
    local ok, err = pcall(hs.json.write, HotkeyBinder.config, HotkeyBinder.path, true, true)
    if not ok then
        log:e("Failed to write hotkeys.json: " .. tostring(err), __FILE__, 226)
        return false, tostring(err)
    end
    return true
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Public API
-- ─────────────────────────────────────────────────────────────────────────────

function HotkeyBinder.find(id)
    for _, b in ipairs((HotkeyBinder.config or {}).bindings or {}) do
        if b.id == id then return b end
    end
    return nil
end

--- Bind everything in the loaded table. Safe to call repeatedly: every existing
--- handle is dropped first, so this is the live-apply path (no hs.reload, which
--- would tear down every open window and lose UI state).
function HotkeyBinder.applyAll()
    for id, _ in pairs(HotkeyBinder.handles) do
        HotkeyBinder.unbindOne(id)
    end
    HotkeyBinder.handles = {}

    local bound = 0
    for _, binding in ipairs((HotkeyBinder.config or {}).bindings or {}) do
        if HotkeyBinder.bindOne(binding) then bound = bound + 1 end
    end

    log:i("Bound " .. bound .. " hotkeys from hotkeys.json", __FILE__, 255)
    if #HotkeyBinder.errors > 0 then
        log:w(#HotkeyBinder.errors .. " binding error(s); see HotkeyBinder.errors", __FILE__, 257)
    end
    return bound
end

--- Insert or replace a binding, apply it live, and persist. This is what every
--- keymap editor surface ultimately calls.
function HotkeyBinder.setBinding(binding)
    if not binding or not binding.id then return false, "binding needs an id" end
    HotkeyBinder.config = HotkeyBinder.config or { version = 1, modifierSets = {}, bindings = {} }

    local replaced = false
    for i, b in ipairs(HotkeyBinder.config.bindings) do
        if b.id == binding.id then
            HotkeyBinder.unbindOne(binding.id)
            HotkeyBinder.config.bindings[i] = binding
            replaced = true
            break
        end
    end
    if not replaced then
        table.insert(HotkeyBinder.config.bindings, binding)
    end

    local ok = HotkeyBinder.bindOne(binding)
    HotkeyBinder.save()
    return ok
end

function HotkeyBinder.deleteBinding(id)
    HotkeyBinder.unbindOne(id)
    for i, b in ipairs((HotkeyBinder.config or {}).bindings or {}) do
        if b.id == id then
            table.remove(HotkeyBinder.config.bindings, i)
            HotkeyBinder.save()
            return true
        end
    end
    return false
end

--- Resolve every binding's target without calling it. The migration parity
--- check, and the keymap UI's "this binding is broken" indicator.
function HotkeyBinder.verify()
    local bad = {}
    for _, b in ipairs((HotkeyBinder.config or {}).bindings or {}) do
        local action = b.action or {}
        if action.kind == "call" then
            local fn, _, err = resolvePath(action.fn)
            if not fn then
                table.insert(bad, { id = b.id, description = b.description, error = err })
            end
        end
    end
    return bad
end

--- Load + bind. Called from hotkeys.lua.
function HotkeyBinder.init()
    HotkeyBinder.load()
    return HotkeyBinder.applyAll()
end

--- Reload from disk and re-apply, without hs.reload(). Use after editing
--- hotkeys.json by hand.
function HotkeyBinder.reload()
    HotkeyBinder.load()
    local n = HotkeyBinder.applyAll()
    hs.alert.show("Hotkeys reloaded: " .. n .. " bound")
    return n
end

return HotkeyBinder
