-- Spoons/HammerGhost.spoon/plugins/trigger_event.lua
--
-- WARNING (mirror action_system.lua's mqttPublish caveat): binding a trigger to
-- the SAME event name this action emits creates an infinite cascade through the
-- bus (TriggerEvent emits "X" -> trigger on "X" fires -> runs TriggerEvent ->
-- emits "X" -> ...). Pick event names that are NOT self-referential, or gate the
-- chain carefully.

return function(action_system)
    -- Fire a custom named event on the bus so other triggers can match it. The
    -- EventGhost analogue of eg.TriggerEvent -- lets a macro signal another macro.
    action_system.registerActionType("triggerEvent", {
        name = "Trigger Event",
        parameters = {
            name    = { type = "text",     required = true,  default = "Custom.MyEvent" },
            payload = { type = "textarea", required = false, default = "" }
        },
        handler = function(params)
            -- Empty/nil name: nothing to emit (emitEvent guards this too, but bail early).
            if not params.name or params.name == "" then return end
            -- Decode payload JSON into a table; on bad JSON keep the literal under `raw`
            -- so the downstream handler still gets *something*. Empty payload -> {}.
            local data
            if params.payload and params.payload ~= "" then
                local ok, decoded = pcall(hs.json.decode, params.payload)
                data = (ok and type(decoded) == "table") and decoded or { raw = params.payload }
            else
                data = {}
            end
            spoon.HammerGhost:emitEvent(params.name, data)
        end
    })
end
