-- Spoons/HammerGhost.spoon/plugins/sample_plugin.lua

return function(action_system)
    action_system.registerActionType("sample_action", {
        name = "Sample Action",
        parameters = {
            message = { type = "text", required = true, default = "This is a sample action" }
        },
        handler = function(params)
            hs.alert.show(params.message)
        end
    })

    action_system.registerConditionType("sample_condition", {
        name = "Sample Condition",
        parameters = {
            value = { type = "text", required = true, default = "hello" }
        },
        handler = function(params)
            return params.value == "hello"
        end
    })
end
