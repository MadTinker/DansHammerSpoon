-- Spoons/HammerGhost.spoon/scripts/action_system.lua

-- Singleton (mirrors event_bus.lua): dofile() does NOT cache -- each call re-runs
-- this file and returns a FRESH table. But init.lua and plugin_manager.lua each
-- dofile this module and MUST share one registry: plugins register through
-- plugin_manager's copy, while the editor dropdown and executor read init.lua's
-- copy. Without this guard those are different tables, so every plugin action /
-- condition (and the variable store the conditions read) is invisible and
-- non-executable. Stash the first instance on a global; later loads return it.
if rawget(_G, "_HammerGhostActionSystem") then
    return _G._HammerGhostActionSystem
end

local M = {}
_G._HammerGhostActionSystem = M
M.actionTypes = {}
M.conditionTypes = {}

-- Runtime variable store. setVariable writes here; any non-script param can read
-- a value back with the {var.name} token (see tmpl). Not persisted across
-- reloads yet -- these are live macro state, like EventGhost's eg.globals.
M.variables = {}

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

-- Serializable copies for the editor UI. The registered defs carry handler
-- closures, and hs.json.encode returns nil for any table holding a function --
-- which silently left the Type dropdown empty (populate*(nil) -> JS error).
-- Strip down to the pure data the editor needs.
local function uiCopy(types)
    local out = {}
    for name, def in pairs(types) do
        out[name] = { name = def.name, parameters = def.parameters }
    end
    return out
end

function M.getActionTypesForUI()
    return uiCopy(M.actionTypes)
end

function M.getConditionTypesForUI()
    return uiCopy(M.conditionTypes)
end

-- Substitute tokens in a string. Three roots:
--   {event.X}     - the firing event (event.name, ...)
--   {payload.X.Y} - the event payload (e.g. {payload.app})
--   {var.X}       - the runtime variable store (M.variables), works even on a
--                   manual run with no event.
-- Rules:
--   - missing key ({payload.nope}) -> "" (partial payloads don't error)
--   - event/payload tokens on a no-event (manual) run -> left LITERAL, so a
--     literal "{payload.app}" round-trips instead of vanishing.
--   - unknown root ({HOME}, ${HOME}) -> left LITERAL. Load-bearing, not cosmetic:
--     shell ${VAR} expansions in runShell must survive untouched. Do NOT
--     "simplify" this to return "".
-- Non-strings pass through unchanged.
local function tmpl(s, event)
    if type(s) ~= "string" then return s end
    return (s:gsub("{([%w_%.]+)}", function(path)
        local segs = {}
        for seg in path:gmatch("[^.]+") do segs[#segs + 1] = seg end
        local cur
        if segs[1] == "var" then
            cur = M.variables
        elseif segs[1] == "event" then
            if not event then return "{" .. path .. "}" end
            cur = event
        elseif segs[1] == "payload" then
            if not event then return "{" .. path .. "}" end
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
    -- Script-body actions take their body raw: templating would corrupt '{...}'
    -- literals (Lua tables, Python/JS dicts, AppleScript records). executeScript
    -- receives the event as a call arg; the others run in their own interpreter.
    if action.actionType == "executeScript"
        or action.actionType == "runScript"
        or action.actionType == "appleScript" then
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

-- Run a script in a chosen interpreter (sh/bash/python3/node). Non-blocking via
-- hs.task. hs.task needs an absolute interpreter path (it does NOT search PATH),
-- so python3/node are resolved against the usual install dirs. Output isn't
-- surfaced on success; a non-zero exit pops the stderr in an alert so failures
-- aren't silent. The code body is exempt from {event} templating (see
-- executeAction) -- use the firing event from inside the script's own world if
-- needed, or executeScript (Lua) for event-aware logic.
local function resolveBin(candidates, fallback)
    for _, p in ipairs(candidates) do
        if hs.fs.attributes(p) then return p end
    end
    return fallback
end

M.registerActionType("runScript", {
    name = "Run Script (sh / python / node)",
    parameters = {
        language = { type = "select", options = { "sh", "bash", "python3", "node" }, required = true },
        code     = { type = "textarea", required = true, default = "echo hello" },
    },
    handler = function(params)
        local code = params.code or ""
        if code == "" then return end
        local lang = params.language or "sh"
        local bin, args
        if lang == "sh" then
            bin, args = "/bin/sh", { "-c", code }
        elseif lang == "bash" then
            bin, args = "/bin/bash", { "-c", code }
        elseif lang == "python3" then
            bin = resolveBin({ "/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3" }, "/usr/bin/python3")
            args = { "-c", code }
        elseif lang == "node" then
            bin = resolveBin({ "/opt/homebrew/bin/node", "/usr/local/bin/node" }, "/usr/local/bin/node")
            args = { "-e", code }
        else
            hs.alert.show("Unknown script language: " .. tostring(lang))
            return
        end
        hs.task.new(bin, function(exitCode, _stdOut, stdErr)
            if exitCode ~= 0 then
                local detail = (stdErr and stdErr ~= "") and stdErr or ("exit " .. tostring(exitCode))
                hs.alert.show("Script failed (" .. lang .. "): " .. detail)
            end
            return true
        end, args):start()
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

-- Store a value in the runtime variable store, readable elsewhere as {var.name}.
-- value is templated before we get here, so value="{payload.app}" captures the
-- firing app, "{var.count}" chains off another variable, etc.
M.registerActionType("setVariable", {
    name = "Set Variable",
    parameters = {
        name  = { type = "text", required = true, default = "myVar" },
        value = { type = "text", required = false, default = "" },
    },
    handler = function(params)
        if params.name and params.name ~= "" then
            M.variables[params.name] = params.value or ""
        end
    end
})

-- Run an AppleScript. Body is raw (exempt from templating); errors alert.
M.registerActionType("appleScript", {
    name = "Run AppleScript",
    parameters = {
        script = { type = "textarea", required = true, default = 'display notification "hi from HammerGhost"' }
    },
    handler = function(params)
        local ok, _result, raw = hs.osascript.applescript(params.script or "")
        if not ok then
            local msg = (type(raw) == "table" and raw.NSLocalizedDescription) or "AppleScript failed"
            hs.alert.show("AppleScript error: " .. tostring(msg))
        end
    end
})

-- Fire an HTTP request (async, non-blocking). Optionally stash the response body
-- in a variable (resultVar) so a later action can use {var.<resultVar>}.
M.registerActionType("httpRequest", {
    name = "HTTP Request",
    parameters = {
        url       = { type = "text", required = true, default = "https://" },
        method    = { type = "select", options = { "GET", "POST" }, required = true },
        body      = { type = "textarea", required = false, default = "" },
        resultVar = { type = "text", required = false, default = "" },
    },
    handler = function(params)
        local url = params.url or ""
        if url == "" then return end
        local method = string.upper(params.method or "GET")
        local function onResp(status, respBody)
            if params.resultVar and params.resultVar ~= "" then
                M.variables[params.resultVar] = respBody or ""
            end
            if not status or status < 0 or status >= 400 then
                hs.alert.show("HTTP " .. tostring(status) .. " " .. url)
            end
        end
        if method == "POST" then
            hs.http.asyncPost(url, params.body or "", nil, onResp)
        else
            hs.http.asyncGet(url, nil, onResp)
        end
    end
})

-- Put text on the clipboard.
M.registerActionType("clipboardSet", {
    name = "Set Clipboard",
    parameters = {
        text = { type = "text", required = true, default = "" }
    },
    handler = function(params)
        hs.pasteboard.setContents(params.text or "")
    end
})

-- Wait/Delay: pause the running macro for N seconds WITHOUT blocking the main
-- thread. This works because runItem/_dispatchEvent run a macro inside a coroutine
-- (see init.lua driveMacro); yielding the seconds suspends the walk and the driver
-- resumes it via hs.timer. Outside a coroutine (the main thread) it's a no-op -- we
-- never busy-wait and freeze the UI.
M.registerActionType("delay", {
    name = "Wait / Delay (seconds)",
    parameters = {
        seconds = { type = "text", required = true, default = "1" }
    },
    handler = function(params)
        local secs = tonumber(params.seconds)
        if not (secs and secs > 0) then return end
        local _, isMain = coroutine.running()
        if not isMain then
            coroutine.yield(secs)
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
