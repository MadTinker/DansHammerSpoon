-- Spoons/HammerGhost.spoon/plugins/flow_conditions.lua
--
-- EventGhost-parity conditions for flow control. Used to gate sequence steps
-- (a condition opens/closes the gate for the actions that follow it). Variable
-- conditions read action_system.variables -- the same store the setVariable
-- action writes and the {var.x} template token reads. Handlers return a boolean.

return function(action_system)
    -- variable == value (string compare; missing var -> "nil" string, so it only
    -- matches if the user literally typed "nil").
    action_system.registerConditionType("var_equals", {
        name = "Variable Equals",
        parameters = {
            name  = { type = "text", required = true, default = "" },
            value = { type = "text", required = false, default = "" }
        },
        handler = function(params)
            return tostring(action_system.variables[params.name]) == (params.value or "")
        end
    })

    -- variable contains substring (plain text find, not a Lua pattern).
    action_system.registerConditionType("var_contains", {
        name = "Variable Contains",
        parameters = {
            name      = { type = "text", required = true, default = "" },
            substring = { type = "text", required = true, default = "" }
        },
        handler = function(params)
            local hay = tostring(action_system.variables[params.name] or "")
            return string.find(hay, params.substring or "", 1, true) ~= nil
        end
    })

    -- variable > number (numeric; non-numeric var or threshold -> false).
    action_system.registerConditionType("var_gt", {
        name = "Variable > Number",
        parameters = {
            name   = { type = "text", required = true, default = "" },
            number = { type = "text", required = true, default = "0" }
        },
        handler = function(params)
            local a = tonumber(action_system.variables[params.name])
            local b = tonumber(params.number)
            return a ~= nil and b ~= nil and a > b
        end
    })

    -- an application is currently running (by name or bundle id).
    action_system.registerConditionType("app_running", {
        name = "App Is Running",
        parameters = {
            app = { type = "text", required = true, default = "" }
        },
        handler = function(params)
            return params.app ~= nil and params.app ~= "" and hs.application.get(params.app) ~= nil
        end
    })

    -- current time within [start_time, end_time] as "HH:MM". If start > end the
    -- window wraps past midnight (e.g. 22:00-06:00). Unparsable input -> false.
    action_system.registerConditionType("time_between", {
        name = "Time Between",
        parameters = {
            start_time = { type = "text", required = true, default = "09:00" },
            end_time   = { type = "text", required = true, default = "17:00" }
        },
        handler = function(params)
            local function toMinutes(s)
                local h, m = tostring(s or ""):match("^(%d%d?):(%d%d)$")
                if not h then return nil end
                return tonumber(h) * 60 + tonumber(m)
            end
            local startM = toMinutes(params.start_time)
            local endM = toMinutes(params.end_time)
            if not (startM and endM) then return false end
            local now = tonumber(os.date("%H")) * 60 + tonumber(os.date("%M"))
            if startM <= endM then
                return now >= startM and now <= endM
            else
                -- Wraps midnight: inside if after start OR before end.
                return now >= startM or now <= endM
            end
        end
    })
end
