-- Spoons/HammerGhost.spoon/scripts/properties.lua

local M = {}

function M.show(spoon, item)
    if not spoon.window then
        return
    end

    local html = "<form onsubmit='return false;'>"
    html = html .. "<h3>Properties</h3>"
    html = html .. string.format("<label for='name'>Name:</label><input type='text' id='name' value='%s'><br>", item.name or "")
    html = html .. string.format("<label for='type'>Type:</label><input type='text' id='type' value='%s' readonly><br>", item.type or "")

    -- Add type-specific properties here
    if item.type == "action" then
        -- Action specific properties
    elseif item.type == "sequence" then
        -- Sequence specific properties
    end

    html = html .. string.format("<button onclick='saveProperties(\"%s\")'>Save</button>", item.id)
    html = html .. "<button onclick='cancelEdit()'>Cancel</button>"
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
    local js = "document.getElementById('properties-panel').innerHTML = '';"
    spoon.window:evaluateJavaScript(js)
end

return M
