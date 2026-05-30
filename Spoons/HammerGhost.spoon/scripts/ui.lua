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

    -- webview_manager.init pre-renders the macro tree into the HTML, so the
    -- window is fully populated on show without a timed JS injection.
    webview_manager.init(spoon)
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
        -- Exclude '&' from the key class so multi-param queries
        -- (source=a&target=b&position=c) split correctly.
        for k, v in args:gmatch("([^=&]+)=([^&]+)") do
            params[k] = urlDecode(v)
        end
    end

    if cmd == "selectItem" and params.id then
        spoon:selectItem(params.id)
    elseif cmd == "toggleItem" and params.id then
        spoon:toggleItem(params.id)
    elseif cmd == "toggleExpand" and params.id then
        spoon:toggleExpand(params.id)
    elseif cmd == "editItem" and params.id then
        spoon:editItem(params.id)
    elseif cmd == "deleteItem" and params.id then
        spoon:deleteItem(params.id)
    elseif cmd == "moveItem" and params.source and params.target then
        spoon:moveItem(params.source, params.target, params.position or "after")
    elseif cmd == "saveProperties" then
        -- app.js sends the payload as encodeURIComponent(JSON), not k=v pairs.
        local data = args and args ~= "" and hs.json.decode(urlDecode(args)) or nil
        if data and data.id then
            spoon:saveProperties(data)
        end
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
