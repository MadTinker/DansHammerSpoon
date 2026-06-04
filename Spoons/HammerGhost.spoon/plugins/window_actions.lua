-- Spoons/HammerGhost.spoon/plugins/window_actions.lua
--
-- EventGhost-parity window management actions. Mirrors the windowLayout action
-- in scripts/action_system.lua: layouts are expressed as screen-relative unit
-- rects -- hs.geometry.rect(x, y, w, h) with the trailing `true` telling
-- win:move the rect is a fraction of the screen, not points. Halves take 0.5 in
-- one axis; quarters are 0.5 x 0.5 anchored at the matching corner. Every
-- handler bails on a nil focused window so a no-window run is a no-op rather
-- than an error.

return function(action_system)
    -- Unit rects keyed by the position select. Reused by the moveWindow
    -- handler; maximize/center are special-cased (no rect) below.
    local POSITIONS = {
        ["left-half"]    = hs.geometry.rect(0,   0,   0.5, 1),
        ["right-half"]   = hs.geometry.rect(0.5, 0,   0.5, 1),
        ["top-half"]     = hs.geometry.rect(0,   0,   1,   0.5),
        ["bottom-half"]  = hs.geometry.rect(0,   0.5, 1,   0.5),
        ["top-left"]     = hs.geometry.rect(0,   0,   0.5, 0.5),
        ["top-right"]    = hs.geometry.rect(0.5, 0,   0.5, 0.5),
        ["bottom-left"]  = hs.geometry.rect(0,   0.5, 0.5, 0.5),
        ["bottom-right"] = hs.geometry.rect(0.5, 0.5, 0.5, 0.5),
    }

    action_system.registerActionType("moveWindow", {
        name = "Move/Resize Window",
        parameters = {
            position = {
                type = "select",
                options = {
                    "left-half", "right-half", "top-half", "bottom-half",
                    "top-left", "top-right", "bottom-left", "bottom-right",
                    "maximize", "center",
                },
                required = true,
            },
        },
        handler = function(params)
            local win = hs.window.focusedWindow()
            if not win then return end
            local position = params.position
            if position == "maximize" then
                win:maximize()
            elseif position == "center" then
                win:centerOnScreen()
            else
                local rect = POSITIONS[position]
                if rect then
                    win:move(rect, nil, true)
                end
            end
        end,
    })

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
