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

    -- Set the navigation callback to handle JavaScript-to-Lua communication
    window:navigationCallback(function(url)
        return spoon:handleURL(url)
    end)

    return window
end

return M
