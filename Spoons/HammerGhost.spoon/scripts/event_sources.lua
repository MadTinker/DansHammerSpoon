-- Spoons/HammerGhost.spoon/scripts/event_sources.lua
--
-- Thin wrappers over Hammerspoon's system watchers. Each source normalizes its
-- raw callback into an EventGhost-style dotted event name and emits it on the
-- shared event bus. Build 1 ships the application watcher only; window, hotkey,
-- usb, and caffeinate sources hang off the same start/stop pattern later.

local eventBus = dofile(hs.spoons.resourcePath("event_bus.lua"))

local M = {}
M.appWatcher = nil

-- hs.application.watcher event constants -> readable verbs.
local APP_VERBS = {
    [hs.application.watcher.launched]    = "Launched",
    [hs.application.watcher.terminated]  = "Terminated",
    [hs.application.watcher.activated]   = "Activated",
    [hs.application.watcher.deactivated] = "Deactivated",
    [hs.application.watcher.hidden]      = "Hidden",
    [hs.application.watcher.unhidden]    = "Unhidden",
}

function M.start()
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

function M.stop()
    if M.appWatcher then
        M.appWatcher:stop()
        M.appWatcher = nil
    end
end

return M
