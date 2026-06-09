-- Spoons/HammerGhost.spoon/scripts/properties.lua

local M = {}

-- Escape a value for safe insertion into HTML that is itself injected via a JS
-- template literal: HTML-encode &<>" and neutralize backtick / ${ so the template
-- literal can't be broken out of.
local function esc(s)
    s = tostring(s or "")
    s = s:gsub("&", "&amp;"):gsub('"', "&quot;"):gsub("<", "&lt;"):gsub(">", "&gt;")
    s = s:gsub("`", "\\`"):gsub("%$", "\\$")
    return s
end

-- HTML shown in the properties panel when nothing is selected.
function M.emptyStateHTML()
    return [[<div class="empty-state">Select an item to edit its properties</div>]]
end

function M.show(spoon, item)
    if not spoon.window then
        return
    end
    -- Item id can resolve to nil (stale selection, deleted node). Fall back to
    -- the empty state instead of indexing a nil and crashing the URL callback.
    if not item then
        M.clear(spoon)
        return
    end

    local html = [[<form class="properties-form" onsubmit="return false;">]]
    html = html .. "<h3>Properties</h3>"
    html = html .. string.format(
        [[<div class="field"><label for="name">Name</label><input type="text" id="name" value="%s"></div>]],
        esc(item.name))
    -- Action/condition types are editable inline: a dropdown (app.js fills it from
    -- the registered defs) + a params container the shared HG renderer populates.
    -- Other node types just show their type read-only.
    local editable = (item.type == "action" or item.type == "condition")
    if editable then
        html = html .. [[<div class="field"><label for="prop-type">Type</label><select id="prop-type"></select></div>]]
        html = html .. [[<div id="properties-params"></div>]]
    else
        html = html .. string.format(
            [[<div class="field"><label for="type">Type</label><input type="text" id="type" value="%s" readonly></div>]],
            esc(item.type))
    end

    -- Triggers expose the event they fire on. Edit directly, or select the
    -- trigger and click an event in the log to bind it.
    if item.type == "trigger" then
        html = html .. string.format(
            [[<div class="field"><label for="eventName">Event Name(s)</label>]] ..
            [[<textarea id="eventName" rows="3" placeholder="e.g. App.Activated.Safari">%s</textarea></div>]],
            esc(item.eventName))
        html = html .. [[<div class="field-hint">One event per line &mdash; fires if ANY matches. ]] ..
            [['*'/'?' wildcards allowed. Click an event in the log below to add it.</div>]]
    end

    -- Autostart: run this item once when HammerGhost loads (EventGhost's
    -- Autostart). Useful on triggers/folders/actions you want armed at launch.
    html = html .. string.format(
        [[<div class="field field-check"><label><input type="checkbox" id="autostart" %s> ]] ..
        [[Run at startup (autostart)</label></div>]],
        item.autostart and "checked" or "")

    html = html .. string.format(
        [[<div class="buttons"><button id="save-button" class="primary" data-id="%s">Save</button>]] ..
        [[<button id="cancel-button">Cancel</button></div>]],
        esc(item.id))
    html = html .. "</form>"

    local js = string.format(
        "document.getElementById('properties-panel').innerHTML = `%s`;",
        html
    )
    -- Hand the inline editor the item's current type + params so it can fill the
    -- dropdown and render widgets. JSON (a table), never a bare string, so a
    -- backtick/${} in a value can't break out (see the refresh-crash fix).
    if editable then
        local initData = hs.json.encode({
            kind = item.type,
            currentType = item.actionType or item.conditionType,
            params = item.params or {},
        })
        js = js .. string.format(
            "if(window.HG&&HG.initPropertiesEditor){HG.initPropertiesEditor(%s);}", initData)
    end
    spoon.window:evaluateJavaScript(js)
end

function M.clear(spoon)
    if not spoon.window then
        return
    end
    local js = string.format(
        "document.getElementById('properties-panel').innerHTML = `%s`;",
        M.emptyStateHTML()
    )
    spoon.window:evaluateJavaScript(js)
end

return M
