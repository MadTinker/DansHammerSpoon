-- Spoons/HammerGhost.spoon/scripts/condition_editor.lua

local editor_window = dofile(hs.spoons.resourcePath("editor_window.lua"))

local M = {}

function M.create(spoon)
    return editor_window.create({
        x = 200, y = 200, w = 400, h = 500,
        title = "Condition Editor",
        html = "condition_editor.html",
        js = "condition_editor.js",
        handler = function(url) spoon:handleConditionEditorURL(url) end,
    })
end

return M
