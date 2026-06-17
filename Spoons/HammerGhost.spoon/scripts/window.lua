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

    -- Intercept custom-scheme navigations via the policy decision callback.
    -- navigationCallback only reports navigation *lifecycle* events (didStart/
    -- didFinish/didFail) and never delivers the request URL for a hammerspoon://
    -- link, so the URL bridge must live here. For a "navigationAction" the URL is
    -- at details.request.URL.url; returning false denies the load and keeps the
    -- current page (no provisional-navigation failure / blank-out).
    window:policyCallback(function(action, webView, details)
        if action == "navigationAction" then
            local request = details and details.request
            local urlObj = request and request.URL
            local url = urlObj and urlObj.url or ""
            if url:match("^hammerspoon://") then
                spoon:handleURL(url)
                return false -- deny navigation, stay on current page
            end
        end
        return true -- allow all other navigations (initial page load, etc.)
    end)

    return window
end

return M
