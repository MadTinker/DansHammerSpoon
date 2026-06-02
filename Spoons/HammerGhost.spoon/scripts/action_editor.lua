-- Spoons/HammerGhost.spoon/scripts/action_editor.lua

local editor_window = dofile(hs.spoons.resourcePath("editor_window.lua"))

local M = {}

function M.create(spoon)
    return editor_window.create({
        x = 200, y = 200, w = 400, h = 500,
        title = "Action Editor",
        html = "action_editor.html",
        js = "action_editor.js",
        handler = function(url) spoon:handleActionEditorURL(url) end,
    })
end

return M
