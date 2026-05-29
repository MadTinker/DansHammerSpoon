--- Tree-related helper functions for HammerGhost

local M = {}

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
    local icon = item.type == "folder" and "📁" or (item.type == "sequence" and "📋" or "⚡")

    local html = string.format([[
        <div class="item %s" data-id="%s" data-type="%s" style="%s" draggable="true" ondragstart="handleDragStart(event)" ondragover="handleDragOver(event)" ondrop="handleDrop(event)">
            <span class="icon" onclick="toggleItem('%s', event)">%s</span>
            <span class="name">%s</span>
            <div class="actions">
                <button class="edit" onclick="editItem('%s', '%s', event)" title="Edit">✏️</button>
                <button class="delete" onclick="deleteItem('%s', '%s', event)" title="Delete">🗑️</button>
            </div>
            <div class="drop-indicator"></div>
        </div>
    ]], stateClass, item.id, item.type, indentStyle, item.id, icon, item.name,
        item.id, item.name:gsub("'", "\\'"), item.id, item.name:gsub("'", "\\'"))

    if item.children and #item.children > 0 then
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
