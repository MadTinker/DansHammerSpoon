-- Spoons/HammerGhost.spoon/scripts/plugin_manager.lua

local M = {}
local action_system = require("action_system")

function M.loadPlugins()
    local pluginDir = hs.spoons.resourcePath("plugins")
    if not hs.fs.attributes(pluginDir) then
        hs.fs.mkdir(pluginDir)
        return
    end

    for file in hs.fs.dir(pluginDir) do
        if file:match("%.lua$") then
            local pluginPath = pluginDir .. "/" .. file
            local plugin, err = loadfile(pluginPath)
            if plugin then
                -- The plugin is expected to be a function that takes the action system as an argument
                local ok, err = pcall(plugin, action_system)
                if not ok then
                    hs.logger.new("HammerGhost"):e("Error loading plugin " .. file .. ": " .. tostring(err))
                end
            else
                hs.logger.new("HammerGhost"):e("Error loading plugin " .. file .. ": " .. tostring(err))
            end
        end
    end
end

return M
