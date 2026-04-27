-- Spoons/HammerGhost.spoon/scripts/window.lua

local M = {}

function M.create(spoon)
    -- Create and configure the main window
    local window = hs.webview.new({
        x = 100,
        y = 100,
        w = 800,
        h = 600,
        show = false,
        title = "HammerGhost",
        resizable = true,
        vibrancy = true,
        windowMasks = { "titled", "closable", "miniaturizable", "resizable" }
    })

    if not window then
        hs.logger.new("HammerGhost"):e("Failed to create main window")
        return nil
    end

    window:allowTextEntry(true)
    window:darkMode(true)
    window:windowStyle({ "titled", "closable", "miniaturizable", "resizable" })
    window:level(hs.drawing.windowLevels.floating)
    window:allowNewWindows(false)

    -- navigationCallback receives (action, webView, navID, extra)
    -- For "navigationAction", extra.URL has the actual URL
    window:navigationCallback(function(action, webView, navID, extra)
        if action == "navigationAction" then
            local url = extra and extra.URL or ""
            if url:match("^hammerspoon://") then
                spoon:handleURL(url)
                return false -- block navigation, keep current page
            end
            return true -- allow other navigations
        elseif action == "webViewShouldClose" then
            return false -- prevent accidental close
        end
    end)

    return window
end

return M
