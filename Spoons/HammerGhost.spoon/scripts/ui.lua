-- Spoons/HammerGhost.spoon/scripts/ui.lua

local window_manager = dofile(hs.spoons.resourcePath("window.lua"))
local toolbar_manager = dofile(hs.spoons.resourcePath("toolbar.lua"))
local webview_manager = dofile(hs.spoons.resourcePath("webview.lua"))
local properties_manager = dofile(hs.spoons.resourcePath("properties.lua"))

local M = {}

-- Percent-decode a URL component. hs.urlevent has no unquote(); the JS side uses
-- encodeURIComponent (no form-style '+' for spaces), so we only decode %xx bytes.
local function urlDecode(s)
    if not s then return s end
    return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

function M.createMainWindow(spoon)
    spoon.window = window_manager.create(spoon)
    if not spoon.window then
        return
    end

    spoon.toolbar = toolbar_manager.create(spoon)
    spoon.window:attachedToolbar(spoon.toolbar)

    webview_manager.init(spoon)
    spoon.window:show()

    -- Delay refresh so page has time to load before JS injection
    hs.timer.doAfter(0.3, function()
        if spoon.window then webview_manager.refresh(spoon) end
    end)
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
            params[k] = urlDecode(v)
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
