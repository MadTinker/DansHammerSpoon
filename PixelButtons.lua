-- PixelButtons.lua - menubar buttons that fire Tasker tasks on the Pixel
--
-- Each button runs `dgm do TASK --force -w WAIT` (Digitomancy) against the
-- phone: USB when plugged in, otherwise the eaws tunnel (pixel9-ts, needs
-- `tunnelup`). The list lives in Digitomancy/buttons.json, so a new macro and
-- its button land in the same commit; the menu re-reads it every time it opens.
-- One task at a time: the phone can't run two macros at once.

local HyperLogger = require('HyperLogger')
local log = HyperLogger.new()

if _G.PixelButtons then
    return _G.PixelButtons
end

local M = {}

local HOME = os.getenv("HOME")
local DGM_PROJECT = HOME .. "/lab/madness_interactive/projects/mobile/Digitomancy"
local BUTTONS_FILE = DGM_PROJECT .. "/buttons.json"
local UV = HOME .. "/.local/bin/uv"
local ADB = "/opt/homebrew/bin/adb"
local ENV = { PATH = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" .. HOME .. "/.local/bin", HOME = HOME }

local menu = nil
local running = nil -- { task = name, started = seconds, proc = hs.task }

local function loadButtons()
    local data = hs.json.read(BUTTONS_FILE)
    if not data or type(data.buttons) ~= "table" then
        log:e('PixelButtons: cannot read ' .. BUTTONS_FILE)
        return nil
    end
    return data.buttons
end

-- USB beats the tunnel: faster, and it doesn't depend on Tailscale.
local function pickDevice()
    local out = hs.execute(ADB .. " devices 2>/dev/null")
    if out:match("48140DLAQ001S7%s+device") then return "pixel9", "USB" end
    if out:match("127%.0%.0%.1:15555%s+device") then return "pixel9-ts", "tunnel" end
    return nil, "offline"
end

local function setTitle()
    if not menu then return end
    menu:setTitle(running and ("📱 " .. running.task:sub(1, 18) .. "…") or "📱")
end

local function finish(btn, code, stdout, stderr)
    local secs = math.floor(hs.timer.secondsSinceEpoch() - running.started)
    running = nil
    setTitle()
    local out = ((stdout or "") .. (stderr or "")):gsub("%s+$", "")
    log:i(string.format('PixelButtons: %s exit=%d in %ds: %s', btn.task, code, secs, out))
    local ok = code == 0
    hs.notify.new({
        title = (ok and "✅ " or "❌ ") .. btn.label,
        informativeText = ok and string.format("done in %ds", secs) or out:sub(1, 200),
        withdrawAfter = ok and 8 or 0,
    }):send()
end

function M.fire(btn)
    if running then
        hs.alert.show("Phone busy: " .. running.task .. " is still running")
        return
    end
    local dev, how = pickDevice()
    if not dev then
        hs.alert.show("Phone offline: plug in USB or run tunnelup")
        return
    end
    if btn.confirm then
        local choice = hs.dialog.blockAlert(btn.label, btn.confirm, "Run it", "Cancel")
        if choice ~= "Run it" then return end
    end
    local args = { "run", "--quiet", "--project", DGM_PROJECT, "dgm", "-d", dev, "do", btn.task }
    if btn.par1 then table.insert(args, btn.par1) end
    if btn.par2 then table.insert(args, btn.par2) end
    for _, a in ipairs({ "--force", "-w", tostring(btn.wait or 60) }) do table.insert(args, a) end
    local proc = hs.task.new(UV, function(code, out, err) finish(btn, code, out, err) end, args)
    proc:setEnvironment(ENV)
    running = { task = btn.task, started = hs.timer.secondsSinceEpoch(), proc = proc }
    setTitle()
    proc:start()
    hs.alert.show("▶ " .. btn.label .. " (" .. how .. ")")
end

local function buildMenu()
    local items = {}
    local _, how = pickDevice()
    table.insert(items, { title = "Phone: " .. how, disabled = true })
    if running then
        table.insert(items, { title = string.format("Running %s (%ds)", running.task,
            math.floor(hs.timer.secondsSinceEpoch() - running.started)), disabled = true })
        table.insert(items, { title = "Stop waiting (the phone keeps going)", fn = function()
            if running and running.proc then running.proc:terminate() end
        end })
    end
    table.insert(items, { title = "-" })
    local buttons = loadButtons()
    if not buttons then
        table.insert(items, { title = "buttons.json unreadable: see console", disabled = true })
    else
        local group = nil
        for _, btn in ipairs(buttons) do
            if btn.group ~= group then
                if group then table.insert(items, { title = "-" }) end
                table.insert(items, { title = btn.group or "", disabled = true })
                group = btn.group
            end
            table.insert(items, {
                title = "   " .. btn.label,
                tooltip = btn.hint,
                disabled = running ~= nil or how == "offline",
                fn = function() M.fire(btn) end,
            })
        end
    end
    table.insert(items, { title = "-" })
    table.insert(items, { title = "Edit buttons…", fn = function()
        hs.task.new("/usr/bin/open", nil, { "-t", BUTTONS_FILE }):start()
    end })
    return items
end

function M.start()
    if menu then return M end
    menu = hs.menubar.new()
    menu:setTooltip("Pixel: fire Tasker tasks")
    menu:setMenu(buildMenu)
    setTitle()
    log:i('PixelButtons: menubar ready (' .. BUTTONS_FILE .. ')')
    return M
end

M.start()
_G.PixelButtons = M
return M
