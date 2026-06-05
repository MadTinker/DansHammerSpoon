-- Spoons/HammerGhost.spoon/plugins/mouse_actions.lua
--
-- EventGhost-parity mouse actions: synthetic click / move / scroll. Params arrive
-- as strings (templated upstream), so every numeric field is tonumber'd with a
-- nil guard before it reaches an hs.eventtap/hs.mouse call.

return function(action_system)
    -- Click at an explicit point, or at the current cursor if x/y are blank.
    -- Empty-string defaults so an unset coordinate means "click where the mouse
    -- already is" rather than snapping to (0,0).
    action_system.registerActionType("mouseClick", {
        name = "Mouse Click",
        parameters = {
            x      = { type = "text",   required = false, default = "" },
            y      = { type = "text",   required = false, default = "" },
            button = { type = "select", options = { "left", "right" }, required = false },
        },
        handler = function(params)
            -- Synthetic clicks need Accessibility; warn+prompt once if missing.
            if not action_system.requireAccessibility() then return end
            local x = tonumber(params.x)
            local y = tonumber(params.y)
            -- Only honor an explicit point when BOTH coords parse; a half-filled
            -- pair falls back to the live cursor instead of a bogus (x,0)/(0,y).
            local point = (x and y) and { x = x, y = y } or hs.mouse.absolutePosition()
            if params.button == "right" then
                hs.eventtap.rightClick(point)
            else
                hs.eventtap.leftClick(point)
            end
        end
    })

    -- Warp the cursor to an absolute screen coordinate. Defaults to (0,0).
    action_system.registerActionType("mouseMove", {
        name = "Move Mouse",
        parameters = {
            x = { type = "text", default = "0" },
            y = { type = "text", default = "0" },
        },
        handler = function(params)
            hs.mouse.absolutePosition({ x = tonumber(params.x) or 0, y = tonumber(params.y) or 0 })
        end
    })

    -- Scroll the wheel by line increments. dy is negative-down per macOS line
    -- scrolling; default -10 scrolls down a chunk, dx default 0 is vertical-only.
    action_system.registerActionType("mouseScroll", {
        name = "Scroll Wheel",
        parameters = {
            dx = { type = "text", default = "0" },
            dy = { type = "text", default = "-10" },
        },
        handler = function(params)
            if not action_system.requireAccessibility() then return end
            hs.eventtap.scrollWheel({ tonumber(params.dx) or 0, tonumber(params.dy) or 0 }, {}, "line")
        end
    })
end
