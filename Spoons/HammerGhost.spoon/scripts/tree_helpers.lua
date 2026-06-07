--- Tree-related helper functions for HammerGhost

local M = {}

-- Escape text destined for raw HTML insertion. Node names are user-entered (the
-- properties panel lets you rename to anything), so a name with & < > -- e.g.
-- "Build & Deploy" -- would otherwise corrupt the tree markup. Mirrors the
-- escapeHTML in webview.lua / properties.lua.
local function escapeHTML(s)
    return (tostring(s or "")
        :gsub("&", "&amp;")
        :gsub("<", "&lt;")
        :gsub(">", "&gt;"))
end

--- Generate HTML representation of a tree item
--- @param item table The item to convert to HTML
--- @param level number The indentation level
--- @param currentSelection table The currently selected item
--- @return string HTML representation of the item
function M.itemToHTML(item, level, currentSelection)
    if not item.name then
        hs.logger.new("HammerGhost"):e("Skipping item with missing 'name': " .. hs.inspect(item))
        return ""
    end

    local indentStyle = string.format("padding-left: %dpx;", level * 20)
    local selectedClass = (currentSelection and item.id == currentSelection.id) and "selected" or ""
    -- item.enabled == false marks a disabled item; nil/true are treated as enabled
    local disabledClass = (item.enabled == false) and "disabled" or ""
    local stateClass = (selectedClass .. " " .. disabledClass):gsub("^%s+", ""):gsub("%s+$", "")
    -- Per-type glyphs: trigger ⚡ fires on an event, action ⚙️ does work,
    -- sequence 📋 runs gated steps, condition ❓ gates, folder 📁 groups.
    local icons = {
        folder = "📁", sequence = "📋", trigger = "⚡",
        action = "⚙️", condition = "❓",
    }
    local icon = icons[item.type] or "⚙️"

    -- Containers with children get a disclosure triangle; expanded unless the
    -- model explicitly stores expanded == false (nil/true render expanded). Items
    -- without children get a spacer so names stay vertically aligned.
    local hasChildren = item.children and #item.children > 0
    local isExpanded = item.expanded ~= false
    local disclosure
    if hasChildren then
        disclosure = string.format('<span class="disclosure">%s</span>', isExpanded and "▾" or "▸")
    else
        disclosure = '<span class="disclosure-spacer"></span>'
    end

    -- Class names below match app.js event delegation (.tree-item / .disclosure /
    -- .toggle-button / .edit-button / .delete-button) and styles.css. Click and drag
    -- wiring is handled by delegated listeners in app.js via
    -- closest('.tree-item').dataset.id, so no inline onclick/ondrag handlers are
    -- needed. draggable + data-type drive the drag-to-reorder behavior.
    local html = string.format([[
        <div class="tree-item %s" data-id="%s" data-type="%s" style="%s" draggable="true">
            %s
            <span class="icon toggle-button">%s</span>
            <span class="name">%s</span>
            <div class="actions">
                <button class="run-button" title="Run">▶️</button>
                <button class="edit-button" title="Edit">✏️</button>
                <button class="delete-button" title="Delete">🗑️</button>
            </div>
        </div>
    ]], stateClass, item.id, item.type, indentStyle, disclosure, icon, escapeHTML(item.name))

    if hasChildren and isExpanded then
        html = html .. "<div class='children'>"
        for _, child in ipairs(item.children) do
            html = html .. M.itemToHTML(child, level + 1, currentSelection)
        end
        html = html .. "</div>"
    end

    return html
end

--- Find an item in a tree by its ID
--- @param items table The tree to search
--- @param id string The ID of the item to find
--- @return table|nil The found item or nil
function M.findItem(items, id)
    for _, item in ipairs(items) do
        if item.id == id then
            return item
        end
        if item.children then
            local found = M.findItem(item.children, id)
            if found then
                return found
            end
        end
    end
    return nil
end

return M 
