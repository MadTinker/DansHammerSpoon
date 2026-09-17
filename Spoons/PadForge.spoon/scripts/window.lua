-- PadForge/scripts/window.lua
--
-- The pad editor in a native Hammerspoon window. Same bridge pattern as
-- BindForge's editor_window.lua: the page talks to Lua by navigating to
-- hammerspoon://cmd?json, intercepted by policyCallback.

local Window = {}

Window.assetDir = (function()
    local viaSpoon = hs.spoons.resourcePath("../assets/")
    if viaSpoon and hs.fs.attributes(viaSpoon .. "padforge.js") then return viaSpoon end
    return hs.configdir .. "/Spoons/PadForge.spoon/assets/"
end)()

local Codec = dofile(hs.spoons.resourcePath("../PcfgCodec.lua"))

local function log()
    return _G.AppLogger or hs.logger.new("PadForge")
end

local function readAsset(name)
    local file = io.open(Window.assetDir .. name, "r")
    if not file then
        log():e("PadForge: could not read asset " .. tostring(name))
        return ""
    end
    local contents = file:read("*a")
    file:close()
    return contents
end

-- ─────────────────────────────────────────────────────────────────────────────
-- State: at most one loaded file at a time.
-- ─────────────────────────────────────────────────────────────────────────────

Window.model = nil   -- Codec.load() result, or nil if nothing loaded
Window.loadError = nil

function Window.loadPath(path)
    local model, err = Codec.load(path)
    if not model then
        Window.model, Window.loadError = nil, err
        return false, err
    end
    Window.model, Window.loadError = model, nil
    return true
end

--- Bindings already in hotkeys.json, as {label, mods=[...], key} -- the
--- "reuse an existing Hammerspoon shortcut" picker's source list. Read
--- directly rather than through BindForge/HotkeyBinder: PadForge edits a
--- different file format and has no runtime dependency on that spoon.
function Window.hotkeyChoices()
    local path = hs.configdir .. "/hotkeys.json"
    local file = io.open(path, "r")
    if not file then return {} end
    local raw = file:read("*a")
    file:close()
    local ok, data = pcall(hs.json.decode, raw)
    if not ok or type(data) ~= "table" then return {} end

    local sets = data.modifierSets or {}
    local out = {}
    for _, b in ipairs(data.bindings or {}) do
        local mods = b.mods
        if type(mods) == "string" then mods = sets[mods] or { mods } end
        if type(mods) == "table" and b.key then
            table.insert(out, {
                label = (b.description or b.id or "") .. "  (" .. table.concat(mods, "+") .. "+" .. b.key .. ")",
                mods = mods,
                key = b.key,
            })
        end
    end
    return out
end

function Window.buildPayload()
    if not Window.model then
        return {
            loaded = false,
            error = Window.loadError,
            modes = Codec.MODES, modeLabels = Codec.MODE_LABELS,
        }
    end
    return {
        loaded = true,
        path = Window.model.path,
        modes = Codec.MODES,
        modeLabels = Codec.MODE_LABELS,
        editableKeys = Codec.EDITABLE_KEYS,
        fixedKeys = Codec.FIXED_KEYS,
        data = Window.model.modes,
        hotkeyChoices = Window.hotkeyChoices(),
    }
end

function Window.refresh()
    local win = Window.win
    if not win then return end
    local payload = hs.json.encode(Window.buildPayload())
    if not payload then
        log():e("PadForge window: could not encode payload")
        return
    end
    win:evaluateJavaScript(string.format("window.PadForge.render(%s)", payload))
end

local function jsonString(s)
    return (hs.json.encode({ tostring(s or "") }):sub(2, -2))
end

local function say(text)
    local win = Window.win
    if not win then return end
    win:evaluateJavaScript(string.format("window.PadForge.setStatus(%s)", jsonString(text)))
end

function Window.decode(args)
    if not args or args == "" then return nil end
    local decoded = args:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
    local ok, value = pcall(hs.json.decode, decoded)
    if not ok or type(value) ~= "table" then
        log():e("PadForge window: bad bridge payload: " .. tostring(decoded))
        return nil
    end
    return value
end

function Window.handleURL(url)
    local cmd, args = url:match("hammerspoon://([^?]+)%??(.*)")
    if not cmd then return end

    if cmd == "padData" then
        Window.refresh()

    elseif cmd == "pickFile" then
        local chosen = hs.dialog.chooseFileOrFolder(
            "Choose an exported .pcfg", os.getenv("HOME") .. "/Desktop", true, false, false, { "pcfg" })
        local path = chosen and chosen[1]
        if not path then return end -- user cancelled
        local ok, err = Window.loadPath(path)
        say(ok and ("Loaded " .. path) or ("Could not load: " .. tostring(err)))
        Window.refresh()

    elseif cmd == "reload" then
        if Window.model then
            local ok, err = Window.loadPath(Window.model.path)
            say(ok and "Reloaded from disk." or ("Reload failed: " .. tostring(err)))
        end
        Window.refresh()

    elseif cmd == "saveKey" then
        local payload = Window.decode(args)
        if not payload or not Window.model then return say("Nothing to save.") end
        local ok, err = Codec.save(Window.model, payload.mode, payload.key, payload.mods, payload.baseKey, payload.label)
        if ok then
            say(("Saved %s / %s. Re-import this file in the XPPen app to push it to the pad."):format(
                Codec.MODE_LABELS[payload.mode] or payload.mode, payload.key))
        else
            say("Not saved: " .. tostring(err))
        end
        Window.refresh()

    elseif cmd == "revealFinder" then
        if Window.model then
            hs.execute(string.format("open -R %q", Window.model.path))
        end
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Window
-- ─────────────────────────────────────────────────────────────────────────────

local function escapePattern(s)
    return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%1"))
end

function Window.renderPage()
    local html = readAsset("padforge.html")
    if html == "" then
        return "<html><body><h1>Error</h1><p>Could not read assets/padforge.html</p></body></html>"
    end

    html = html:gsub('<link rel="stylesheet" href="styles.css">', function()
        return "<style>\n" .. readAsset("styles.css") .. "\n</style>"
    end)

    for _, name in ipairs({ "padforge.js" }) do
        local body = readAsset(name)
        html = html:gsub('<script src="' .. escapePattern(name) .. '"></script>', function()
            return "<script>\n" .. body .. "\n</script>"
        end)
    end

    return html
end

function Window.navigationURL(details)
    local request = details and details.request
    local url = request and request.URL
    if type(url) == "table" then
        url = url.url or url.absoluteString
    end
    return type(url) == "string" and url or ""
end

function Window.create()
    local mainScreen = hs.screen.mainScreen()
    if not mainScreen then
        log():e("PadForge window: no main screen to open on")
        return nil
    end
    local screen = mainScreen:frame()
    local w = math.min(1100, screen.w - 80)
    local h = math.min(760, screen.h - 80)

    local win = hs.webview.new({
        x = screen.x + math.floor((screen.w - w) / 2),
        y = screen.y + math.floor((screen.h - h) / 2),
        w = w,
        h = h,
        show = false,
    })
    if not win then
        log():e("PadForge window: failed to create the webview")
        return nil
    end

    win:allowTextEntry(true)
    win:darkMode(true)
    win:windowStyle({ "titled", "closable", "resizable" })
    win:windowTitle("⌘ PadForge")
    win:allowNewWindows(false)

    win:policyCallback(function(action, _, details)
        if action == "navigationAction" then
            if Window.navigationURL(details):match("^hammerspoon://") then
                Window.handleURL(Window.navigationURL(details))
                return false
            end
        end
        return true
    end)

    win:html(Window.renderPage(), Window.assetDir)
    return win
end

function Window.toggle()
    local win = Window.win

    if win and win:isVisible() then
        win:hide()
        return false
    end

    if not win then
        win = Window.create()
        if not win then
            hs.alert.show("PadForge failed to open (see the console)")
            return false
        end
        Window.win = win
        win:show():bringToFront(true)
        return true
    end

    win:show():bringToFront(true)
    Window.refresh()
    return true
end

return Window
