-- Spoons/HammerGhost.spoon/scripts/action_chooser.lua

local editor_window = dofile(hs.spoons.resourcePath("editor_window.lua"))

local M = {}

function M.create(spoon)
    return editor_window.create({
        x = 300, y = 300, w = 300, h = 400,
        title = "Choose Action",
        html = "action_chooser.html",
        js = "action_chooser.js",
        handler = function(url) spoon:handleActionChooserURL(url) end,
    })
end

return M
