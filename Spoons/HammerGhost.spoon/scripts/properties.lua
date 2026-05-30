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

    -- Type-specific properties can be appended here in the future.

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
