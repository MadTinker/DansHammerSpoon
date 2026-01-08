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

-- Define modifier key combinations
hammer = { "cmd", "ctrl", "alt" }
_hyper = { "cmd", "shift", "ctrl", "alt" }
_meta = { "cmd", "shift", "alt" }
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

-- Keybindings - Top Row
hs.hotkey.bind(hammer, "F1", "Toggle Console", function() hs.toggleConsole() end)
hs.hotkey.bind(_hyper, "F1", "LM Studio", function() AppManager.open_lmstudio() end)
hs.hotkey.bind("cmd", "F1", "Open Warp", function() AppManager.open_terminal() end)
hs.hotkey.bind(hammer, "F2", "Temporary Function", function() tempFunction() end)
hs.hotkey.bind(_hyper, "F2", "Windsurf", function() AppManager.open_windsurf() end)
hs.hotkey.bind("cmd", "F2", "Open Zen", function() AppManager.open_zen() end)
hs.hotkey.bind(hammer, "F3", "Toggle USB Logging", function() DeviceManager.toggleUSBLogging() end)
hs.hotkey.bind(_hyper, "F3", "Temporary Function", function() tempFunction() end)
hs.hotkey.bind("cmd", "F3", "Open GitHub", function() AppManager.open_github() end)
hs.hotkey.bind(hammer, "F4", "Show Layouts Menu", function() spoon.Layouts:chooseLayout() end)
hs.hotkey.bind(_hyper, "F4", "Save Layout", function() saveLayoutWithDialog() end)
hs.hotkey.bind("cmd", "F4", "Temporary Function", function() tempFunction() end)
hs.hotkey.bind(hammer, "F5", "Reload Hammerspoon", function() hs.reload() end)
hs.hotkey.bind(_hyper, "F5", "Open Hammerspoon Preferences", function() hs.openPreferences() end)
hs.hotkey.bind("cmd", "F5", "Temporary Function", function() tempFunction() end)
hs.hotkey.bind(hammer, "F6", "Save Window Position", function() WindowManager.saveWindowPosition() end)
hs.hotkey.bind(_hyper, "F6", "Save All Window Positions", function() WindowManager.saveAllWindowPositions() end)
hs.hotkey.bind("cmd", "F6", "Temporary Function", function() tempFunction() end)
hs.hotkey.bind(hammer, "F7", "Restore Window Position", function() WindowManager.restoreWindowPosition() end)
hs.hotkey.bind(_hyper, "F7", "Restore All Window Positions", function() WindowManager.restoreAllWindowPositions() end)
hs.hotkey.bind("cmd", "F8", "Temporary Function", function() tempFunction() end)
hs.hotkey.bind(hammer, "F8", "Raise Window to Front", function() WindowManager.toggleAlwaysOnTop() end)
hs.hotkey.bind(_hyper, "F8", "Temporary Function", function() tempFunction() end)
hs.hotkey.bind("cmd", "F9", "Temporary Function", function() tempFunction() end)
hs.hotkey.bind(hammer, "F9", "Show Window Config Info", function() WindowToggler.showConfigurationInfo() end)
hs.hotkey.bind(_hyper, "F9", "Refresh Window Config", function() WindowToggler.refreshConfiguration() end)
hs.hotkey.bind("cmd", "F10", "Temporary Function", function() tempFunction() end)
hs.hotkey.bind(hammer, "F10", "Temporary Function", function() tempFunction() end)
hs.hotkey.bind(_hyper, "F10", "Temporary Function", function() tempFunction() end)
hs.hotkey.bind("cmd", "F11", "Temporary Function", function() tempFunction() end)
hs.hotkey.bind(hammer, "F11", "Temporary Function", function() tempFunction() end)
hs.hotkey.bind(_hyper, "F11", "Temporary Function", function() tempFunction() end)
hs.hotkey.bind("cmd", "F12", "Temporary Function", function() tempFunction() end)
hs.hotkey.bind(hammer, "F12", "Temporary Function", function() tempFunction() end)
hs.hotkey.bind(_hyper, "F12", "Temporary Function", function() tempFunction() end)

-- Keybindings - Number Row
hs.hotkey.bind(hammer, "`", "Open Cursor with GitHub", function() AppManager.open_cursor_with_github() end)
hs.hotkey.bind(_hyper, "`", "Open Medis", function() AppManager.open_medis() end)
hs.hotkey.bind(hammer, "1", "Move Top-Left Corner", function() WindowManager.applyLayout("topLeft") end)
hs.hotkey.bind(_hyper, "1", "Move Bottom-Left Corner", function() WindowManager.applyLayout("bottomLeft") end)
hs.hotkey.bind(hammer, "2", "Move Top-Right Corner", function() WindowManager.applyLayout("topRight") end)
hs.hotkey.bind(_hyper, "2", "Move Bottom-Right Corner", function() WindowManager.applyLayout("bottomRight") end)
hs.hotkey.bind(hammer, "3", "Full Screen", function() WindowManager.toggleFullLayout() end)
hs.hotkey.bind(_hyper, "3", "Nearly Full Screen", function() WindowManager.applyLayout('sevenByFive') end)
hs.hotkey.bind(hammer, "4", "Left Wide Layout", function() WindowManager.applyLayout('leftWide') end)
hs.hotkey.bind(_hyper, "4", "Mini Shuffle", function() WindowManager.miniShuffle() end)
hs.hotkey.bind(hammer, "5", "Split Vertical", function() WindowManager.applyLayout('splitVertical') end)
hs.hotkey.bind(_hyper, "5", "Split Horizontal", function() WindowManager.applyLayout('splitHorizontal') end)
hs.hotkey.bind(hammer, "6", "Left Small Layout", function() WindowManager.toggleLeftLayout() end)
hs.hotkey.bind(_hyper, "6", "Left Half Layout", function() WindowManager.applyLayout('leftHalf') end)
hs.hotkey.bind(hammer, "7", "Toggle Right Layout", function() WindowManager.toggleRightLayout() end)
hs.hotkey.bind(_hyper, "7", "Right Half Layout", function() WindowManager.applyLayout('rightHalf') end)
hs.hotkey.bind(hammer, "8", "Temporary Function", function() tempFunction() end)
hs.hotkey.bind(_hyper, "8", "Open System Preferences", function() AppManager.open_system() end)
hs.hotkey.bind(hammer, "9", "Move Window to Mouse", function() WindowManager.moveWindowMouseCenter() end)
hs.hotkey.bind(_hyper, "9", "Open Selected File", function() FileManager.openSelectedFile() end)
hs.hotkey.bind(hammer, "0", "Horizontal Shuffle", function() WindowManager.halfShuffle(4, 4) end)
hs.hotkey.bind(_hyper, "0", "Vertical Shuffle", function() WindowManager.halfShuffle(1, 4) end)
-- add - and = and backspace
hs.hotkey.bind(hammer, "-", "Temporary Function", function() tempFunction() end)
hs.hotkey.bind(_hyper, "-", "Temporary Function", function() tempFunction() end)
hs.hotkey.bind(hammer, "=", "Temporary Function", function() tempFunction() end)
hs.hotkey.bind(_hyper, "=", "Temporary Function", function() tempFunction() end)
-- hs.hotkey.bind(hammer, "delete", "Temporary Function", function() tempFunction() end) (cant bind while modifier is down)
-- hs.hotkey.bind(_hyper, "delete", "Temporary Function", function() tempFunction() end)
-- hs.hotkey.bind(hammer, "u", "Save Current Layout", function() saveLayoutWithDialog() end)
-- hs.hotkey.bind(hammer, "i", "Restore Layout", function() restoreLayoutChooser() end)
-- hs.hotkey.bind(_hyper, "y", "Delete Layout", function() deleteLayoutChooser() end)

-- Keybindings - Tab Row
hs.hotkey.bind(hammer, "Tab", "Open Mission Control", function() AppManager.open_mission_control() end)
hs.hotkey.bind(_hyper, "Tab", "Open Launchpad", function() AppManager.open_launchpad() end)
hs.hotkey.bind(hammer, "q", "Clear Saved Window Positions", function() WindowToggler.clearSavedPositions() end)
hs.hotkey.bind(_hyper, "q", "Clear All Saved Locations", function() WindowToggler.clearSavedLocations(true) end)
hs.hotkey.bind(hammer, "w", "Toggle Between Location 1 and 2", function() WindowToggler.toggleWindowPosition() end)
hs.hotkey.bind(_hyper, "w", "Window Locations Menu", function() WindowToggler.showLocationsMenu() end)
hs.hotkey.bind(hammer, "e", "Show File Menu", function() FileManager.showFileMenu() end)
hs.hotkey.bind(_hyper, "e", "Show Editor Menu", function() FileManager.showEditorMenuSafe() end)
hs.hotkey.bind(hammer, "r", "Show Window Management Menu", function() WindowMenu.toggleMenu() end)
hs.hotkey.bind(_hyper, "r", "Reset Shuffle Counters", function() WindowManager.resetShuffleCounters() end)
hs.hotkey.bind(hammer, "t", "Open Barrier", function() AppManager.open_barrier() end)
hs.hotkey.bind(_hyper, "t", "Temporary Function", function() tempFunction() end)
hs.hotkey.bind(hammer, "y", "Temporary Function", function() tempFunction() end)
hs.hotkey.bind(_hyper, "y", "Temporary Function", function() tempFunction() end)
hs.hotkey.bind(hammer, "u", "Open Most Recent Image Folder", function() FileManager.openMostRecentImageFolder() end)
hs.hotkey.bind(_hyper, "u", "Temporary Function", function() tempFunction() end)
hs.hotkey.bind(hammer, "i", "Copy Most Recent Image", function() FileManager.copyMostRecentImage() end)
hs.hotkey.bind(_hyper, "i", "Open Most Recent Image", function() FileManager.openMostRecentImage() end)
hs.hotkey.bind(hammer, "o", "Restore Window to Location 1", function() WindowToggler.restoreToLocation1() end)
hs.hotkey.bind(_hyper, "o", "Save Window to Location 1", function() WindowToggler.saveToLocation1() end)
-- hs.hotkey.bind(hammer, "p", "Open Antigravity", function() AppManager.open_antigravity() end)
hs.hotkey.bind(hammer, "p", "Open Postman", function() AppManager.open_postman() end)
hs.hotkey.bind(_hyper, "p", "Open Cursor", function() AppManager.open_cursor() end)
hs.hotkey.bind(hammer, "[", "Temporary Function", function() tempFunction() end)
hs.hotkey.bind(_hyper, "[", "Temporary Function", function() tempFunction() end)
hs.hotkey.bind(hammer, "]", "Temporary Function", function() tempFunction() end)
hs.hotkey.bind(_hyper, "]", "Temporary Function", function() tempFunction() end)
hs.hotkey.bind(hammer, "\\", "Temporary Function", function() tempFunction() end)
hs.hotkey.bind(_hyper, "\\", "Temporary Function", function() tempFunction() end)

-- Keybindings - Caps Lock Row
hs.hotkey.bind(hammer, "a", "Toggle KineticLatch", function() spoon.KineticLatch:toggle() end)
hs.hotkey.bind(_hyper, "a", "KineticLatch Status", function() spoon.KineticLatch:showStatus() end)
hs.hotkey.bind(_meta, "a", "KineticLatch Diagnostics", function() spoon.KineticLatch:diagnose() end)
hs.hotkey.bind(hammer, "s", "Open Slack", function() AppManager.open_slack() end)
hs.hotkey.bind(_hyper, "s", "Temporary Function", function() tempFunction() end)
hs.hotkey.bind(hammer, "d", "Open AnythingLLM", function() AppManager.open_anythingllm() end)
hs.hotkey.bind(_hyper, "d", "Open MongoDB Compass", function() AppManager.open_mongodb() end)
hs.hotkey.bind(hammer, "f", "Open Scrcpy", function() AppManager.open_scrcpy() end)
hs.hotkey.bind(_hyper, "f", "Temporary Function", function() tempFunction() end)
hs.hotkey.bind(hammer, "g", "Open GitHub Desktop", function() AppManager.launchGitHubWithProjectSelection() end)
hs.hotkey.bind(_hyper, "g", "Open just GitHub Desktop", function() AppManager.open_github() end)
hs.hotkey.bind(hammer, "h", "Temporary Function", function() tempFunction() end)
hs.hotkey.bind(_hyper, "h", "Temporary Function", function() tempFunction() end)
hs.hotkey.bind(hammer, "j", "Toggle Project Manager", function() ProjectManager.toggleProjectManager() end)
hs.hotkey.bind(_hyper, "j", "Show Active Project Info", function() ProjectManager.showActiveProjectInfo() end)
hs.hotkey.bind(hammer, "k", "Reset Project Manager UI", function() ProjectManager.resetUI() end)
hs.hotkey.bind(_hyper, "k", "Hide Project Manager UI", function() ProjectManager.hideUI() end)
hs.hotkey.bind(hammer, "l", "Open Logi Options+", function() AppManager.open_logi() end)
hs.hotkey.bind(_hyper, "l", "Open System Settings", function() AppManager.open_system() end)
hs.hotkey.bind(hammer, ";", "Temporary Function", function() tempFunction() end)
hs.hotkey.bind(_hyper, ";", "Temporary Function", function() tempFunction() end)
hs.hotkey.bind(hammer, "'", "Temporary Function", function() tempFunction() end)
hs.hotkey.bind(_hyper, "'", "Temporary Function", function() tempFunction() end)
hs.hotkey.bind(hammer, "return", "Toggle Native Fullscreen", function() WindowManager.toggleNativeFullScreen() end)

-- Shift Row
hs.hotkey.bind(hammer, "z", "Temporary Function", function() tempFunction() end)
hs.hotkey.bind(_hyper, "z", "Temporary Function", function() tempFunction() end)
hs.hotkey.bind(hammer, "x", "Toggle Dragon Grid", function() spoon.DragonGrid:toggleGridDisplay() end)
hs.hotkey.bind(_hyper, "x", "Dragon Grid Settings", function() spoon.DragonGrid:showSettingsMenu() end)
hs.hotkey.bind(hammer, "c", "Temporary Function", function() tempFunction() end) -- hs.hotkey.bind(hammer, "c", function() FileManager.showClipboardManager() end) broken
hs.hotkey.bind(_hyper, "c", "Temporary Function", function() tempFunction() end) -- hs.hotkey.bind(_hyper, "c", function() FileManager.clearClipboard() end) broken
hs.hotkey.bind(hammer, "v", "Temporary Function", function() tempFunction() end)
hs.hotkey.bind(_hyper, "v", "Temporary Function", function() tempFunction() end)
hs.hotkey.bind(hammer, "b", "Open Chrome", function() AppManager.open_chrome() end)
hs.hotkey.bind(_hyper, "b", "Open Arc Browser", function() AppManager.open_arc() end)
hs.hotkey.bind(hammer, "n", "Restore Window to Location 2", function() WindowToggler.restoreToLocation2() end)
hs.hotkey.bind(_hyper, "n", "Save Window to Location 2", function() WindowToggler.saveToLocation2() end)
hs.hotkey.bind(hammer, "m", "Toggle HammerGhost", function() spoon.HammerGhost:toggle() end)
hs.hotkey.bind(_hyper, "m", "HammerGhost Editor", function() spoon.HammerGhost:showActionEditor() end)

-- Keybindings - Space Row
hs.hotkey.bind(hammer, "Space", "Show Hammer Hotkeys", function() showHammerList() end)
hs.hotkey.bind(_hyper, "Space", "Show Hyper Hotkeys", function() showHyperList() end)
hs.hotkey.bind(_meta, "Space", "Toggle Hotkey Display Mode", function() toggleHotkeyDisplayMode() end)

-- Keybindings - Arrow Row
hs.hotkey.bind(hammer, "left", "Move Window Left", function() WindowManager.moveWindow("left") end)
hs.hotkey.bind(_hyper, "left", "Move to Previous Screen", function() WindowManager.moveToScreen("previous", "right") end)
hs.hotkey.bind(hammer, "right", "Move Window Right", function() WindowManager.moveWindow("right") end)
hs.hotkey.bind(_hyper, "right", "Move to Next Screen", function() WindowManager.moveToScreen("next", "right") end)
hs.hotkey.bind(hammer, "up", "Move Window Up", function() WindowManager.moveWindow("up") end)
hs.hotkey.bind(_hyper, "up", "Center Screen Layout", function() WindowManager.applyLayout('centerScreen') end)
hs.hotkey.bind(hammer, "down", "Move Window Down", function() WindowManager.moveWindow("down") end)
hs.hotkey.bind(_hyper, "down", "Bottom Half Layout", function() WindowManager.applyLayout('bottomHalf') end)

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

hs.hotkey.bind(_meta, "0", "Show Top Projects", function() showTopProjects() end)

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
