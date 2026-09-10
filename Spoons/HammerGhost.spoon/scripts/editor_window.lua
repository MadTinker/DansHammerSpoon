-- Spoons/HammerGhost.spoon/scripts/editor_window.lua
--
-- Shared builder for the modal editor webviews (action / sequence / condition /
-- chooser). These all need the same three things the main window already does in
-- webview.lua; before this helper they each hand-rolled it and got all three
-- wrong, so the windows opened blank:
--
--   1. Asset path. resourcePath resolves relative to THIS file's dir (scripts/),
--      so the page lives at "../assets/<name>", not "assets/<name>". The old
--      "assets/..." path read nothing -> html("") -> blank vibrancy rectangle.
--   2. Subresources. WKWebView's html(content, baseURL) does not reliably load
--      file:// <link>/<script> subresources, so styles.css and the page's own
--      script are inlined into the document (mirrors webview.lua).
--   3. URL bridge. A hammerspoon:// link must be intercepted with a policyCallback
--      returning false (deny navigation, stay on the page). navigationCallback
--      only observes lifecycle events and never denies, so the page navigated to
--      hammerspoon://... and blanked. A real baseURL is still supplied so the
--      document has an origin and window.location.href reaches the callback.

local M = {}

-- Escape Lua pattern magic so a filename is matched literally. Filenames carry
-- a '.', which as a pattern means "any character" -- harmless for the names in
-- use, but the <script src> substitutions below should match what they say.
local function escapePattern(s)
    return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%1"))
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

-- Build an editor webview.
--   opts.x/y/w/h  window frame
--   opts.title    window title
--   opts.html     page filename in assets/ (e.g. "action_editor.html")
--   opts.js       script filename in assets/ that the page <script src=>'s
--   opts.handler  function(url) called for each hammerspoon:// navigation
function M.create(opts)
    local win = hs.webview.new({
        x = opts.x,
        y = opts.y,
        w = opts.w,
        h = opts.h,
        show = false,
    })

    if not win then
        hs.logger.new("HammerGhost"):e("Failed to create " .. tostring(opts.title) .. " window")
        return nil
    end

    win:allowTextEntry(true)
    win:darkMode(true)
    win:windowStyle({ "titled", "closable", "resizable" })
    win:windowTitle(opts.title)
    win:allowNewWindows(false)

    -- See note (3) above: deny hammerspoon:// navigations and route them to the
    -- handler instead of letting the webview blank itself out.
    win:policyCallback(function(action, webView, details)
        if action == "navigationAction" then
            local request = details and details.request
            -- Hammerspoon changed this shape between builds: 6933 gives a
            -- table with .url, 6936 gives a plain string. Reading only the
            -- table form left every editor window empty on the newer build,
            -- because the hammerspoon:// match never fired and the page's
            -- request for its data was never seen.
            local urlObj = request and request.URL
            local url = urlObj
            if type(url) == "table" then url = url.url or url.absoluteString end
            if type(url) ~= "string" then url = "" end
            if url:match("^hammerspoon://") then
                opts.handler(url)
                return false
            end
        end
        return true
    end)

    local html = readAsset(opts.html)
    if html == "" then
        html = "<html><body><h1>Error</h1><p>Could not read " ..
            tostring(opts.html) .. "</p></body></html>"
    end

    -- Inline CSS/JS (see note (2)). Function replacement keeps the asset bodies
    -- literal so their '%' and braces aren't read as gsub escapes.
    local css = readAsset("styles.css")
    local js = readAsset(opts.js)
    html = html:gsub('<link rel="stylesheet" href="styles.css">', function()
        return "<style>\n" .. css .. "\n</style>"
    end)
    -- Inline the shared param-widgets renderer ahead of the page script. No-op on
    -- pages that don't include the tag (e.g. the action chooser).
    local widgets = readAsset("param_widgets.js")
    html = html:gsub('<script src="param_widgets.js"></script>', function()
        return "<script>\n" .. widgets .. "\n</script>"
    end)

    -- opts.extraJs: further scripts the page <script src=>'s, inlined in the
    -- order given and BEFORE opts.js. The keymap editor uses this for its
    -- transport adapter, which must define window.KeymapTransport before the
    -- renderer runs.
    for _, name in ipairs(opts.extraJs or {}) do
        local body = readAsset(name)
        html = html:gsub('<script src="' .. escapePattern(name) .. '"></script>', function()
            return "<script>\n" .. body .. "\n</script>"
        end)
    end

    html = html:gsub('<script src="' .. escapePattern(opts.js) .. '"></script>', function()
        return "<script>\n" .. js .. "\n</script>"
    end)

    local baseURL = hs.spoons.resourcePath("../assets/")
    win:html(html, baseURL)

    return win
end

return M
