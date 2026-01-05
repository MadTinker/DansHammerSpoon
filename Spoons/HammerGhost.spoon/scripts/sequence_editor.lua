-- Spoons/HammerGhost.spoon/scripts/sequence_editor.lua

local M = {}

function M.create(spoon)
    local editorWindow = hs.webview.new({
        x = 250,
        y = 250,
        w = 500,
        h = 600,
        show = false,
        title = "Sequence Editor",
        resizable = true,
        vibrancy = true,
        windowMasks = { "titled", "closable", "resizable" }
    })

    if not editorWindow then
        hs.logger.new("HammerGhost"):e("Failed to create sequence editor window")
        return nil
    end

    editorWindow:allowTextEntry(true)
    editorWindow:darkMode(true)

    editorWindow:navigationCallback(function(url)
        return spoon:handleSequenceEditorURL(url)
    end)

    local htmlPath = hs.spoons.resourcePath("assets/sequence_editor.html")
    local htmlContent = ""
    local file = io.open(htmlPath, "r")
    if file then
        htmlContent = file:read("*a")
        io.close(file)
    else
        hs.logger.new("HammerGhost"):e("Could not read sequence_editor.html")
    end
    editorWindow:html(htmlContent)

    return editorWindow
end

return M
