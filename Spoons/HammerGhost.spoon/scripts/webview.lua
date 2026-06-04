-- Spoons/HammerGhost.spoon/scripts/webview.lua

local tree_helpers = dofile(hs.spoons.resourcePath("tree_helpers.lua"))
local properties = dofile(hs.spoons.resourcePath("properties.lua"))
local eventBus = dofile(hs.spoons.resourcePath("event_bus.lua"))

local M = {}

-- Escape text destined for raw HTML insertion.
local function escapeHTML(s)
    return (tostring(s or "")
        :gsub("&", "&amp;")
        :gsub("<", "&lt;")
        :gsub(">", "&gt;"))
end

-- Escape for a double-quoted HTML attribute (adds " on top of escapeHTML), used
-- for the payload JSON stashed on data-payload.
local function escapeAttr(s)
    return (escapeHTML(s):gsub('"', "&quot;"))
end

-- Render the event bus's recent history as log rows (oldest first, matching the
-- live-append order). Shown when the window opens so the log isn't blank.
local function buildLogHTML()
    local recent = eventBus.recent()
    if #recent == 0 then
        return '<div class="log-empty">No events yet.</div>'
    end
    local rows = {}
    for _, ev in ipairs(recent) do
        local payloadJSON = hs.json.encode(ev.payload or {}) or "{}"
        rows[#rows + 1] = string.format(
            '<div class="log-entry" data-seq="%d" data-payload="%s"><span class="log-time">%s</span>' ..
            '<span class="log-name">%s</span><button class="log-toggle" title="Show payload tokens">{}</button></div>',
            ev.seq, escapeAttr(payloadJSON), os.date("%H:%M:%S", ev.time), escapeHTML(ev.name))
    end
    return table.concat(rows)
end

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

-- Total number of items in the tree (folders, sequences, actions; all depths).
local function countItems(items)
    local n = 0
    for _, item in ipairs(items or {}) do
        n = n + 1
        if item.children then
            n = n + countItems(item.children)
        end
    end
    return n
end

-- Human label for the header item count.
local function itemCountLabel(spoon)
    local n = countItems(spoon.macroTree)
    return n == 1 and "1 item" or (n .. " items")
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

    -- Pre-render the header item count.
    htmlContent = htmlContent:gsub('<!%-%- Item count injected here %-%->', function()
        return itemCountLabel(spoon)
    end)

    -- Pre-render recent events so the log shows history captured before open.
    htmlContent = htmlContent:gsub('<!%-%- Log entries injected here %-%->', function()
        return buildLogHTML()
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

    -- Re-render the tree and keep the header count in sync (single re-render path).
    local js = string.format(
        "document.getElementById('tree-container').innerHTML = `%s`;" ..
        "var __c = document.getElementById('item-count'); if (__c) __c.textContent = `%s`;",
        buildTreeHTML(spoon),
        itemCountLabel(spoon)
    )
    spoon.window:evaluateJavaScript(js)
end


return M
