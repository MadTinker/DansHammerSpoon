-- Spoons/HammerGhost.spoon/scripts/keymap_server.lua
--
-- Serves the keymap editor to a browser tab over loopback HTTP -- the third
-- surface, and the one closest to how Logitech Options actually feels: a real
-- page, in a real browser, driving the live keyboard.
--
-- It reuses assets/keymap.js and the shared assets/keymap_page.html shell; only
-- the transport differs (assets/keymap_transport_http.js). Nothing about the
-- editor is duplicated here -- this file is a server, not a second editor.
--
-- SECURITY. This opens a port that mutates the user's keyboard, so:
--   * bound to localhost only, and Bonjour advertising is off -- a keyboard
--     config server has no business announcing itself on the LAN.
--   * every /api/ call must carry a per-start random token in the
--     X-Keymap-Token header. The token lives in the page the server itself
--     serves, never in the URL, so it stays out of history and Referer.
--   * no CORS headers are ever sent. A page on another origin can reach the
--     port, but a request with a custom header needs a preflight this server
--     does not answer, and it could not read the response anyway. That is
--     what stops a random site the user is visiting from rebinding their keys.
-- Loopback alone would not be enough: anything running as the user can reach
-- 127.0.0.1, and browsers happily send cross-origin requests to it.

local M = {}

M.server = nil
M.port = 27123          -- arbitrary, unprivileged, unlikely to collide
M.token = nil
M.spoon = nil

local function log()
    return _G.AppLogger or hs.logger.new("HammerGhost")
end

-- hs.json.encode REQUIRES a table and throws on a bare string ("incorrect type
-- 'string' for argument 1"). Wrapping in an array and stripping the brackets
-- borrows Hammerspoon's own escaping instead of hand-rolling one.
local function jsonString(s)
    return (hs.json.encode({ tostring(s or "") }):sub(2, -2))
end

-- Resolve the assets directory ONCE, at module load, and keep it.
-- hs.spoons.resourcePath resolves relative to whatever source file is calling
-- it, and inside an hs.httpserver callback that is no longer this spoon: the
-- path came back rooted at the caller's directory and every asset read failed,
-- which the server could only report as a 503. At load time the caller IS this
-- file, so it resolves correctly; the configdir fallback covers a load context
-- where even that is not true.
local ASSET_DIR = (function()
    local viaSpoon = hs.spoons.resourcePath("../assets/")
    if viaSpoon and hs.fs.attributes(viaSpoon .. "keymap.js") then return viaSpoon end
    return hs.configdir .. "/Spoons/HammerGhost.spoon/assets/"
end)()

local function assetPath(name)
    return ASSET_DIR .. name
end

local function readAsset(name)
    local file = io.open(assetPath(name), "r")
    if not file then
        log():e("Keymap server: could not read asset " .. tostring(name))
        return nil
    end
    local contents = file:read("*a")
    file:close()
    return contents
end

local function binder()
    local ok, B = pcall(require, 'HotkeyBinder')
    if not ok then return nil end
    return B
end

-- Same payload every surface renders. Kept here rather than imported from
-- keymap_window.lua so the server does not depend on a window existing.
function M.buildPayload()
    local B = binder()
    if not B then return { bindings = {}, modifierSets = {}, actionTypes = {}, problems = {} } end

    local problems = {}
    for _, err in ipairs(B.errors or {}) do
        local id, msg = err:match("^([^:]+):%s*(.+)$")
        if id then problems[id] = msg end
    end
    for _, bad in ipairs(B.verify()) do problems[bad.id] = bad.error end

    local actionTypes = {}
    local asys = rawget(_G, "_HammerGhostActionSystem")
    if asys and asys.getActionTypesForUI then actionTypes = asys.getActionTypesForUI() end

    return {
        bindings = (B.config or {}).bindings or {},
        modifierSets = (B.config or {}).modifierSets or {},
        actionTypes = actionTypes,
        problems = problems,
    }
end

-- hs.json.encode turns an empty table into "[]", but the page does
-- data.problems[id] and Object.keys(actionTypes). Force object syntax for the
-- two maps that can legitimately be empty.
local function encodePayload(payload)
    local encoded = hs.json.encode(payload)
    if not encoded then return nil end
    encoded = encoded:gsub('"problems":%[%]', '"problems":{}')
    encoded = encoded:gsub('"actionTypes":%[%]', '"actionTypes":{}')
    return encoded
end

-- Build the page: shared shell + this surface's notice, transport and the one
-- renderer. Mirrors build_keymap_artifact.py and editor_window.lua -- three
-- hosts, one editor.
local function buildPage()
    local shell = readAsset("keymap_page.html")
    local transport = readAsset("keymap_transport_http.js")
    local renderer = readAsset("keymap.js")
    if not (shell and transport and renderer) then return nil end

    local notice = [[<p>
                    <strong>Connected to Hammerspoon.</strong> Changes apply to the live
                    keyboard the moment you save them &mdash; no reload, no export. This page is
                    served from your own Mac on localhost and is not reachable from anywhere else.
                </p>]]

    -- Function replacements so a '%' or brace in an asset body is not read as a
    -- gsub escape.
    shell = shell:gsub("__NOTICE__", function() return notice end)
    shell = shell:gsub("__TRANSPORT__", function()
        return "window.KEYMAP_TOKEN = " .. jsonString(M.token) .. ";\n" .. transport
    end)
    shell = shell:gsub("__RENDERER__", function() return renderer end)
    return shell
end

local JSON_HEADERS = { ["Content-Type"] = "application/json" }
local HTML_HEADERS = { ["Content-Type"] = "text/html; charset=utf-8" }

local function jsonResponse(tbl, code)
    return hs.json.encode(tbl) or "{}", code or 200, JSON_HEADERS
end

local function tableResponse(message)
    local encoded = encodePayload(M.buildPayload())
    if not encoded then return jsonResponse({ error = "could not encode table" }, 500) end
    -- Splice the pre-encoded table in rather than re-encoding it, so the
    -- object-vs-array fixups above survive.
    local body = '{"message":' .. jsonString(message) .. ',"table":' .. encoded .. '}'
    return body, 200, JSON_HEADERS
end

function M.handler(method, path, headers, body)
    -- Strip any query string; the page is served from "/" and the API paths
    -- carry no parameters.
    local route = path:match("^([^?]*)") or path

    if route == "/" or route == "/index.html" then
        local page = buildPage()
        if not page then return "Could not build the keymap page", 500, {} end
        return page, 200, HTML_HEADERS
    end

    if not route:match("^/api/") then
        return "Not found", 404, {}
    end

    -- Header names arrive with varying case depending on the client.
    local token
    for k, v in pairs(headers or {}) do
        if k:lower() == "x-keymap-token" then token = v end
    end
    if not M.token or token ~= M.token then
        return "Forbidden", 403, {}
    end

    local B = binder()
    if not B then return jsonResponse({ error = "HotkeyBinder unavailable" }, 500) end

    if method == "GET" and route == "/api/bindings" then
        local encoded = encodePayload(M.buildPayload())
        if not encoded then return jsonResponse({ error = "could not encode table" }, 500) end
        return encoded, 200, JSON_HEADERS
    end

    if method ~= "POST" then return "Not found", 404, {} end

    local ok, payload = pcall(hs.json.decode, body or "")
    if route ~= "/api/reload" and (not ok or type(payload) ~= "table") then
        return jsonResponse({ error = "body must be a JSON object" }, 400)
    end

    if route == "/api/binding" then
        if not payload.id then return jsonResponse({ error = "binding needs an id" }, 400) end
        local bound, err = B.setBinding(payload)
        local message = bound and ("Saved and applied " .. payload.id .. ".")
            or ("Saved, but not bound: " .. tostring(err or (B.errors[#B.errors] or "see the console")))
        return tableResponse(message)
    end

    if route == "/api/binding/delete" then
        if not payload.id then return jsonResponse({ error = "need an id" }, 400) end
        local removed = B.deleteBinding(payload.id)
        return tableResponse(removed and ("Deleted " .. payload.id .. ".") or "Nothing to delete.")
    end

    if route == "/api/reload" then
        B.load()
        local n = B.applyAll()
        return tableResponse("Reloaded from disk: " .. n .. " bound.")
    end

    return "Not found", 404, {}
end

function M.url()
    return "http://localhost:" .. M.port .. "/"
end

function M.isRunning()
    return M.server ~= nil
end

function M.start(spoon)
    if M.server then return M.url() end
    M.spoon = spoon

    -- 32 hex chars from the system RNG. math.random is seeded predictably
    -- enough at startup that it has no business guarding a write API.
    local handle = io.open("/dev/urandom", "rb")
    if handle then
        local bytes = handle:read(16)
        handle:close()
        M.token = (bytes:gsub(".", function(c) return string.format("%02x", c:byte()) end))
    else
        M.token = tostring(hs.host.uuid()):gsub("-", "")
    end

    -- new(ssl, bonjour): both explicit. Bonjour must be off -- see the header.
    local server = hs.httpserver.new(false, false)
    if not server then
        log():e("Keymap server: could not create hs.httpserver")
        return nil
    end

    server:setPort(M.port)
    server:setInterface("localhost")
    server:setCallback(M.handler)

    local started, err = pcall(function() return server:start() end)
    if not started then
        log():e("Keymap server: start failed: " .. tostring(err))
        return nil
    end

    M.server = server
    M.installShutdownHook()
    log():i("Keymap server listening on " .. M.url())
    return M.url()
end

-- hs.reload() builds a fresh Lua state but does NOT run M.stop(), and the old
-- listening socket can outlive the state that owned it. The next start then
-- fails to bind while the PREVIOUS callback keeps answering on the port -- which
-- looks exactly like new code that will not take effect (it served stale 503s
-- through several reloads before this hook existed). Releasing the socket on
-- shutdown is the fix. Chain rather than replace: hs.shutdownCallback is a
-- single global slot and other code may already own it.
function M.installShutdownHook()
    if M.shutdownHooked then return end
    M.shutdownHooked = true
    local previous = hs.shutdownCallback
    hs.shutdownCallback = function()
        pcall(M.stop)
        if type(previous) == "function" then pcall(previous) end
    end
end

function M.stop()
    if not M.server then return false end
    pcall(function() M.server:stop() end)
    M.server = nil
    M.token = nil
    log():i("Keymap server stopped")
    return true
end

function M.toggle(spoon)
    if M.server then
        M.stop()
        hs.alert.show("Keymap server stopped")
        return nil
    end
    local url = M.start(spoon)
    if url then
        hs.alert.show("Keymap server: " .. url)
        -- The token only reaches the browser through the page this server
        -- serves, so opening it here is also how the session is authorised.
        hs.urlevent.openURL(url)
    else
        hs.alert.show("Keymap server failed to start (see console)")
    end
    return url
end

return M
