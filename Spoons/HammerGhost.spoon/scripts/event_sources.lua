-- Spoons/HammerGhost.spoon/scripts/event_sources.lua
--
-- Thin wrappers over Hammerspoon's system watchers. Each source normalizes its
-- raw callback into an EventGhost-style dotted event name and emits it on the
-- shared event bus. Build 1 shipped the application watcher; Build 3 adds window
-- (focus/title/create/destroy), USB, and system-power sources. All hang off the
-- same idempotent start/stop pattern. Hotkey surfacing is deferred to a later
-- sub-task (it overlaps the existing hotkeys.lua bindings).

local eventBus = dofile(hs.spoons.resourcePath("event_bus.lua"))

local M = {}
M.appWatcher = nil
M.windowFilter = nil
M.usbWatcher = nil
M.caffeinateWatcher = nil

-- Last seen title per window id, so window.filter's chatty title-changed stream
-- only emits on an actual change. Pruned on windowDestroyed; wiped on stop.
M._winTitles = {}

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

function M.start()
    startAppWatcher()
    startWindowFilter()
    startUsbWatcher()
    startCaffeinateWatcher()
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
    M._winTitles = {}
end

return M
