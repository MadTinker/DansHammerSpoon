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

-- Substitute {event.X} / {payload.X.Y} tokens in a string against the firing
-- event. e.g. "{payload.app} woke" with payload.app="Safari" -> "Safari woke".
--   - missing key ({payload.nope})  -> "" (so partial payloads don't error)
--   - unknown root ({HOME}, ${HOME}) -> left LITERAL. This is load-bearing, not
--     cosmetic: shell ${VAR} expansions in runShell must survive untouched.
--     Do NOT "simplify" this to return "" or every ${VAR} silently corrupts.
-- Non-strings and the no-event (manual run) case pass through unchanged.
local function tmpl(s, event)
    if type(s) ~= "string" or not event then return s end
    return (s:gsub("{([%w_%.]+)}", function(path)
        local segs = {}
        for seg in path:gmatch("[^.]+") do segs[#segs + 1] = seg end
        local cur
        if segs[1] == "event" then
            cur = event
        elseif segs[1] == "payload" then
            cur = event.payload
        else
            return "{" .. path .. "}"  -- unknown root: leave literal (see above)
        end
        for i = 2, #segs do
            if type(cur) ~= "table" then return "" end
            cur = cur[segs[i]]
        end
        if cur == nil then return "" end
        return tostring(cur)
    end))
end

-- Return a shallow copy of params with every string value templated against
-- event. Copy, never mutate: the original params live in the persisted tree and
-- must keep their {payload.app} literals for the next run.
local function expandParams(params, event)
    local out = {}
    for k, v in pairs(params or {}) do out[k] = tmpl(v, event) end
    return out
end

-- `event` is the bus event that fired the enclosing trigger (nil for manual
-- runs). String params are templated against it (see tmpl); handlers also get
-- event as a 2nd arg. executeScript is exempt from templating -- '{...}' is Lua
-- table syntax -- and instead receives event as a call arg (read via `...`).
function M.executeAction(action, event)
    local def = M.actionTypes[action.actionType]
    if not (def and def.handler) then return end
    if action.actionType == "executeScript" then
        def.handler(action.params or {}, event)
    else
        def.handler(expandParams(action.params, event), event)
    end
end

function M.executeCondition(condition, event)
    local def = M.conditionTypes[condition.conditionType]
    if def and def.handler then
        return def.handler(expandParams(condition.params, event), event)
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
    -- The script is NOT templated (it's Lua -- '{...}' is table syntax). Instead
    -- the firing event is passed as the call arg: read it with `local event = ...`
    -- then event.name / event.payload.foo. (nil on a manual run.)
    parameters = {
        script = { type = "textarea", required = true, default = "local event = ...\nprint(event and event.name)" }
    },
    handler = function(params, event)
        local fn, err = load(params.script)
        if fn then
            fn(event)
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
