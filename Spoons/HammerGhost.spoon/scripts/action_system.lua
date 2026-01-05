-- Spoons/HammerGhost.spoon/scripts/action_system.lua

local M = {}
M.actionTypes = {}
M.conditionTypes = {}

function M.registerActionType(name, def)
    M.actionTypes[name] = def
end

function M.registerConditionType(name, def)
    M.conditionTypes[name] = def
end

function M.getActionTypes()
    return M.actionTypes
end

function M.getConditionTypes()
    return M.conditionTypes
end

function M.executeAction(action)
    local def = M.actionTypes[action.actionType]
    if def and def.handler then
        def.handler(action.params)
    end
end

function M.executeCondition(condition)
    local def = M.conditionTypes[condition.conditionType]
    if def and def.handler then
        return def.handler(condition.params)
    end
    return false
end

-- Register some default action types
M.registerActionType("alert", {
    name = "Show Alert",
    parameters = {
        text = { type = "text", required = true, default = "Hello, World!" }
    },
    handler = function(params)
        hs.alert.show(params.text)
    end
})

M.registerActionType("executeScript", {
    name = "Execute Lua Script",
    parameters = {
        script = { type = "textarea", required = true, default = "print('Hello from Lua!')" }
    },
    handler = function(params)
        local fn, err = load(params.script)
        if fn then
            fn()
        else
            hs.alert.show("Error in script: " .. tostring(err))
        end
    end
})

-- Register some default condition types
M.registerConditionType("frontmost_window", {
    name = "Frontmost Window Title",
    parameters = {
        title = { type = "text", required = true, default = "Finder" },
        operator = { type = "select", options = {"contains", "is", "is not"}, required = true}
    },
    handler = function(params)
        local win = hs.window.frontmostWindow()
        if not win then return false end
        local title = win:title()
        if params.operator == "contains" then
            return title:find(params.title) ~= nil
        elseif params.operator == "is" then
            return title == params.title
        elseif params.operator == "is not" then
            return title ~= params.title
        end
        return false
    end
})


return M
