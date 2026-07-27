-- Hammerspoon init.lua
local __FILE__ = 'init.lua' -- Primary configuration file for Hammerspoon
hs.allowAppleScript(true) -- Enable AppleScript support
require("hs.ipc")
-- Load HyperLogger for better debugging with clickable log messages
local HyperLogger = require('HyperLogger')
-- Create a main application logger and expose it globally
local log = HyperLogger.new('HammerspoonApp')
-- Make the logger available globally for other modules
_G.AppLogger = log
log:d('Logger initialized', __FILE__, 10)

-- Console + hotkey control over log verbosity. Default is "info" (quiet);
-- cycleLogLevel() steps quiet->loud (info -> debug) across every namespace.
_G.cycleLogLevel = function()
    local level = HyperLogger.cycleGlobalLevel()
    hs.alert.show("Log level: " .. level)
    return level
end
_G.setLogLevel = function(level)
    local applied = HyperLogger.setGlobalLevel(level)
    hs.alert.show("Log level: " .. applied)
    return applied
end

-- Load secrets
local secrets = require("load_secrets")
log:d('Secrets module loaded', __FILE__, 14)

-- Configure environment variables from secrets
local AWSIP = secrets.get("AWSIP", "localhost")
local AWSIP2 = secrets.get("AWSIP2", "localhost")
local MCP_PORT = secrets.get("MCP_PORT", "8000")

-- Load additional modules and spoons
local loadConfigResult = require('loadConfig')

-- Setup OmniLadle global reference if it was successfully loaded and started
if spoon.OmniLadle then
    log:i('OmniLadle spoon loaded successfully - The mystical ladle is ready!', __FILE__, 25)
    -- Make OmniLadle globally available for other modules
    _G.OmniLadle = spoon.OmniLadle
else
    log:w('OmniLadle spoon not available - falling back to local project management', __FILE__, 28)
end

dofile(hs.configdir .. "/hotkeys.lua")

-- Load the HammerGhost spoon
hs.loadSpoon("HammerGhost")

-- Initialize the HammerGhost spoon (no window will be created automatically)
local hammerghost = spoon.HammerGhost:init()
if hammerghost then
    hs.logger.new("init.lua"):i("HammerGhost spoon initialized successfully.")
else
    hs.logger.new("init.lua"):e("Failed to initialize HammerGhost spoon.")
end

-- HammerGhost toggle consolidated to hotkeys.lua (hammer+h)

-- Control panel toggle moved to hotkeys.lua (hammer+g) to avoid conflict with GitHub Desktop binding

-- Configure Console Dark Mode
log:d('Configuring console appearance', __FILE__, 45)
local darkMode = {
    backgroundColor = { white = 0.1 },
    textColor = { white = 0.8 },
    cursorColor = { white = 0.8 },
    selectionColor = { red = 0.3, blue = 0.4, green = 0.35 },
    fontName = "Menlo",
    fontSize = 12
}

-- Apply console styling
hs.console.darkMode(true)
hs.console.windowBackgroundColor({
    red = 0.11,
    green = 0.11,
    blue = 0.11,
    alpha = 0.95
})
hs.console.outputBackgroundColor(darkMode.backgroundColor)
hs.console.consoleCommandColor(darkMode.textColor)
hs.console.consolePrintColor(darkMode.textColor)
hs.console.consoleResultColor({ white = 0.7 })
hs.console.alpha(0.95)
hs.console.titleVisibility("hidden")

-- Apply appearance after a short delay
hs.timer.doAfter(0.1, function()
    local consoleWindow = hs.console.hswindow()
    if consoleWindow and consoleWindow.setAppearance then
        consoleWindow:setAppearance(hs.drawing.windowAppearance.darkAqua)
    end
end)

-- Create and configure console toolbar
log:i('Creating console toolbar', __FILE__, 50)
local toolbar = require("hs.webview.toolbar")
local consoleTB = toolbar.new("myConsole", {
        {
            id = "editConfig",
            label = "Edit Config",
            image = hs.image.imageFromName("NSEditTemplate"),
            fn = function()
                local editor = "cursor" -- Use cursor as the editor
                local configFile = hs.configdir .. "/init.lua"
                if hs.fs.attributes(configFile) then
                    hs.task.new("/usr/bin/open", nil, { "-a", editor, configFile }):start()
                else
                    hs.alert.show("Could not find config file")
                end
            end
        },
        {
            id = "reloadConfig",
            label = "Reload",
            image = hs.image.imageFromName("NSRefreshTemplate"),
            fn = function()
                hs.reload()
                hs.alert.show("Config reloaded")
            end
        }
    })
    :canCustomize(true)
    :autosaves(true)

-- Apply the toolbar after a short delay
hs.timer.doAfter(0.2, function()
    hs.console.toolbar(consoleTB)
end)

-- Alert to indicate that the config has been loaded
hs.alert.show("Config loaded")

-- Macro Tree System
local macroTree = {
    Applications = {
        {
            name = "Development",
            icon = "NSApplicationIcon",
            items = {
                {
                    name = "Open VSCode",
                    icon = "NSEditTemplate",
                    fn = function() hs.application.launchOrFocus("Visual Studio Code") end
                },
                {
                    name = "Open PyCharm",
                    icon = "NSAdvanced",
                    fn = function() hs.application.launchOrFocus("PyCharm Community Edition") end
                },
                {
                    name = "Open Cursor",
                    icon = "NSComputer",
                    fn = function() hs.application.launchOrFocus("cursor") end
                }
            }
        },
        {
            name = "Browsers",
            icon = "NSNetwork",
            items = {
                {
                    name = "Open Chrome",
                    icon = "NSGlobe",
                    fn = function() hs.application.launchOrFocus("Google Chrome") end
                },
                {
                    name = "Open Arc",
                    icon = "NSBonjour",
                    fn = function() hs.application.launchOrFocus("Arc") end
                }
            }
        },
        {
            name = "Communication",
            icon = "NSChat",
            items = {
                {
                    name = "Open Slack",
                    icon = "NSShareTemplate",
                    fn = function() hs.application.launchOrFocus("Slack") end
                }
            }
        }
    },
    WindowManagement = {
        {
            name = "Basic Actions",
            icon = "NSPreferencesGeneral",
            items = {
                {
                    name = "Center Window",
                    icon = "NSCenterTextAlignment",
                    fn = function()
                        local win = hs.window.focusedWindow(); if win then win:centerOnScreen() end
                    end
                },
                {
                    name = "Full Screen",
                    icon = "NSEnterFullScreenTemplate",
                    fn = function()
                        local win = hs.window.focusedWindow(); if win then
                            local f = win:screen():frame(); win:setFrame(f)
                        end
                    end
                },
                {
                    name = "Save Position",
                    icon = "NSSaveTemplate",
                    fn = saveWindowPosition
                },
                {
                    name = "Restore Position",
                    icon = "NSRefreshTemplate",
                    fn = restoreWindowPosition
                }
            }
        },
        {
            name = "Screen Positions",
            icon = "NSMultipleWindows",
            items = {
                {
                    name = "Left Half",
                    icon = "NSGoLeftTemplate",
                    fn = function() moveSide("left", false) end
                },
                {
                    name = "Right Half",
                    icon = "NSGoRightTemplate",
                    fn = function() moveSide("right", false) end
                },
                {
                    name = "Top Left",
                    icon = "NSGoBackTemplate",
                    fn = function() moveToCorner("topLeft") end
                },
                {
                    name = "Top Right",
                    icon = "NSGoForwardTemplate",
                    fn = function() moveToCorner("topRight") end
                },
                {
                    name = "Bottom Left",
                    icon = "NSGoDownTemplate",
                    fn = function() moveToCorner("bottomLeft") end
                },
                {
                    name = "Bottom Right",
                    icon = "NSGoUpTemplate",
                    fn = function() moveToCorner("bottomRight") end
                }
            }
        },
        {
            name = "Layouts",
            icon = "NSListViewTemplate",
            items = {
                {
                    name = "Mini Layout",
                    icon = "NSFlowViewTemplate",
                    fn = miniShuffle
                },
                {
                    name = "Horizontal Split",
                    icon = "NSColumnViewTemplate",
                    fn = function() halfShuffle(true, 3) end
                },
                {
                    name = "Vertical Split",
                    icon = "NSTableViewTemplate",
                    fn = function() halfShuffle(false, 4) end
                }
            }
        }
    },
    System = {
        {
            name = "Power",
            icon = "NSStatusAvailable",
            items = {
                {
                    name = "Lock Screen",
                    icon = "NSLockLockedTemplate",
                    fn = function() hs.caffeinate.lockScreen() end
                },
                {
                    name = "Show Desktop",
                    icon = "NSHomeTemplate",
                    fn = function() hs.spaces.toggleMissionControl() end
                }
            }
        },
        {
            name = "Configuration",
            icon = "NSPreferencesGeneral",
            items = {
                {
                    name = "Edit Config",
                    icon = "NSEditTemplate",
                    fn = function()
                        local editor = "cursor"
                        local configFile = hs.configdir .. "/init.lua"
                        if hs.fs.attributes(configFile) then
                            hs.task.new("/usr/bin/open", nil, { "-a", editor, configFile }):start()
                        end
                    end
                },
                {
                    name = "Reload Config",
                    icon = "NSRefreshTemplate",
                    fn = function()
                        hs.reload(); hs.alert.show("Config reloaded")
                    end
                }
            }
        }
    }
}

-- Create the macro chooser
local breadcrumbs = {}
local macroChooser = hs.chooser.new(function(choice)
    if not choice then
        -- If user cancelled and we're in a subcategory, go back one level
        if #breadcrumbs > 0 then
            table.remove(breadcrumbs)
            showCurrentLevel()
        end
        return
    end

    if choice.fn then
        -- Execute the macro
        choice.fn()
        breadcrumbs = {}
    else
        -- Navigate to subcategory
        table.insert(breadcrumbs, choice.text)
        showCurrentLevel()
    end
end)

-- Function to get current level in the macro tree based on breadcrumbs
function getCurrentLevel()
    local current = macroTree
    for _, crumb in ipairs(breadcrumbs) do
        for _, category in pairs(current) do
            if category.name == crumb then
                current = category.items
                break
            end
        end
    end
    return current
end

-- Function to show current level in the chooser
function showCurrentLevel()
    local current = getCurrentLevel()
    local choices = {}

    -- Add back button if we're in a subcategory
    if #breadcrumbs > 0 then
        table.insert(choices, {
            text = "← Back",
            subText = "Return to previous menu",
            image = hs.image.imageFromName("NSGoLeftTemplate")
        })
    end

    -- Add items from current level
    for name, category in pairs(current) do
        -- Create image from system icon or fallback to text icon
        local img
        if category.icon then
            if category.icon:len() <= 2 then
                -- For emoji/text icons, create an attributed string
                img = hs.styledtext.new(category.icon, { font = { size = 16 } })
            else
                -- For system icons, use imageFromName
                img = hs.image.imageFromName(category.icon) or
                    hs.image.imageFromName("NSActionTemplate")
            end
        end

        table.insert(choices, {
            text = category.name,
            subText = category.items and "Open submenu" or "Execute action",
            image = img,
            fn = category.items and nil or category.fn
        })
    end

    -- Update chooser title to show breadcrumbs
    local title = "Macro Tree"
    if #breadcrumbs > 0 then
        title = table.concat(breadcrumbs, " → ")
    end
    macroChooser:placeholderText(title)

    macroChooser:choices(choices)
    macroChooser:show()
end

-- Function to show macro tree
function showMacroTree()
    breadcrumbs = {}
    showCurrentLevel()
end

-- Bind hotkey to show macro tree (Cmd+Alt+Ctrl+M)
-- hs.hotkey.bind({"cmd", "alt", "ctrl"}, "M", showMacroTree)

-- myWatcher = hs.pathwatcher.new(os.getenv("HOME") .. "/.hammerspoon/", reloadConfig):start()

-- hs.eventtap.new(hs.eventtap.event.types.middleMouseUp, function(event)

--     button = event:getProperty(hs.eventtap.event.properties.mouseEventButtonNumber)

--     current_app = hs.application.frontmostApplication()
--     google_chrome = hs.application.find("Google Chrome")

--     if (current_app == google_chrome) then
--         if (button == 3) then
--             hs.eventtap.keyStroke({"cmd"}, "[")
--         end

--         if (button == 4) then
--             hs.eventtap.keyStroke({"cmd"}, "]")
--         end
--     end
-- end):start()



--everyday at 9:45 am
hs.timer.doAt("4:30", "1d", function()
    hs.alert.show("Time to update Holly!")
end)




-- hs.loadSpoon('ExtendedClipboard')

-- Disable window animations for instant, reliable window positioning
hs.window.animationDuration = 0

white = hs.drawing.color.white
black = hs.drawing.color.black
blue = hs.drawing.color.blue
osx_red = hs.drawing.color.osx_red
osx_green = hs.drawing.color.osx_green
osx_yellow = hs.drawing.color.osx_yellow
tomato = hs.drawing.color.x11.tomato
dodgerblue = hs.drawing.color.x11.dodgerblue
firebrick = hs.drawing.color.x11.firebrick
lawngreen = hs.drawing.color.x11.lawngreen
lightseagreen = hs.drawing.color.x11.lightseagreen
purple = hs.drawing.color.x11.purple
royalblue = hs.drawing.color.x11.royalblue
sandybrown = hs.drawing.color.x11.sandybrown
black50 = { red = 0, blue = 0, green = 0, alpha = 0.5 }
darkblue = { red = 24 / 255, blue = 195 / 255, green = 145 / 255, alpha = 1 }
gray = { red = 246 / 255, blue = 246 / 255, green = 246 / 255, alpha = 0.3 }

--
-- MQTT Remote Command Handler
--
function handleRemoteCommand(command)
    local log = _G.AppLogger or hs.logger.new('MQTTHandler')
    log:d("Received remote command: " .. command)

    local remoteCommands = {
        -- Key Presses
        ["F1"] = function() hs.eventtap.keyStroke({}, 'f1') end,
        ["TAB"] = function() hs.eventtap.keyStroke({}, 'tab') end,
        ["PASTE"] = function() hs.eventtap.keyStroke({'cmd'}, 'v') end,
        ["COPY"] = function() hs.eventtap.keyStroke({'cmd'}, 'c') end,
        ["ENTER"] = function() hs.eventtap.keyStroke({}, 'return') end,

        -- Application Switching
        ["CHROME"] = function() hs.application.launchOrFocus('Google Chrome') end,
        ["WARP"] = function() hs.application.launchOrFocus('Warp') end,
        ["SLACK"] = function() hs.application.launchOrFocus('Slack') end,
        ["CURSOR"] = function() hs.application.launchOrFocus('Cursor') end,

        -- Window Management
        ["WIN_LEFT"] = function() hs.window.focusedWindow():move(hs.geometry.rect(0, 0, 0.5, 1), hs.screen.mainScreen(), true) end,
        ["WIN_RIGHT"] = function() hs.window.focusedWindow():move(hs.geometry.rect(0.5, 0, 0.5, 1), hs.screen.mainScreen(), true) end,
        ["WIN_MAX"] = function() hs.window.focusedWindow():maximize() end,

        -- System Control
        ["LOCK_SCREEN"] = function() hs.caffeinate.lockScreen() end,
    }

    local action = remoteCommands[command]
    if action then
        action()
    else
        log:w("No action defined for command: " .. command)
        hs.alert.show("Unknown Command", "Received: " .. command, 0.5)
    end
end

