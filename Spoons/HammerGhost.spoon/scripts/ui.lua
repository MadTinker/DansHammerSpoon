-- Spoons/HammerGhost.spoon/scripts/ui.lua

local window_manager = require("window")
local toolbar_manager = require("toolbar")
local webview_manager = require("webview")
local properties_manager = require("properties")

local M = {}

function M.createMainWindow(spoon)
    spoon.window = window_manager.create(spoon)
    if not spoon.window then
        return
    end

    spoon.toolbar = toolbar_manager.create(spoon)
    spoon.window:attachedToolbar(spoon.toolbar)

    webview_manager.init(spoon)
    webview_manager.refresh(spoon)

    spoon.window:show()
end

function M.refresh(spoon)
    webview_manager.refresh(spoon)
end

function M.showProperties(spoon, item)
    properties_manager.show(spoon, item)
end

function M.clearProperties(spoon)
    properties_manager.clear(spoon)
end

function M.handleURL(spoon, url)
    local cmd, args = url:match("hammerspoon://([^?]+)%??(.*)")

    if not cmd then
        return
    end

    local params = {}
    if args then
        for k, v in args:gmatch("([^=]+)=([^&]+)") do
            params[k] = hs.urlevent.unquote(v)
        end
    end

    if cmd == "selectItem" and params.id then
        spoon:selectItem(params.id)
    elseif cmd == "toggleItem" and params.id then
        spoon:toggleItem(params.id)
    elseif cmd == "editItem" and params.id then
        spoon:editItem(params.id)
    elseif cmd == "deleteItem" and params.id then
        spoon:deleteItem(params.id)
    elseif cmd == "saveProperties" and params.id then
        spoon:saveProperties(params)
    elseif cmd == "cancelEdit" then
        M.clearProperties(spoon)
    elseif cmd == "addFolder" then
        spoon:addFolder()
    elseif cmd == "addAction" then
        spoon:addAction()
    elseif cmd == "addSequence" then
        spoon:addSequence()
    end
end

return M
