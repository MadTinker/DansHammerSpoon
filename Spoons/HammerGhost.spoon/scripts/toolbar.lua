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
        {
            id = "importEG",
            label = "Import EG",
            image = hs.image.imageFromName("NSFolderSmart") or hs.image.imageFromName("NSFolder"),
            fn = function()
                -- Pick an EventGhost tree.xml and import its structure.
                local result = hs.dialog.chooseFileOrFolder(
                    "Select an EventGhost tree.xml to import",
                    os.getenv("HOME") or "~", true, false, false, { "xml" })
                local path = result and (result["1"] or result[1])
                if not path then return end
                local f = io.open(path, "r")
                if not f then
                    hs.alert.show("Could not read " .. tostring(path))
                    return
                end
                local content = f:read("*a")
                f:close()
                spoon:importMacros(content)
            end,
        },
    })

    return toolbar
end

return M
