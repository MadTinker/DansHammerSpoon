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
        {
            id = "addCondition",
            label = "Add Condition",
            image = hs.image.imageFromName("NSStatusAvailable") or hs.image.imageFromName("NSActionTemplate"),
            fn = function()
                spoon:addCondition()
            end,
        },
        {
            id = "runSelected",
            label = "Run Selected",
            image = hs.image.imageFromName("NSTouchBarPlayTemplate")
                or hs.image.imageFromName("NSGoRightTemplate")
                or hs.image.imageFromName("NSActionTemplate"),
            fn = function()
                local sel = spoon:getCurrentSelection()
                if sel then
                    spoon:runItem(sel.id)
                else
                    hs.alert.show("Select an item to run")
                end
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
