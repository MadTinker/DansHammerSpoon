-- Spoons/HammerGhost.spoon/scripts/sequence_editor.lua

local editor_window = dofile(hs.spoons.resourcePath("editor_window.lua"))

local M = {}

function M.create(spoon)
    return editor_window.create({
        x = 250, y = 250, w = 500, h = 600,
        title = "Sequence Editor",
        html = "sequence_editor.html",
        js = "sequence_editor.js",
        handler = function(url) spoon:handleSequenceEditorURL(url) end,
    })
end

return M
