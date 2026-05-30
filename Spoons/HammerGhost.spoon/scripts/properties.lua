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

    local html = [[<form class="properties-form" onsubmit="return false;">]]
    html = html .. "<h3>Properties</h3>"
    html = html .. string.format(
        [[<div class="field"><label for="name">Name</label><input type="text" id="name" value="%s"></div>]],
        esc(item.name))
    html = html .. string.format(
        [[<div class="field"><label for="type">Type</label><input type="text" id="type" value="%s" readonly></div>]],
        esc(item.type))

    -- Triggers expose the event they fire on. Edit directly, or select the
    -- trigger and click an event in the log to bind it.
    if item.type == "trigger" then
        html = html .. string.format(
            [[<div class="field"><label for="eventName">Event Name</label>]] ..
            [[<input type="text" id="eventName" value="%s" placeholder="e.g. App.Activated.Safari"></div>]],
            esc(item.eventName))
        html = html .. [[<div class="field-hint">Tip: click an event in the log below to bind it.</div>]]
    end

    html = html .. string.format(
        [[<div class="buttons"><button id="save-button" class="primary" data-id="%s">Save</button>]] ..
        [[<button id="cancel-button">Cancel</button></div>]],
        esc(item.id))
    html = html .. "</form>"

    local js = string.format(
        "document.getElementById('properties-panel').innerHTML = `%s`;",
        html
    )
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
