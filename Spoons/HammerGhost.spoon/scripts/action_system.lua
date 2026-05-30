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

-- `event` is the bus event that fired the enclosing trigger (nil for manual
-- runs). Passed as the handler's 2nd arg so payload-aware actions can read
-- event.payload / event.name; handlers that take only (params) ignore it.
function M.executeAction(action, event)
    local def = M.actionTypes[action.actionType]
    if def and def.handler then
        def.handler(action.params or {}, event)
    end
end

function M.executeCondition(condition, event)
    local def = M.conditionTypes[condition.conditionType]
    if def and def.handler then
        return def.handler(condition.params or {}, event)
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

-- Launch or focus an application by name.
M.registerActionType("launchApp", {
    name = "Launch / Focus App",
    parameters = {
        app = { type = "text", required = true, default = "Finder" }
    },
    handler = function(params)
        if params.app and params.app ~= "" then
            hs.application.launchOrFocus(params.app)
        end
    end
})

-- Send a keystroke: comma-separated modifiers + a key. e.g. mods="cmd,shift".
M.registerActionType("keyStroke", {
    name = "Send Keystroke",
    parameters = {
        mods = { type = "text", required = false, default = "cmd" },
        key  = { type = "text", required = true,  default = "space" }
    },
    handler = function(params)
        local mods = {}
        for m in tostring(params.mods or ""):gmatch("[^,%s]+") do mods[#mods + 1] = m end
        if params.key and params.key ~= "" then
            hs.eventtap.keyStroke(mods, params.key, 0)
        end
    end
})

-- Type a literal string at the cursor.
M.registerActionType("typeText", {
    name = "Type Text",
    parameters = {
        text = { type = "text", required = true, default = "" }
    },
    handler = function(params)
        if params.text and params.text ~= "" then
            hs.eventtap.keyStrokes(params.text)
        end
    end
})

-- Run a shell command. Non-blocking via hs.task -- hs.execute would block the
-- Hammerspoon main thread and stall the event loop.
M.registerActionType("runShell", {
    name = "Run Shell Command",
    parameters = {
        command = { type = "textarea", required = true, default = "echo hello" }
    },
    handler = function(params)
        if params.command and params.command ~= "" then
            hs.task.new("/bin/sh", nil, { "-c", params.command }):start()
        end
    end
})

-- Open a URL (or file path) with the default handler.
M.registerActionType("openURL", {
    name = "Open URL",
    parameters = {
        url = { type = "text", required = true, default = "https://" }
    },
    handler = function(params)
        if params.url and params.url ~= "" then
            hs.urlevent.openURL(params.url)
        end
    end
})

-- Post a macOS notification.
M.registerActionType("notify", {
    name = "Notification",
    parameters = {
        title = { type = "text", required = false, default = "HammerGhost" },
        text  = { type = "text", required = true,  default = "" }
    },
    handler = function(params)
        hs.notify.new({
            title = params.title or "HammerGhost",
            informativeText = params.text or "",
        }):send()
    end
})

-- Layout the focused window: maximize | left | right | center.
M.registerActionType("windowLayout", {
    name = "Window Layout",
    parameters = {
        layout = { type = "select", options = { "maximize", "left", "right", "center" }, required = true }
    },
    handler = function(params)
        local win = hs.window.focusedWindow()
        if not win then return end
        local layout = params.layout or "maximize"
        if layout == "maximize" then
            win:maximize()
        elseif layout == "left" then
            win:move(hs.geometry.rect(0, 0, 0.5, 1), nil, true)
        elseif layout == "right" then
            win:move(hs.geometry.rect(0.5, 0, 0.5, 1), nil, true)
        elseif layout == "center" then
            win:centerOnScreen()
        end
    end
})

-- Publish a message to MQTT (closes the loop with madqtt). WARNING: pairing this
-- with a MQTT.* trigger creates an infinite loop through the broker (publish ->
-- our own mosquitto_sub receives -> emit -> dispatch -> publish). Topic your
-- publishes outside the subscribed status/+/claude/# space, or gate carefully.
M.registerActionType("mqttPublish", {
    name = "MQTT Publish",
    parameters = {
        topic   = { type = "text", required = true, default = "status/macbook/hammerghost/out" },
        message = { type = "text", required = true, default = "1" }
    },
    handler = function(params)
        if not params.topic or params.topic == "" then return end
        local host = os.getenv("MADNESS_MQTT_HOST") or "localhost"
        local port = os.getenv("MADNESS_MQTT_PORT") or "1883"
        local bin = hs.fs.attributes("/opt/homebrew/bin/mosquitto_pub")
            and "/opt/homebrew/bin/mosquitto_pub" or "mosquitto_pub"
        hs.task.new(bin, nil, {
            "-h", host, "-p", port,
            "-t", params.topic, "-m", tostring(params.message or ""),
        }):start()
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
M.registerConditionType("frontmost_app", {
    name = "Frontmost Application",
    parameters = {
        app = { type = "text", required = true, default = "Finder" },
        operator = { type = "select", options = { "is", "is not", "contains" }, required = true }
    },
    handler = function(params)
        local app = hs.application.frontmostApplication()
        local name = app and app:name() or ""
        if params.operator == "is" then
            return name == params.app
        elseif params.operator == "is not" then
            return name ~= params.app
        elseif params.operator == "contains" then
            return name:find(params.app, 1, true) ~= nil
        end
        return false
    end
})


return M
