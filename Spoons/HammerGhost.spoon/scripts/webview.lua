-- Spoons/HammerGhost.spoon/scripts/webview.lua

local tree_helpers = dofile(hs.spoons.resourcePath("tree_helpers.lua"))
local properties = dofile(hs.spoons.resourcePath("properties.lua"))

local M = {}

-- Read a file from the assets directory, returning its contents or "" on failure.
local function readAsset(name)
    local path = hs.spoons.resourcePath("../assets/" .. name)
    local file = io.open(path, "r")
    if not file then
        hs.logger.new("HammerGhost"):e("Could not read asset: " .. tostring(path))
        return ""
    end
    local contents = file:read("*a")
    file:close()
    return contents
end

-- Build the macro tree's HTML from the current model.
local function buildTreeHTML(spoon)
    local html = ""
    for _, item in ipairs(spoon.macroTree) do
        html = html .. tree_helpers.itemToHTML(item, 0, spoon.currentSelection)
    end
    return html
end

function M.init(spoon)
    -- WKWebView's html(content, baseURL) does not reliably load external
    -- subresources (cross-origin restrictions apply to file:// stylesheets and
    -- scripts), so inline styles.css and app.js directly into the document.
    local htmlContent = readAsset("index.html")
    if htmlContent == "" then
        htmlContent = "<html><body><h1>Error</h1><p>Could not read index.html</p></body></html>"
    end

    local css = readAsset("styles.css")
    local js = readAsset("app.js")

    -- Plain-text replacement via function callback so CSS/JS '%' and braces are
    -- not interpreted as gsub replacement escapes.
    htmlContent = htmlContent:gsub('<link rel="stylesheet" href="styles.css">', function()
        return "<style>\n" .. css .. "\n</style>"
    end)
    htmlContent = htmlContent:gsub('<script src="app.js"></script>', function()
        return "<script>\n" .. js .. "\n</script>"
    end)

    -- Pre-render the tree into #tree-container before the document loads. This
    -- avoids racing the DOM with a timed evaluateJavaScript injection (which left
    -- the tree blank on cold open until some action forced a refresh) - the window
    -- now appears fully populated. Function replacement keeps tree HTML literal.
    local treeHTML = buildTreeHTML(spoon)
    htmlContent = htmlContent:gsub('<!%-%- Tree content will be injected here %-%->', function()
        return treeHTML
    end)

    -- Pre-render the properties panel's empty state so a fresh window isn't blank.
    htmlContent = htmlContent:gsub('<!%-%- Properties content will be injected here %-%->', function()
        return properties.emptyStateHTML()
    end)

    -- Assets are inlined above, so baseURL is not needed for resource loading;
    -- it is still supplied to give the document a real origin (not about:blank)
    -- so that window.location.href navigations reach the navigationCallback.
    local baseURL = hs.spoons.resourcePath("../assets/")
    spoon.window:html(htmlContent, baseURL)
end

function M.refresh(spoon)
    if not spoon.window then
        return
    end

    -- Use JavaScript to update only the tree-container div
    local js = string.format(
        "document.getElementById('tree-container').innerHTML = `%s`;",
        buildTreeHTML(spoon)
    )
    spoon.window:evaluateJavaScript(js)
end


return M
