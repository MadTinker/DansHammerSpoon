-- Spoons/HammerGhost.spoon/scripts/event_sources.lua
--
-- Thin wrappers over Hammerspoon's system watchers. Each source normalizes its
-- raw callback into an EventGhost-style dotted event name and emits it on the
-- shared event bus. Build 1 shipped the application watcher; Build 3 adds window
-- (focus/title/create/destroy), USB, and system-power sources. All hang off the
-- same idempotent start/stop pattern. The hotkey source is an eventtap that
-- surfaces modified keypresses as Hotkey.<mods+key> events (see startKeyTap) --
-- it observes every chord, including the ones hotkeys.lua already binds.

local eventBus = dofile(hs.spoons.resourcePath("event_bus.lua"))

local M = {}
M.appWatcher = nil
M.windowFilter = nil
M.usbWatcher = nil
M.caffeinateWatcher = nil
M.screenWatcher = nil
M.wifiWatcher = nil
M.keyTap = nil
M.mqttTask = nil

-- Last seen title per window id, so window.filter's chatty title-changed stream
-- only emits on an actual change. Pruned on windowDestroyed; wiped on stop.
M._winTitles = {}

-- Last seen screens (id -> name), so the screen watcher can diff added/removed
-- displays. Snapshot at start; wiped on stop.
M._screens = {}

-- Last seen Wi-Fi SSID (nil = disconnected), so the wifi watcher can emit
-- join/disconnect transitions. Snapshot at start; cleared on stop.
M._wifiSSID = nil

-- MQTT source state. Hammerspoon has no native MQTT, so we tail mosquitto_sub
-- as a long-lived hs.task and turn each "topic {json}" line into a bus event.
M._mqttBuf = ""        -- partial-line carry; stdout chunks aren't line-aligned
M._mqttRespawn = nil   -- backoff timer when the subscriber dies
M._mqttStopping = false -- set by M.stop() so the exit handler doesn't respawn

local MQTT_HOST = os.getenv("MADNESS_MQTT_HOST") or "localhost"
local MQTT_PORT = os.getenv("MADNESS_MQTT_PORT") or "1883"
-- Marker client-id: lets us (a) reap orphaned subs left by a prior hs.reload()
-- without nuking the user's manual debug subs, and (b) name the broker conn.
local MQTT_CLIENT_ID = "hammerghost"
-- madqtt's claude lifecycle topics (session/git/sessions/...). Lower volume and
-- meaningful as automation triggers. NOTE: activity/# is a firehose of every
-- tool call on this device -- since HammerGhost runs on the same mac the
-- claude-prime hooks publish from, subscribing to it logs this very session's
-- calls back at us. Opt in deliberately by adding the lines below.
local MQTT_TOPICS = {
    "status/+/claude/#",
    "+/status/+/claude/#",  -- dvttestkit prepends its module name as a prefix
    -- "status/+/activity/#",    -- opt-in: tool-call firehose (self-referential)
    -- "+/status/+/activity/#",
}

-- hs.application.watcher event constants -> readable verbs.
local APP_VERBS = {
    [hs.application.watcher.launched]    = "Launched",
    [hs.application.watcher.terminated]  = "Terminated",
    [hs.application.watcher.activated]   = "Activated",
    [hs.application.watcher.deactivated] = "Deactivated",
    [hs.application.watcher.hidden]      = "Hidden",
    [hs.application.watcher.unhidden]    = "Unhidden",
}

-- hs.caffeinate.watcher event constants -> System.* verbs. Only constants that
-- exist on this macOS build are mapped (some are screensaver-only legacy names).
local CAFFEINATE_VERBS = {}
do
    local cw = hs.caffeinate.watcher
    local map = {
        systemDidWake          = "DidWake",
        systemWillSleep        = "WillSleep",
        systemWillPowerOff     = "WillPowerOff",
        screensDidLock         = "ScreensDidLock",
        screensDidUnlock       = "ScreensDidUnlock",
        screensDidSleep        = "ScreensDidSleep",
        screensDidWake         = "ScreensDidWake",
        sessionDidResignActive = "SessionResignActive",
        sessionDidBecomeActive = "SessionBecomeActive",
        screensaverDidStart    = "ScreensaverDidStart",
        screensaverDidStop     = "ScreensaverDidStop",
        screensaverWillStop    = "ScreensaverWillStop",
    }
    for const, verb in pairs(map) do
        if cw[const] ~= nil then CAFFEINATE_VERBS[cw[const]] = verb end
    end
end

local function startAppWatcher()
    if M.appWatcher then return end
    M.appWatcher = hs.application.watcher.new(function(appName, eventType, app)
        local verb = APP_VERBS[eventType]
        if not verb then return end
        local name = string.format("App.%s.%s", verb, appName or "?")
        eventBus.emit(name, {
            app = appName,
            bundleID = app and app.bundleID and app:bundleID() or nil,
        })
    end)
    M.appWatcher:start()
end

local function startWindowFilter()
    if M.windowFilter then return end
    -- window.filter logs "X is STILL not registered" at warning level while it
    -- builds its app cache (menu-bar/headless apps never settle). We're the only
    -- filter consumer, so quiet it to errors-only to keep the console readable.
    hs.window.filter.setLogLevel("error")
    -- new() copies the curated default filter (already drops menus/popovers).
    -- Reject our own app so the live-log webview re-rendering can't feed back
    -- focus/title events into the bus.
    local wf = hs.window.filter.new()
    wf:setAppFilter("Hammerspoon", false)

    local function emitWin(verb, win, appName)
        local id = win and win.id and win:id() or nil
        eventBus.emit(string.format("Window.%s.%s", verb, appName or "?"), {
            app = appName,
            windowId = id,
            title = win and win.title and win:title() or nil,
        })
        return id
    end

    wf:subscribe(hs.window.filter.windowFocused, function(win, appName)
        emitWin("Focused", win, appName)
    end)
    wf:subscribe(hs.window.filter.windowCreated, function(win, appName)
        emitWin("Created", win, appName)
    end)
    wf:subscribe(hs.window.filter.windowDestroyed, function(win, appName)
        local id = emitWin("Destroyed", win, appName)
        if id then M._winTitles[id] = nil end  -- prune dedupe entry
    end)
    wf:subscribe(hs.window.filter.windowTitleChanged, function(win, appName)
        local id = win and win.id and win:id() or nil
        local title = win and win.title and win:title() or nil
        if id and M._winTitles[id] == title then return end  -- no real change
        if id then M._winTitles[id] = title end
        eventBus.emit(string.format("Window.TitleChanged.%s", appName or "?"), {
            app = appName,
            windowId = id,
            title = title,
        })
    end)
    -- Note: subscribe() defaults immediate=false, so no startup burst for the
    -- windows already open when init() runs (and it runs twice).
    M.windowFilter = wf
end

local function startUsbWatcher()
    if M.usbWatcher then return end
    M.usbWatcher = hs.usb.watcher.new(function(data)
        local verb = data.eventType == "removed" and "Removed" or "Added"
        local product = data.productName or "?"
        eventBus.emit(string.format("USB.%s.%s", verb, product), {
            productName = data.productName,
            vendorName  = data.vendorName,
            productID   = data.productID,
            vendorID    = data.vendorID,
        })
    end)
    M.usbWatcher:start()
end

local function startCaffeinateWatcher()
    if M.caffeinateWatcher then return end
    M.caffeinateWatcher = hs.caffeinate.watcher.new(function(eventType)
        local verb = CAFFEINATE_VERBS[eventType]
        if not verb then return end
        eventBus.emit("System." .. verb, {})
    end)
    M.caffeinateWatcher:start()
end

-- Snapshot current displays as { [id]=name }.
local function snapshotScreens()
    local snap = {}
    for _, s in ipairs(hs.screen.allScreens()) do
        snap[s:id()] = s:name() or tostring(s:id())
    end
    return snap
end

local function startScreenWatcher()
    if M.screenWatcher then return end
    M._screens = snapshotScreens()  -- baseline so the first change diffs cleanly
    -- hs.screen.watcher fires on any display add/remove/rearrange/resolution
    -- change. It carries no detail, so we diff against the last snapshot to tell
    -- which displays appeared or disappeared, then always emit LayoutChanged.
    M.screenWatcher = hs.screen.watcher.new(function()
        local now = snapshotScreens()
        for id, name in pairs(now) do
            if not M._screens[id] then eventBus.emit("Screen.Added." .. name, { name = name, id = id }) end
        end
        for id, name in pairs(M._screens) do
            if not now[id] then eventBus.emit("Screen.Removed." .. name, { name = name, id = id }) end
        end
        M._screens = now
        local names = {}
        for _, n in pairs(now) do names[#names + 1] = n end
        eventBus.emit("Screen.LayoutChanged", { count = #names, screens = names })
    end)
    M.screenWatcher:start()
end

local function startWifiWatcher()
    if M.wifiWatcher then return end
    M._wifiSSID = hs.wifi.currentNetwork()  -- baseline (nil if off/ethernet)
    -- Default hs.wifi.watcher fires on SSID change; the callback carries no
    -- useful detail, so we query currentNetwork() and diff against the last SSID
    -- to tell join from disconnect.
    M.wifiWatcher = hs.wifi.watcher.new(function()
        local cur = hs.wifi.currentNetwork()
        local prev = M._wifiSSID
        if cur and cur ~= prev then
            eventBus.emit("WiFi.Joined." .. cur, { ssid = cur, previous = prev })
        elseif not cur and prev then
            eventBus.emit("WiFi.Disconnected", { previous = prev })
        end
        M._wifiSSID = cur
        eventBus.emit("WiFi.SSIDChanged", { ssid = cur, previous = prev })
    end)
    M.wifiWatcher:start()
end

-- Hotkey source. An eventtap on keyDown surfaces modified keypresses as
-- Hotkey.<mods+key> bus events so ANY chord (whether or not hotkeys.lua binds it)
-- can trigger a macro. This is the firehose the rest of this file avoids -- the
-- user opted into it deliberately over a narrower per-binding emitter. Two guards
-- keep it from being a keylogger and from drowning the bus:
--   * Only chords carrying cmd/ctrl/alt emit. Plain typing and shift-only
--     capitals never fire, so no plaintext (passwords, messages) is surfaced --
--     the tap sees every key but emits nothing for unmodified ones.
--   * Auto-repeat is dropped, so holding a chord emits once, not a stream.
-- The callback returns false, so it never consumes the event -- the chord still
-- reaches apps and the existing hotkeys.lua binds. (A macro that itself synthesizes
-- a modified keystroke would be re-observed here; the dispatcher's depth cap is the
-- backstop against a feedback cascade.)
local HOTKEY_MODS = { "cmd", "ctrl", "alt", "shift" }  -- fixed order for stable names

local function chordName(flags, keyCode)
    -- Require a "real" modifier; shift alone is just capitalization, not a hotkey.
    if not (flags.cmd or flags.ctrl or flags.alt) then return nil end
    local key = hs.keycodes.map[keyCode]
    if not key or key == "" then return nil end  -- unmappable key (dead/media)
    local parts = {}
    for _, m in ipairs(HOTKEY_MODS) do
        if flags[m] then parts[#parts + 1] = m end
    end
    parts[#parts + 1] = key
    return table.concat(parts, "+")
end

local function startKeyTap()
    if M.keyTap then return end
    local autorepeat = hs.eventtap.event.properties.keyboardEventAutorepeat
    M.keyTap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(e)
        if e:getProperty(autorepeat) ~= 0 then return false end  -- one event per press
        local name = chordName(e:getFlags(), e:getKeyCode())
        if name then eventBus.emit("Hotkey." .. name, { key = name }) end
        return false  -- never consume; let the chord through to apps/other hotkeys
    end)
    M.keyTap:start()
    -- The tap silently no-ops without Accessibility; surface that so a dead hotkey
    -- source is diagnosable rather than mysteriously quiet.
    if _G.AppLogger and not hs.accessibilityState() then
        _G.AppLogger:w("Hotkey source: Accessibility not granted; no key events will fire",
            "event_sources.lua", 0)
    end
end

-- Resolve mosquitto_sub: Homebrew (arm/intel) first, then PATH.
local function resolveMosquittoSub()
    for _, c in ipairs({ "/opt/homebrew/bin/mosquitto_sub", "/usr/local/bin/mosquitto_sub" }) do
        if hs.fs.attributes(c) then return c end
    end
    local p = (hs.execute("/usr/bin/which mosquitto_sub") or ""):gsub("%s+$", "")
    return p ~= "" and p or nil
end

-- "topic {json}" -> MQTT.<dotted topic> with the decoded JSON as payload.
local function emitMqttLine(line)
    if line == "" then return end
    local topic, payload = line:match("^(%S+)%s(.*)$")
    if not topic then topic, payload = line, "" end
    local data
    if payload ~= "" then
        local ok, decoded = pcall(hs.json.decode, payload)
        data = (ok and type(decoded) == "table") and decoded or { raw = payload }
    else
        data = {}
    end
    eventBus.emit("MQTT." .. topic:gsub("/", "."), data)
end

local startMqttTask  -- forward decl for the respawn closure

startMqttTask = function()
    if M.mqttTask then return end
    local bin = resolveMosquittoSub()
    if not bin then
        if _G.AppLogger then
            _G.AppLogger:w("mosquitto_sub not found; MQTT source disabled", "event_sources.lua", 0)
        end
        return
    end
    -- Reap any subscriber orphaned by a previous hs.reload() (the Lua VM is
    -- recreated with mqttTask=nil while the old OS process may still be alive).
    -- Match our marker id so manual debug subs are untouched.
    hs.execute("/usr/bin/pkill -f 'mosquitto_sub.*" .. MQTT_CLIENT_ID .. "'")

    local args = { "-h", MQTT_HOST, "-p", MQTT_PORT, "-i", MQTT_CLIENT_ID, "-v" }
    for _, t in ipairs(MQTT_TOPICS) do
        args[#args + 1] = "-t"
        args[#args + 1] = t
    end

    M._mqttBuf = ""
    M.mqttTask = hs.task.new(bin,
        function(_exitCode)  -- done: subscriber exited (broker drop, kill, etc.)
            M.mqttTask = nil
            if M._mqttStopping then return end
            -- Respawn with backoff so a flapping broker doesn't hot-loop.
            if M._mqttRespawn then M._mqttRespawn:stop() end
            M._mqttRespawn = hs.timer.doAfter(5, function()
                M._mqttRespawn = nil
                startMqttTask()
            end)
        end,
        function(_task, stdOut, _stdErr)  -- stream: must return true to keep going
            M._mqttBuf = M._mqttBuf .. (stdOut or "")
            while true do
                local nl = M._mqttBuf:find("\n", 1, true)
                if not nl then break end
                local line = M._mqttBuf:sub(1, nl - 1)
                M._mqttBuf = M._mqttBuf:sub(nl + 1)
                emitMqttLine(line)
            end
            return true
        end,
        args)
    M.mqttTask:start()
end

function M.start()
    startAppWatcher()
    startWindowFilter()
    startUsbWatcher()
    startCaffeinateWatcher()
    startScreenWatcher()
    startWifiWatcher()
    startKeyTap()
    M._mqttStopping = false
    startMqttTask()
end

function M.stop()
    if M.appWatcher then
        M.appWatcher:stop()
        M.appWatcher = nil
    end
    if M.windowFilter then
        -- Nil-ing the field does NOT stop callbacks; they fire until GC.
        -- Unsubscribe explicitly before dropping the reference.
        M.windowFilter:unsubscribeAll()
        M.windowFilter = nil
    end
    if M.usbWatcher then
        M.usbWatcher:stop()
        M.usbWatcher = nil
    end
    if M.caffeinateWatcher then
        M.caffeinateWatcher:stop()
        M.caffeinateWatcher = nil
    end
    if M.screenWatcher then
        M.screenWatcher:stop()
        M.screenWatcher = nil
    end
    M._screens = {}
    if M.wifiWatcher then
        M.wifiWatcher:stop()
        M.wifiWatcher = nil
    end
    M._wifiSSID = nil
    if M.keyTap then
        M.keyTap:stop()
        M.keyTap = nil
    end
    -- MQTT: flag first so the exit handler doesn't respawn, then tear down.
    M._mqttStopping = true
    if M._mqttRespawn then
        M._mqttRespawn:stop()
        M._mqttRespawn = nil
    end
    if M.mqttTask then
        M.mqttTask:terminate()
        M.mqttTask = nil
    end
    M._mqttBuf = ""
    M._winTitles = {}
end

return M
