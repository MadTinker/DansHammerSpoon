-- hs.loadSpoon("ModalMgr")
local __FILE__ = 'loadConfig.lua'
local loadConfig = {} -- Create module table

-- Define default Spoons which will be loaded
local hspoon_list = {
    -- "OmniLadle", -- MCP client spoon for centralized project management
    "AClock",
    "EmmyLua",
    "ClipShow",
    -- "ClipboardTool",
    "DragonGrid",
    "Layouts",
    "KineticLatch", -- The Mad Tinker's Window Manipulation Contraption! 🔧⚡
    -- Disabled/Optional Spoons (uncomment to enable)
    -- "BingDaily",
    -- "CircleClock",
    -- "CountDown",
    -- "HammerGhost",
    -- "HSKeybindings",
    -- "SpoonInstall",
    -- "HCalendar",
    -- "HSaria2",
    -- "HSearch",
    -- "SpeedMenu",
    -- "WinWin",
    -- "FnMate",
}

-- Logger for Spoon loading
local HyperLogger = require('HyperLogger')
local log = HyperLogger.new()

log:d('Loading Spoons', __FILE__, 31)

-- Load Spoons with error handling
local loaded_spoons = {}
local failed_spoons = {}

for _, spoon_name in pairs(hspoon_list) do
    log:d('Attempting to load Spoon: ' .. spoon_name, __FILE__, 38)
    local success, error_msg = pcall(function() hs.loadSpoon(spoon_name) end)

    if success and spoon[spoon_name] then
        table.insert(loaded_spoons, spoon_name)
        log:d('Successfully loaded Spoon: ' .. spoon_name, __FILE__, 43)
    else
        table.insert(failed_spoons, spoon_name)
        log:e('Failed to load Spoon: ' .. spoon_name .. (error_msg and (' - ' .. error_msg) or ''), __FILE__, 46)
    end
end

log:i('Loaded ' .. #loaded_spoons .. ' Spoons, ' .. #failed_spoons .. ' failed', __FILE__, 50)

-- Start each spoon that has a start function
local started_spoons = {}
for _, spoon_name in pairs(loaded_spoons) do
    if spoon[spoon_name] and type(spoon[spoon_name].start) == "function" then
        log:d('Starting Spoon: ' .. spoon_name, __FILE__, 55)
        local success, error_msg = pcall(function() spoon[spoon_name]:start() end)

        if success then
            table.insert(started_spoons, spoon_name)
            log:d('Successfully started Spoon: ' .. spoon_name, __FILE__, 60)
        else
            log:e('Failed to start Spoon: ' .. spoon_name .. (error_msg and (' - ' .. error_msg) or ''), __FILE__, 62)
        end
    end
end

log:i('Started ' .. #started_spoons .. ' Spoons', __FILE__, 66)

-- Add results to the module table
loadConfig.loaded = loaded_spoons
loadConfig.failed = failed_spoons
loadConfig.started = started_spoons

-- Return module for require()
return loadConfig
