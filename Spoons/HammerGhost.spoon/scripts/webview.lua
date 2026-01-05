-- Spoons/HammerGhost.spoon/scripts/webview.lua

local tree_helpers = dofile(hs.spoons.resourcePath("tree_helpers.lua"))

local M = {}

function M.init(spoon)
    -- Load the main HTML file
    local htmlPath = hs.spoons.resourcePath("assets/index.html")
    local htmlContent = ""
    local file = io.open(htmlPath, "r")
    if file then
        htmlContent = file:read("*a")
        io.close(file)
    else
        hs.logger.new("HammerGhost"):e("Could not read index.html")
    end

    spoon.window:html(htmlContent)
end

function M.refresh(spoon)
    if not spoon.window then
        return
    end

    -- Generate HTML for the macro tree
    local html = ""
    for _, item in ipairs(spoon.macroTree) do
        html = html .. tree_helpers.itemToHTML(item, 0, spoon.currentSelection)
    end

    -- Use JavaScript to update only the tree-container div
    local js = string.format(
        "document.getElementById('tree-container').innerHTML = `%s`;",
        html
    )
    spoon.window:evaluateJavaScript(js)
end


return M
