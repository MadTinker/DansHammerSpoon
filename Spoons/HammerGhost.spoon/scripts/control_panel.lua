-- === HammerGhost Control Panel ===
-- Mad Tinker Dashboard — a floating command center for all active Hammerspoon spoons
-- Dark theme. Glowing indicators. Toggle buttons. NO BORING ENTERPRISE UI.

local M = {}

-- ─────────────────────────────────────────────────────────────────────────────
-- DASHBOARD HTML
-- ─────────────────────────────────────────────────────────────────────────────

local PANEL_HTML = [[
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Mad Tinker Dashboard</title>
<style>
  :root {
    --bg:         #090912;
    --card-bg:    #0f0f1c;
    --border:     #1c1c35;
    --active:     #00ffa3;
    --inactive:   #ff3366;
    --idle:       #ffc040;
    --text:       #c4cde0;
    --text-dim:   #484e6a;
    --accent:     #7b5fff;
    --accent2:    #00d4ff;
    --btn-bg:     #14142a;
    --btn-hover:  #1e1e40;
    --header-bg:  #07070f;
  }

  * { box-sizing: border-box; margin: 0; padding: 0; }

  html, body {
    background: var(--bg);
    color: var(--text);
    font-family: 'Menlo', 'Monaco', 'Courier New', monospace;
    font-size: 11px;
    height: 100vh;
    overflow: hidden;
    user-select: none;
    -webkit-user-select: none;
  }

  /* ── Header ── */
  .header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 8px 14px;
    background: var(--header-bg);
    border-bottom: 1px solid var(--border);
    height: 36px;
  }

  .header-left {
    display: flex;
    align-items: center;
    gap: 8px;
  }

  .header-title {
    font-size: 11px;
    font-weight: bold;
    letter-spacing: 3px;
    color: var(--accent);
    text-transform: uppercase;
  }

  .header-sep { color: var(--border); }

  .header-sub {
    font-size: 9px;
    letter-spacing: 1px;
    color: var(--text-dim);
    text-transform: uppercase;
  }

  .header-right {
    display: flex;
    align-items: center;
    gap: 10px;
  }

  .online-badge {
    display: flex;
    align-items: center;
    gap: 5px;
    font-size: 9px;
    letter-spacing: 1px;
    color: var(--active);
    text-transform: uppercase;
  }

  .pulse-dot {
    width: 6px; height: 6px;
    border-radius: 50%;
    background: var(--active);
    box-shadow: 0 0 6px var(--active);
    animation: pulse 2.2s ease-in-out infinite;
  }

  @keyframes pulse {
    0%, 100% { opacity: 1;   box-shadow: 0 0 6px var(--active); }
    50%       { opacity: 0.4; box-shadow: 0 0 2px var(--active); }
  }

  .reload-btn {
    padding: 2px 8px;
    border: 1px solid var(--border);
    border-radius: 3px;
    background: transparent;
    color: var(--text-dim);
    font-family: inherit;
    font-size: 9px;
    cursor: pointer;
    letter-spacing: 1px;
    text-transform: uppercase;
    transition: all 0.15s;
  }
  .reload-btn:hover {
    border-color: var(--accent2);
    color: var(--accent2);
  }

  /* ── Grid ── */
  .grid {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 8px;
    padding: 10px;
    overflow-y: auto;
    height: calc(100vh - 36px);
  }

  /* Custom scrollbar */
  .grid::-webkit-scrollbar { width: 4px; }
  .grid::-webkit-scrollbar-track { background: var(--bg); }
  .grid::-webkit-scrollbar-thumb { background: var(--border); border-radius: 2px; }

  /* ── Cards ── */
  .card {
    background: var(--card-bg);
    border: 1px solid var(--border);
    border-radius: 5px;
    padding: 10px 10px 8px;
    transition: border-color 0.2s, box-shadow 0.2s;
    display: flex;
    flex-direction: column;
    gap: 6px;
    min-height: 120px;
  }

  .card:hover {
    border-color: #2a2a50;
  }

  .card.is-active {
    border-color: rgba(0, 255, 163, 0.3);
    box-shadow: 0 0 14px rgba(0, 255, 163, 0.06);
  }

  .card.is-busy {
    border-color: rgba(255, 192, 64, 0.4);
    box-shadow: 0 0 14px rgba(255, 192, 64, 0.08);
  }

  /* ── Card header row ── */
  .card-head {
    display: flex;
    align-items: center;
    justify-content: space-between;
  }

  .card-ident {
    display: flex;
    align-items: center;
    gap: 6px;
  }

  .card-icon { font-size: 15px; line-height: 1; }

  .card-name {
    font-size: 10px;
    font-weight: bold;
    letter-spacing: 0.8px;
    color: #dce4ff;
    text-transform: uppercase;
  }

  /* ── LED indicator ── */
  .led {
    width: 8px; height: 8px;
    border-radius: 50%;
    flex-shrink: 0;
    transition: background 0.3s, box-shadow 0.3s;
  }
  .led-on   { background: var(--active);   box-shadow: 0 0 7px var(--active); }
  .led-off  { background: #22223a;         box-shadow: none; }
  .led-busy { background: var(--idle);     box-shadow: 0 0 7px var(--idle);
              animation: pulse 0.7s infinite; }

  /* ── Description ── */
  .card-desc {
    font-size: 9px;
    color: var(--text-dim);
    line-height: 1.5;
    flex: 1;
  }

  /* ── Action row ── */
  .card-actions {
    display: flex;
    gap: 5px;
    flex-wrap: wrap;
  }

  .btn {
    padding: 3px 9px;
    border: 1px solid var(--border);
    border-radius: 3px;
    background: var(--btn-bg);
    color: var(--text-dim);
    font-family: inherit;
    font-size: 9px;
    letter-spacing: 0.8px;
    text-transform: uppercase;
    cursor: pointer;
    transition: all 0.15s;
  }
  .btn:hover { background: var(--btn-hover); }

  .btn-engage  { border-color: rgba(0, 255, 163, 0.4); color: var(--active); }
  .btn-engage:hover  { background: rgba(0, 255, 163, 0.08); border-color: var(--active); }

  .btn-kill    { border-color: rgba(255, 51, 102, 0.4); color: var(--inactive); }
  .btn-kill:hover    { background: rgba(255, 51, 102, 0.08); border-color: var(--inactive); }

  .btn-accent  { border-color: rgba(123, 95, 255, 0.5); color: var(--accent); }
  .btn-accent:hover  { background: rgba(123, 95, 255, 0.1); border-color: var(--accent); }

  .btn-info    { border-color: rgba(0, 212, 255, 0.4); color: var(--accent2); }
  .btn-info:hover    { background: rgba(0, 212, 255, 0.08); border-color: var(--accent2); }

  /* ── Status line ── */
  .card-status {
    font-size: 8px;
    color: var(--text-dim);
    letter-spacing: 0.5px;
    margin-top: 2px;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .card-status .hi { color: var(--active); }
  .card-status .warn { color: var(--idle); }

  /* ── Empty state ── */
  .empty {
    grid-column: 1/-1;
    text-align: center;
    padding: 40px;
    color: var(--text-dim);
    font-size: 11px;
    letter-spacing: 1px;
  }
</style>
</head>
<body>

<div class="header">
  <div class="header-left">
    <span class="header-title">⚡ HammerGhost</span>
    <span class="header-sep">│</span>
    <span class="header-sub">Mad Tinker Dashboard</span>
  </div>
  <div class="header-right">
    <div class="online-badge">
      <div class="pulse-dot"></div>
      ONLINE
    </div>
    <button class="reload-btn" onclick="requestState()">⟳ REFRESH</button>
  </div>
</div>

<div class="grid" id="card-grid">
  <div class="empty">⚙ Initializing contraptions…</div>
</div>

<script>
function nav(path) {
  window.location = 'hammerspoon://controlPanel?' + path;
}

function requestState() {
  nav('action=getState&spoon=all');
}

function toggleSpoon(id) {
  nav('action=toggle&spoon=' + encodeURIComponent(id));
}

function actionSpoon(id, cmd, param) {
  var path = 'action=' + encodeURIComponent(cmd) + '&spoon=' + encodeURIComponent(id);
  if (param) path += '&param=' + encodeURIComponent(param);
  nav(path);
}

function renderCards(cards) {
  var grid = document.getElementById('card-grid');
  if (!cards || cards.length === 0) {
    grid.innerHTML = '<div class="empty">No contraptions detected. Check your loadConfig.lua.</div>';
    return;
  }

  var html = '';
  for (var i = 0; i < cards.length; i++) {
    var c = cards[i];
    var isActive = !!c.active;
    var isBusy   = !!c.busy;

    var cardCls = 'card';
    if (isBusy)   cardCls += ' is-busy';
    else if (isActive) cardCls += ' is-active';

    var ledCls = isBusy ? 'led led-busy' : (isActive ? 'led led-on' : 'led led-off');

    html += '<div class="' + cardCls + '">';

    // Header row
    html += '<div class="card-head">';
    html += '<div class="card-ident">';
    html += '<span class="card-icon">' + (c.icon || '⚙') + '</span>';
    html += '<span class="card-name">' + escHtml(c.name) + '</span>';
    html += '</div>';
    html += '<div class="' + ledCls + '"></div>';
    html += '</div>';

    // Description
    html += '<div class="card-desc">' + escHtml(c.desc || '') + '</div>';

    // Actions
    html += '<div class="card-actions">';
    if (c.toggleable) {
      if (isActive) {
        html += '<button class="btn btn-kill" onclick="toggleSpoon(\'' + c.id + '\')">DISENGAGE</button>';
      } else {
        html += '<button class="btn btn-engage" onclick="toggleSpoon(\'' + c.id + '\')">ENGAGE</button>';
      }
    }
    if (c.actions) {
      for (var j = 0; j < c.actions.length; j++) {
        var a = c.actions[j];
        var btnCls = a.style ? 'btn btn-' + a.style : 'btn btn-accent';
        html += '<button class="' + btnCls + '" onclick="actionSpoon(\'' + c.id + '\',\'' + a.cmd + '\',\'' + (a.param || '') + '\')">' + escHtml(a.label) + '</button>';
      }
    }
    html += '</div>';

    // Status line
    if (c.status) {
      html += '<div class="card-status">' + c.status + '</div>';
    }

    html += '</div>'; // .card
  }

  grid.innerHTML = html;
}

function escHtml(s) {
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

// Boot: request state on load
window.addEventListener('load', function() {
  requestState();
});
</script>
</body>
</html>
]]

-- ─────────────────────────────────────────────────────────────────────────────
-- Internal state
-- ─────────────────────────────────────────────────────────────────────────────

local panelWindow = nil

-- ─────────────────────────────────────────────────────────────────────────────
-- Card builder — introspects loaded spoons and builds JSON-ready card tables
-- ─────────────────────────────────────────────────────────────────────────────

local function buildCards()
    local cards = {}

    -- ── KineticLatch ─────────────────────────────────────────────────────────
    if spoon.KineticLatch then
        local running = spoon.KineticLatch:isRunning()
        local st = spoon.KineticLatch:getStatus()
        local stateStr = '<span class="' .. (running and 'hi' or '') .. '">' .. st.kineticState .. '</span>'
        table.insert(cards, {
            id         = "KineticLatch",
            name       = "KineticLatch",
            icon       = "⚡",
            desc       = "Alt+drag to latch windows · Alt+right-drag to reshape · any surface",
            active     = running,
            busy       = st.isDragging or st.isResizing,
            toggleable = true,
            status     = "STATE: " .. stateStr,
            actions    = {
                { label = "STATUS", cmd = "showStatus", style = "info" },
                { label = "DIAGNOSE", cmd = "diagnose", style = "accent" },
            }
        })
    end

    -- ── DragonGrid ───────────────────────────────────────────────────────────
    if spoon.DragonGrid then
        table.insert(cards, {
            id         = "DragonGrid",
            name       = "DragonGrid",
            icon       = "🐉",
            desc       = "Multi-level precision mouse grid · keyboard or click targeting",
            active     = false,
            toggleable = false,
            actions    = {
                { label = "ACTIVATE", cmd = "show",        style = "engage" },
                { label = "WINDOW MODE", cmd = "showWindow", style = "accent" },
            }
        })
    end

    -- ── OmniLadle ────────────────────────────────────────────────────────────
    if spoon.OmniLadle then
        local connected = spoon.OmniLadle.isInitialized == true
        local modeStr = spoon.OmniLadle.config and spoon.OmniLadle.config.clientMode or "?"
        table.insert(cards, {
            id         = "OmniLadle",
            name       = "OmniLadle",
            icon       = "🥄",
            desc       = "MCP client → Omnispindle · serves up data from the workshop depths",
            active     = connected,
            toggleable = false,
            status     = "MODE: " .. modeStr:upper(),
            actions    = {
                { label = "RECONNECT", cmd = "reconnect", style = connected and "info" or "engage" },
                { label = "STATUS",    cmd = "status",    style = "accent" },
            }
        })
    end

    -- ── AClock ───────────────────────────────────────────────────────────────
    if spoon.AClock then
        table.insert(cards, {
            id         = "AClock",
            name       = "AClock",
            icon       = "🕐",
            desc       = "Floating overlay clock · disappears on press",
            active     = false,
            toggleable = false,
            actions    = {
                { label = "SHOW CLOCK", cmd = "show", style = "engage" },
            }
        })
    end

    -- ── ClipShow ─────────────────────────────────────────────────────────────
    if spoon.ClipShow then
        table.insert(cards, {
            id         = "ClipShow",
            name       = "ClipShow",
            icon       = "📋",
            desc       = "Paste-friendly clipboard viewer with formatting preview",
            active     = false,
            toggleable = false,
            actions    = {
                { label = "SHOW CLIP", cmd = "show", style = "engage" },
            }
        })
    end

    -- ── ClipboardTool ────────────────────────────────────────────────────────
    if spoon.ClipboardTool then
        table.insert(cards, {
            id         = "ClipboardTool",
            name       = "ClipboardTool",
            icon       = "📎",
            desc       = "Persistent clipboard history · up to 100 entries",
            active     = false,
            toggleable = true,
        })
    end

    -- ── Layouts ──────────────────────────────────────────────────────────────
    if spoon.Layouts then
        table.insert(cards, {
            id         = "Layouts",
            name       = "Layouts",
            icon       = "🏗",
            desc       = "Named window layout presets · apply saved arrangements",
            active     = false,
            toggleable = false,
            actions    = {
                { label = "LIST", cmd = "list", style = "info" },
            }
        })
    end

    -- ── HammerGhost Macro Editor ─────────────────────────────────────────────
    -- Always present (we ARE inside HammerGhost)
    do
        local visible = spoon.HammerGhost and spoon.HammerGhost.window
            and spoon.HammerGhost.window:isVisible() or false
        local macroCount = 0
        if spoon.HammerGhost and spoon.HammerGhost.macroTree then
            macroCount = #spoon.HammerGhost.macroTree
        end
        table.insert(cards, {
            id         = "HammerGhost",
            name       = "Macro Editor",
            icon       = "👻",
            desc       = "EventGhost-style macro tree · actions, sequences, conditions",
            active     = visible,
            toggleable = true,
            status     = "MACROS: " .. macroCount,
            actions    = {
                { label = "NEW ACTION", cmd = "newAction", style = "accent" },
            }
        })
    end

    -- ── System / Quick actions ────────────────────────────────────────────────
    table.insert(cards, {
        id         = "_system",
        name       = "System",
        icon       = "⚙",
        desc       = "Reload config · lock screen · open Hammerspoon console",
        active     = true,
        toggleable = false,
        actions    = {
            { label = "RELOAD HS",   cmd = "reload",   style = "kill" },
            { label = "CONSOLE",     cmd = "console",  style = "info" },
            { label = "LOCK SCREEN", cmd = "lock",     style = "accent" },
        }
    })

    return cards
end

-- ─────────────────────────────────────────────────────────────────────────────
-- URL / action handler
-- ─────────────────────────────────────────────────────────────────────────────

-- Percent-decode a URL component. hs.urlevent has no unquote(); the JS side uses
-- encodeURIComponent (no form-style '+' for spaces), so we only decode %xx bytes.
local function urlDecode(s)
    if not s then return s end
    return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

local function handleURL(spoonObj, url)
    if type(url) ~= "string" then return end

    -- Only handle our custom scheme
    local cmd, args = url:match("hammerspoon://([^?]+)%??(.*)")
    if cmd ~= "controlPanel" then return end

    local params = {}
    if args then
        for k, v in args:gmatch("([^=&]+)=([^&]*)") do
            params[k] = urlDecode(v)
        end
    end

    local action  = params.action or ""
    local spoonId = params.spoon  or ""

    -- ── getState ─────────────────────────────────────────────────────────────
    if action == "getState" then
        M.refresh()

    -- ── toggle ───────────────────────────────────────────────────────────────
    elseif action == "toggle" then
        if spoonId == "KineticLatch" and spoon.KineticLatch then
            spoon.KineticLatch:toggle()
        elseif spoonId == "ClipboardTool" and spoon.ClipboardTool then
            if spoon.ClipboardTool.startWatching then
                spoon.ClipboardTool:startWatching()
            end
        elseif spoonId == "HammerGhost" and spoon.HammerGhost then
            spoon.HammerGhost:toggle()
        end
        hs.timer.doAfter(0.15, function() M.refresh() end)

    -- ── show ─────────────────────────────────────────────────────────────────
    elseif action == "show" then
        if spoonId == "DragonGrid" and spoon.DragonGrid then
            spoon.DragonGrid:createDragonGrid()
        elseif spoonId == "AClock" and spoon.AClock then
            spoon.AClock:show()
        elseif spoonId == "ClipShow" and spoon.ClipShow then
            spoon.ClipShow:show()
        end

    elseif action == "showWindow" then
        if spoonId == "DragonGrid" and spoon.DragonGrid then
            spoon.DragonGrid.windowMode = true
            spoon.DragonGrid:createDragonGrid()
        end

    -- ── KineticLatch specific ─────────────────────────────────────────────────
    elseif action == "showStatus" then
        if spoonId == "KineticLatch" and spoon.KineticLatch then
            spoon.KineticLatch:showStatus()
        end

    elseif action == "diagnose" then
        if spoonId == "KineticLatch" and spoon.KineticLatch then
            spoon.KineticLatch:diagnose()
        end

    -- ── OmniLadle ─────────────────────────────────────────────────────────────
    elseif action == "reconnect" then
        if spoonId == "OmniLadle" and spoon.OmniLadle then
            spoon.OmniLadle:start()
            hs.timer.doAfter(0.5, function() M.refresh() end)
        end

    elseif action == "status" then
        if spoonId == "OmniLadle" and spoon.OmniLadle then
            local s = tostring(spoon.OmniLadle.isInitialized)
            hs.alert.show("OmniLadle: " .. s, 3)
        end

    -- ── HammerGhost macro editor ───────────────────────────────────────────────
    elseif action == "newAction" then
        if spoon.HammerGhost then
            spoon.HammerGhost:addAction()
        end

    elseif action == "list" then
        -- Layouts — just show an alert listing saved layouts
        if spoon.Layouts and spoon.Layouts.layouts then
            local names = {}
            for k, _ in pairs(spoon.Layouts.layouts) do
                table.insert(names, k)
            end
            hs.alert.show("Layouts: " .. table.concat(names, ", "), 4)
        end

    -- ── System actions ─────────────────────────────────────────────────────────
    elseif action == "reload" then
        hs.reload()

    elseif action == "console" then
        hs.openConsole()

    elseif action == "lock" then
        hs.caffeinate.lockScreen()

    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Public API
-- ─────────────────────────────────────────────────────────────────────────────

--- M.show(spoonObj)
--- Opens the control panel. Creates window on first call.
function M.show(spoonObj)
    if panelWindow and panelWindow:isVisible() then
        return -- already up
    end

    if not panelWindow then
        -- Centre on main screen
        local sf = hs.screen.mainScreen():frame()
        local w, h = 680, 520
        local rect = {
            x = sf.x + math.floor((sf.w - w) / 2),
            y = sf.y + math.floor((sf.h - h) / 2),
            w = w,
            h = h,
        }

        panelWindow = hs.webview.new(rect, { developerExtrasEnabled = false })

        if not panelWindow then
            hs.logger.new("ControlPanel"):e("Failed to create control panel window")
            return
        end

        panelWindow:darkMode(true)
        panelWindow:allowTextEntry(false)
        panelWindow:level(hs.drawing.windowLevels.floating)
        panelWindow:windowStyle({ "titled", "closable", "miniaturizable", "resizable" })
        panelWindow:windowTitle("⚡ Mad Tinker Dashboard")
        panelWindow:allowNewWindows(false)

        panelWindow:navigationCallback(function(url)
            handleURL(spoonObj, url)
            -- Return true to cancel navigation for custom scheme URLs
            if type(url) == "string" and url:match("^hammerspoon://") then
                return true
            end
        end)

        panelWindow:html(PANEL_HTML)
    end

    panelWindow:show()
    -- Slight delay so the page can load before we push card data
    hs.timer.doAfter(0.3, function() M.refresh() end)
end

--- M.hide()
--- Hides the control panel.
function M.hide()
    if panelWindow then
        panelWindow:hide()
    end
end

--- M.toggle(spoonObj)
--- Shows or hides the control panel.
function M.toggle(spoonObj)
    if panelWindow and panelWindow:isVisible() then
        M.hide()
    else
        M.show(spoonObj)
    end
end

--- M.refresh()
--- Pushes fresh card data to the already-open dashboard.
function M.refresh()
    if not panelWindow then return end
    local cards = buildCards()
    local ok, json = pcall(hs.json.encode, cards)
    if ok then
        panelWindow:evaluateJavaScript("renderCards(" .. json .. ");")
    end
end

--- M.destroy()
--- Deletes the panel window and clears state.
function M.destroy()
    if panelWindow then
        panelWindow:delete()
        panelWindow = nil
    end
end

return M
