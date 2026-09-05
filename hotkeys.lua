---@diagnostic disable: lowercase-global, undefined-global
-- Use our custom HyperLogger instead of the standard logger
local HyperLogger = require('HyperLogger')
-- Always use the global application logger from init.lua
local log = _G.AppLogger
local __FILE__ = 'hotkeys.lua'
log:d('Initializing hotkey system', __FILE__, 6)

-- Access modules from the global environment if they've been loaded already
-- This prevents redundant module initialization
local function getModule(name)
    if _G[name] then
        log:d('Using existing module: ' .. name, __FILE__, 12)
        return _G[name]
    else
        log:d('Loading module: ' .. name, __FILE__, 15)
        local module = require(name)
        _G[name] = module
        return module
    end
end

-- Import modules using the getModule helper
local WindowManager = getModule('WindowManager')
local FileManager = getModule('FileManager')
local AppManager = getModule('AppManager')
local DeviceManager = getModule('DeviceManager')
local HotkeyManager = getModule('HotkeyManager')
local WindowToggler = getModule('WindowToggler')
local ProjectManager = getModule('ProjectManager')
local WindowMenu = getModule('WindowMenu')
local WindowTidy = getModule('WindowTidy')
local HotkeyBinder = getModule('HotkeyBinder')
-- Read the binding table up front: the modifier sets below come out of it.
HotkeyBinder.load()

-- Define modifier key combinations. Sourced from hotkeys.json so the named sets
-- ("hammer", "hyper", "meta") used by every binding in that file cannot drift
-- from the globals used by the imperative binds below. The literals are the
-- fallback for a missing or unparseable hotkeys.json -- losing the whole
-- keyboard over a stray comma would be a bad trade.
local modSets = (HotkeyBinder.config or {}).modifierSets or {}
hammer = modSets.hammer or { "cmd", "ctrl", "alt" }
_hyper = modSets.hyper or { "cmd", "shift", "ctrl", "alt" }
_meta = modSets.meta or { "cmd", "shift", "alt" }
-- NEW: Caps Lock as Hyper key (maps to F18)
_caps = {} -- Will be set up below with modal system

-- Add state tracking for toggling right layouts
local rightLayoutState = {
    isSmall = true
}
local leftLayoutState = {
    isSmall = true
}
local FullLayoutState = {
    currentState = 0 -- 0: fullScreen, 1: nearlyFull, 2: trueFull
}

log:d('Keyboard initializing - Beep boop!', __FILE__, 158)


-- ─────────────────────────────────────────────────────────────────────────────
-- Declarative bindings
-- ─────────────────────────────────────────────────────────────────────────────
-- The ~140 hs.hotkey.bind calls that used to fill this file now live in
-- hotkeys.json and are applied by HotkeyBinder. Add or change a hotkey THERE,
-- not here -- by hand, or from the keymap editor. Bindings are data now, which
-- is the whole point: a UI can read and rewrite them, and HotkeyBinder.reload()
-- applies changes live (hs.reload() would destroy every open window's state).
--
-- Regenerate hotkeys.json from a pre-migration hotkeys.lua:
--   python3 scripts/extract_hotkeys.py hotkeys.lua hotkeys.json
--
-- Check every binding still resolves to a real function:
--   hs.inspect(require('HotkeyBinder').verify())
HotkeyBinder.applyAll()

-- ─────────────────────────────────────────────────────────────────────────────
-- Bindings that stay imperative
-- ─────────────────────────────────────────────────────────────────────────────
-- Two cases hotkeys.json deliberately does not model: a body that closes over a
-- local, and bindings generated from runtime data. Everything else belongs in
-- the JSON table.

-- Open Replit team link in Work Chrome profile (profile dir: check chrome://version/ when Work is active)
local workChromeProfile = "Profile 2"   -- change if your Work profile uses another dir, e.g. "Default" or "Profile 2"
hs.hotkey.bind({"ctrl", "cmd"}, "b", "Open Replit (Work Chrome)", function()
    hs.execute(string.format(
        'open -na "Google Chrome" --args --profile-directory="%s" "https://replit.com/t/elemental-machines"',
        workChromeProfile
    ))
end)

-- Dynamic hotkeys for top 9 projects
for i = 1, 9 do
    local projects = FileManager.getProjectsList()
    if i <= #projects then
        local projectName = projects[i].name
        hs.hotkey.bind(_meta, tostring(i), "Open " .. projectName, function()
            AppManager.openProjectByIndex(i)
        end)
    end
end

-- Add a definition for tempFunction at the end of the file
function tempFunction()
    log:i('Temporary function called')
    hs.alert.show("Temporary Function Placeholder")
end



-- Window layout management hotkeys

-- Delete layout keybinding

-- Function to save current window layout with user input
function saveLayoutWithDialog()
    if not hs.dialog then
        hs.alert.show("hs.dialog module not available. Update Hammerspoon.")
        return
    end

    local name = hs.dialog.textPrompt("Save Layout", "Enter a name for this layout:", "", "Save", "Cancel")
    if name and name ~= "" then
        WindowManager.saveCurrentLayout(name)
    end
end

-- Function to restore a saved layout via chooser
function restoreLayoutChooser()
    local layouts = WindowManager.listSavedLayouts()
    if #layouts == 0 then
        hs.alert.show("No saved layouts available")
        return
    end

    local choices = {}
    for _, layout in ipairs(layouts) do
        table.insert(choices, {
            text = layout.name,
            subText = layout.description .. " (" .. layout.windowCount .. " windows)",
            image = hs.image.imageFromName("NSRefreshTemplate")
        })
    end

    local chooser = hs.chooser.new(function(choice)
        if choice then
            WindowManager.restoreLayout(choice.text)
        end
    end)

    chooser:placeholderText("Select a layout to restore")
    chooser:choices(choices)
    chooser:show()
end

-- Function to delete a saved layout via chooser
function deleteLayoutChooser()
    local layouts = WindowManager.listSavedLayouts()
    if #layouts == 0 then
        hs.alert.show("No saved layouts available")
        return
    end

    local choices = {}
    for _, layout in ipairs(layouts) do
        table.insert(choices, {
            text = layout.name,
            subText = "Delete: " .. layout.description .. " (" .. layout.windowCount .. " windows)",
            image = hs.image.imageFromName("NSTrashFull")
        })
    end

    local chooser = hs.chooser.new(function(choice)
        if choice then
            WindowManager.deleteLayout(choice.text)
        end
    end)

    chooser:placeholderText("Select a layout to DELETE")
    chooser:choices(choices)
    chooser:show()
end

function showTopProjects()
    local projects = FileManager.getProjectsList()
    if #projects == 0 then
        hs.alert.show("No projects found.")
        return
    end

    local message = "Top Projects:\n\n"
    for i = 1, math.min(9, #projects) do
        message = message .. i .. ". " .. projects[i].name .. "\n"
    end
    hs.alert.show(message, 10)
end
