-- Spoons/HammerGhost.spoon/scripts/plugin_manager.lua

local M = {}
local action_system = dofile(hs.spoons.resourcePath("action_system.lua"))
local log = hs.logger.new("HammerGhost")

function M.loadPlugins()
    -- resourcePath resolves relative to THIS file's dir (scripts/), so the plugin
    -- folder is "../plugins", not "plugins" (which pointed at scripts/plugins and
    -- silently auto-created an empty dir -> no plugins ever loaded).
    local pluginDir = hs.spoons.resourcePath("../plugins")
    if not hs.fs.attributes(pluginDir) then
        hs.fs.mkdir(pluginDir)
        return
    end

    for file in hs.fs.dir(pluginDir) do
        if file:match("%.lua$") then
            local pluginPath = pluginDir .. "/" .. file
            local chunk, loadErr = loadfile(pluginPath)
            if not chunk then
                log:e("Error loading plugin " .. file .. ": " .. tostring(loadErr))
            else
                -- A plugin file is `return function(action_system) ... end`. Running
                -- the chunk yields that function; it must then be CALLED with the
                -- registry to register. (The old code ran the chunk and discarded
                -- the returned function, so nothing was ever registered.)
                local ranOk, result = pcall(chunk)
                if not ranOk then
                    log:e("Error running plugin " .. file .. ": " .. tostring(result))
                elseif type(result) == "function" then
                    local regOk, regErr = pcall(result, action_system)
                    if not regOk then
                        log:e("Error registering plugin " .. file .. ": " .. tostring(regErr))
                    end
                else
                    log:w("Plugin " .. file .. " did not return a function; skipped")
                end
            end
        end
    end
end

return M
