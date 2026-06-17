-- Spoons/HammerGhost.spoon/scripts/toolbar.lua

local M = {}

function M.create(spoon)
    local toolbar = hs.webview.toolbar.new("hammerghostToolbar", {
        {
            id = "addFolder",
            label = "Add Folder",
            image = hs.image.imageFromName("NSFolder"),
            fn = function()
                spoon:addFolder()
            end,
        },
        {
            id = "addTrigger",
            label = "Add Trigger",
            image = hs.image.imageFromName("NSAdvanced") or hs.image.imageFromName("NSActionTemplate"),
            fn = function()
                spoon:addTrigger()
            end,
        },
        {
            id = "addAction",
            label = "Add Action",
            image = hs.image.imageFromName("NSActionTemplate"),
            fn = function()
                spoon:addAction()
            end,
        },
        {
            id = "addSequence",
            label = "Add Sequence",
            image = hs.image.imageFromName("NSSlideshowTemplate"),
            fn = function()
                spoon:addSequence()
            end,
        },
        { id = "flexibleSpace" },
        {
            id = "save",
            label = "Save",
            image = hs.image.imageFromName("NSSavePanel"),
            fn = function()
                spoon:saveConfig()
            end,
        },
        {
            id = "reload",
            label = "Reload",
            image = hs.image.imageFromName("NSRefreshTemplate"),
            fn = function()
                spoon:reloadConfig()
            end,
        },
    })

    return toolbar
end

return M
