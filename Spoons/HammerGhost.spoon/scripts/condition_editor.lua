-- Spoons/HammerGhost.spoon/scripts/condition_editor.lua

local M = {}

function M.create(spoon)
    local editorWindow = hs.webview.new({
        x = 200,
        y = 200,
        w = 400,
        h = 500,
        show = false,
        title = "Condition Editor",
        resizable = true,
        vibrancy = true,
        windowMasks = { "titled", "closable", "resizable" }
    })

    if not editorWindow then
        hs.logger.new("HammerGhost"):e("Failed to create condition editor window")
        return nil
    end

    editorWindow:allowTextEntry(true)
    editorWindow:darkMode(true)

    editorWindow:navigationCallback(function(url)
        return spoon:handleConditionEditorURL(url)
    end)

    local htmlPath = hs.spoons.resourcePath("assets/condition_editor.html")
    local htmlContent = ""
    local file = io.open(htmlPath, "r")
    if file then
        htmlContent = file:read("*a")
        io.close(file)
    else
        hs.logger.new("HammerGhost"):e("Could not read condition_editor.html")
    end
    editorWindow:html(htmlContent)

    return editorWindow
end

return M
