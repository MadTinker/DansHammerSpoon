-- Spoons/HammerGhost.spoon/scripts/action_chooser.lua

local M = {}

function M.create(spoon)
    local chooserWindow = hs.webview.new({
        x = 300,
        y = 300,
        w = 300,
        h = 400,
        show = false,
        title = "Choose Action",
        resizable = true,
        vibrancy = true,
        windowMasks = { "titled", "closable", "resizable" }
    })

    if not chooserWindow then
        hs.logger.new("HammerGhost"):e("Failed to create action chooser window")
        return nil
    end

    chooserWindow:allowTextEntry(true)
    chooserWindow:darkMode(true)

    chooserWindow:navigationCallback(function(url)
        return spoon:handleActionChooserURL(url)
    end)

    local htmlPath = hs.spoons.resourcePath("assets/action_chooser.html")
    local htmlContent = ""
    local file = io.open(htmlPath, "r")
    if file then
        htmlContent = file:read("*a")
        io.close(file)
    else
        hs.logger.new("HammerGhost"):e("Could not read action_chooser.html")
    end
    chooserWindow:html(htmlContent)

    return chooserWindow
end

return M
