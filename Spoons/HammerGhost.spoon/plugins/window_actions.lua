-- Spoons/HammerGhost.spoon/plugins/window_actions.lua
--
-- EventGhost-parity window management. Position/resize lives in the core
-- "windowLayout" action (scripts/action_system.lua, which absorbed the old
-- moveWindow superset); this plugin adds what windowLayout doesn't cover:
-- minimize, fullscreen toggle, and move-to-display. Every handler bails on a nil
-- focused window so a no-window run is a no-op rather than an error.

return function(action_system)
    action_system.registerActionType("minimizeWindow", {
        name = "Minimize Window",
        parameters = {},
        handler = function()
            local win = hs.window.focusedWindow()
            if not win then return end
            win:minimize()
        end,
    })

    action_system.registerActionType("toggleFullscreen", {
        name = "Toggle Fullscreen",
        parameters = {},
        handler = function()
            local win = hs.window.focusedWindow()
            if not win then return end
            win:toggleFullScreen()
        end,
    })

    action_system.registerActionType("moveToDisplay", {
        name = "Move Window to Display",
        parameters = {
            direction = {
                type = "select",
                options = { "next", "previous" },
                required = true,
            },
        },
        handler = function(params)
            local win = hs.window.focusedWindow()
            if not win then return end
            local scr = win:screen()
            if not scr then return end
            local target = (params.direction == "previous") and scr:previous() or scr:next()
            if target then
                win:moveToScreen(target)
            end
        end,
    })
end
