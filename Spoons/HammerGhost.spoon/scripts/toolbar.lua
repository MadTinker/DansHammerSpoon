-- Spoons/HammerGhost.spoon/scripts/toolbar.lua

local M = {}

function M.create(spoon)
    local toolbar = hs.webview.toolbar.new({
        {
            id = "addFolder",
            label = "Add Folder",
            image = hs.image.imageFromName(hs.image.systemImageNames.folder),
            fn = function()
                spoon:addFolder()
            end,
        },
        {
            id = "addAction",
            label = "Add Action",
            image = hs.image.imageFromName(hs.image.systemImageNames.action),
            fn = function()
                spoon:addAction()
            end,
        },
        {
            id = "addSequence",
            label = "Add Sequence",
            image = hs.image.imageFromName(hs.image.systemImageNames.slideshow),
            fn = function()
                spoon:addSequence()
            end,
        },
        { id = "flexibleSpace" },
        {
            id = "save",
            label = "Save",
            image = hs.image.imageFromName(hs.image.systemImageNames.save),
            fn = function()
                spoon:saveConfig()
            end,
        },
        {
            id = "reload",
            label = "Reload",
            image = hs.image.imageFromName(hs.image.systemImageNames.refresh),
            fn = function()
                spoon:reloadConfig()
            end,
        },
    })

    return toolbar
end

return M
