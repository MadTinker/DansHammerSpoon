--- WindowTidy — occasional AI-assisted window arrangement.
---
--- Flow: snapshot visible windows -> compute overlap/waste locally -> ask a CLI
--- agent (gemini) for a better arrangement -> validate its answer -> queue the
--- moves and drain them one-per-tick after the agent run ends.
---
--- Hard rules enforced in Lua, never trusted to the model:
---   * the focused window is never moved
---   * every frame is clamped inside its screen's work area
---   * unknown window ids and degenerate sizes are dropped
---
--- The previous frames are stashed before each drain so a bad arrangement is
--- one hotkey away from undone.

if _G.WindowTidy then return _G.WindowTidy end

local WindowTidy = {}

local log = _G.AppLogger or require('HyperLogger').new('WindowTidy')
local WindowManager = _G.WindowManager or require('WindowManager')

-- Configuration -------------------------------------------------------------

WindowTidy.config = {
    gap = 8,             -- px of breathing room the model is told to leave
    minWidth = 320,      -- reject any proposed frame smaller than this
    minHeight = 240,
    drainInterval = 0.2, -- seconds between applying queued moves
    timeout = 90,        -- seconds before we give up on the agent
    model = nil,         -- nil = gemini's default; e.g. "gemini-2.5-pro"
    dryRun = false,      -- true = log the plan, queue nothing

    -- Run log. The console is ephemeral and a run finishes ~30s after the
    -- hotkey, long after you have looked away, so every run is also appended
    -- to a file you can read afterwards.
    logPath = os.getenv("HOME") .. "/.hammerspoon/data/windowtidy.log",
    maxLogBytes = 512 * 1024, -- rotate to .log.1 past this
    logRawResponse = true,    -- include the agent's raw stdout (verbose but
                              -- the only way to debug a bad plan)
}

-- Runtime state
WindowTidy.queue = {}       -- pending {id, frame, reason}
WindowTidy.undoStack = {}   -- {id, frame} captured just before each drain
WindowTidy.task = nil       -- in-flight hs.task
WindowTidy.drainTimer = nil
WindowTidy.lastPlan = nil   -- last decoded agent response, for inspection

-- Binary resolution ---------------------------------------------------------
-- hs.task does not inherit a login shell PATH, so probe for gemini explicitly.

local geminiPath = nil

local function resolveGemini()
    if geminiPath and hs.fs.attributes(geminiPath) then return geminiPath end

    local home = os.getenv("HOME") or ""
    local candidates = {
        "/opt/homebrew/bin/gemini",
        "/usr/local/bin/gemini",
        home .. "/.local/bin/gemini",
    }
    for _, c in ipairs(candidates) do
        if hs.fs.attributes(c) then geminiPath = c; return c end
    end

    -- Fall back to the user shell so nvm/asdf shims resolve.
    local p = (hs.execute("which gemini", true) or ""):gsub("%s+$", "")
    if p ~= "" and hs.fs.attributes(p) then geminiPath = p; return p end

    return nil
end

-- Run log -------------------------------------------------------------------

--- Roll the log over once it gets fat, keeping one previous generation.
local function rotateLogIfNeeded(path)
    local attrs = hs.fs.attributes(path)
    if attrs and attrs.size and attrs.size > WindowTidy.config.maxLogBytes then
        os.remove(path .. ".1")
        os.rename(path, path .. ".1")
    end
end

--- Append a timestamped line to the run log. Never throws: a logging failure
--- must not take down a window move.
local function logLine(fmt, ...)
    local ok, msg = pcall(string.format, fmt, ...)
    if not ok then msg = tostring(fmt) end

    log:i('WindowTidy: ' .. msg)

    local path = WindowTidy.config.logPath
    if not path then return end

    pcall(function()
        rotateLogIfNeeded(path)
        local f = io.open(path, "a")
        if not f then return end
        f:write(os.date("%Y-%m-%d %H:%M:%S "), msg, "\n")
        f:close()
    end)
end

--- Section header so separate runs are easy to tell apart when scrolling.
local function logHeader(title)
    pcall(function()
        local f = io.open(WindowTidy.config.logPath, "a")
        if not f then return end
        f:write("\n", string.rep("=", 72), "\n")
        f:close()
    end)
    logLine("=== %s ===", title)
end

WindowTidy.log = logLine

--- Open the run log in the user's default editor.
function WindowTidy.showLog()
    local path = WindowTidy.config.logPath
    if not hs.fs.attributes(path) then
        hs.alert.show("WindowTidy: no log yet")
        return
    end
    hs.execute("open -t '" .. path:gsub("'", "'\\''") .. "'")
end

--- Dump the tail of the log straight into the Hammerspoon console.
function WindowTidy.tailLog(lines)
    lines = lines or 40
    local path = WindowTidy.config.logPath
    if not hs.fs.attributes(path) then
        print("WindowTidy: no log at " .. tostring(path))
        return
    end
    local out = hs.execute(string.format("tail -n %d '%s'", lines, path:gsub("'", "'\\''")))
    print(out or "")
end

-- Snapshot ------------------------------------------------------------------

local function roundRect(f)
    return {
        x = math.floor(f.x + 0.5),
        y = math.floor(f.y + 0.5),
        w = math.floor(f.w + 0.5),
        h = math.floor(f.h + 0.5),
    }
end

-- Screens ordered left-to-right so indices in the prompt are stable and match
-- the ordering WindowManager already uses for monitor commands.
local function orderedScreens()
    local screens = hs.screen.allScreens()
    table.sort(screens, function(a, b)
        local fa, fb = a:frame(), b:frame()
        if fa.x == fb.x then return fa.y < fb.y end
        return fa.x < fb.x
    end)
    return screens
end

--- Area of the intersection of two rects. 0 when they do not touch.
local function overlapArea(a, b)
    local dx = math.min(a.x + a.w, b.x + b.w) - math.max(a.x, b.x)
    local dy = math.min(a.y + a.h, b.y + b.h) - math.max(a.y, b.y)
    if dx <= 0 or dy <= 0 then return 0 end
    return dx * dy
end

--- Build the state the agent reasons over: screens, windows, and the overlap
--- pairs we already computed so the model does not have to do geometry.
function WindowTidy.snapshot()
    local focused = hs.window.focusedWindow()
    local focusedId = focused and focused:id() or nil

    local screens = orderedScreens()
    local screenIndexById = {}
    local screenList = {}
    for i, s in ipairs(screens) do
        screenIndexById[s:id()] = i
        screenList[i] = {
            index = i,
            name = s:name(),
            workArea = roundRect(s:frame()), -- frame() excludes menubar/dock
        }
    end

    local windows = {}
    for _, win in ipairs(hs.window.visibleWindows()) do
        local scr = win:screen()
        if win:isStandard() and not win:isMinimized() and scr then
            local app = win:application()
            local title = win:title() or ""
            if #title > 80 then title = title:sub(1, 77) .. "..." end
            windows[#windows + 1] = {
                id = win:id(),
                app = app and app:name() or "unknown",
                title = title,
                screen = screenIndexById[scr:id()] or 1,
                frame = roundRect(win:frame()),
                focused = (win:id() == focusedId) or nil,
            }
        end
    end

    -- Pairwise overlaps, same screen only.
    local overlaps = {}
    for i = 1, #windows do
        for j = i + 1, #windows do
            local a, b = windows[i], windows[j]
            if a.screen == b.screen then
                local area = overlapArea(a.frame, b.frame)
                if area > 0 then
                    local smaller = math.min(a.frame.w * a.frame.h, b.frame.w * b.frame.h)
                    overlaps[#overlaps + 1] = {
                        a = a.id, b = b.id,
                        area = area,
                        pctOfSmaller = math.floor(area / smaller * 100),
                    }
                end
            end
        end
    end

    return {
        screens = screenList,
        windows = windows,
        overlaps = overlaps,
        focusedWindowId = focusedId,
    }
end

-- Prompt --------------------------------------------------------------------

local PROMPT_RULES = [[
You are a window-layout optimizer for a macOS desktop. You will receive JSON
describing the screens (their usable work areas, in global desktop coordinates)
and the currently visible windows with their frames, plus a precomputed list of
overlapping window pairs.

Propose a better arrangement that makes fuller use of the screens.

Rules:
- NEVER propose a move for the window whose "focused" field is true. Omit it.
- Keep every window on the screen it is already on. Do not migrate windows
  between screens.
- Every proposed frame must sit entirely inside that screen's workArea.
- Eliminate the listed overlaps where you reasonably can.
- Leave a %d px gap between adjacent windows and between windows and the work
  area edges.
- No window smaller than %dx%d.
- Prefer tiling related apps side by side; give editors/browsers more area than
  chat or utility windows.
- Only include windows whose position or size you are actually changing. A short
  plan is a good plan.

Respond with RAW JSON ONLY. No markdown, no code fences, no prose before or
after. Exact shape:

{"moves":[{"id":12345,"x":0,"y":25,"w":1280,"h":1415,"reason":"why"}],
 "summary":"one sentence"}

Here is the current desktop state:
]]

local function buildPrompt(snapshot)
    local cfg = WindowTidy.config
    local rules = string.format(PROMPT_RULES, cfg.gap, cfg.minWidth, cfg.minHeight)
    return rules .. hs.json.encode(snapshot)
end

-- Response parsing ----------------------------------------------------------

--- Agents habitually wrap JSON in fences or chatter. Pull out the outermost
--- balanced {...} block and decode that.
---
--- gemini's headless mode adds another layer: it prints an envelope
--- {"session_id":...,"response":"<the model's actual text>","stats":{...}}
--- where the payload we want is a JSON *string* inside .response. So after
--- decoding we unwrap that field and parse again.
function WindowTidy.extractJson(text, unwrapDepth)
    unwrapDepth = unwrapDepth or 0
    if not text or text == "" or unwrapDepth > 3 then return nil end

    local fenced = text:match("```%s*json%s*(.-)```") or text:match("```(.-)```")
    if fenced then text = fenced end

    local startIdx = text:find("{")
    if not startIdx then return nil end

    local depth, inString, escaped = 0, false, false
    for i = startIdx, #text do
        local c = text:sub(i, i)
        if inString then
            if escaped then escaped = false
            elseif c == "\\" then escaped = true
            elseif c == '"' then inString = false end
        elseif c == '"' then inString = true
        elseif c == "{" then depth = depth + 1
        elseif c == "}" then
            depth = depth - 1
            if depth == 0 then
                local ok, decoded = pcall(hs.json.decode, text:sub(startIdx, i))
                if not ok or type(decoded) ~= "table" then return nil end
                -- Envelope, not the plan itself: unwrap and parse the inner text.
                if decoded.moves == nil and type(decoded.response) == "string" then
                    return WindowTidy.extractJson(decoded.response, unwrapDepth + 1)
                end
                return decoded
            end
        end
    end
    return nil
end

-- Validation ----------------------------------------------------------------

local function clamp(v, lo, hi) return math.max(lo, math.min(v, hi)) end

--- Squeeze a proposed frame into the work area, or return nil if it is junk.
local function sanitizeFrame(proposed, workArea)
    local cfg = WindowTidy.config

    -- Oversized is clamped down; undersized is rejected outright. Silently
    -- growing a too-small frame would break the tiling the model planned
    -- around it, so a violation of the stated minimum drops the whole move.
    local w = math.min(math.floor(proposed.w or 0), workArea.w)
    local h = math.min(math.floor(proposed.h or 0), workArea.h)
    if w < cfg.minWidth or h < cfg.minHeight then return nil end

    local x = clamp(math.floor(proposed.x or 0), workArea.x, workArea.x + workArea.w - w)
    local y = clamp(math.floor(proposed.y or 0), workArea.y, workArea.y + workArea.h - h)

    return { x = x, y = y, w = w, h = h }
end

--- Filter the agent's moves down to ones we are willing to perform.
--- Returns the accepted move list and a list of human-readable rejections.
function WindowTidy.validatePlan(plan, snapshot)
    local accepted, rejected = {}, {}
    if type(plan) ~= "table" or type(plan.moves) ~= "table" then
        return accepted, { "response had no 'moves' array" }
    end

    local byId = {}
    for _, w in ipairs(snapshot.windows) do byId[w.id] = w end

    local workAreaByIndex = {}
    for _, s in ipairs(snapshot.screens) do workAreaByIndex[s.index] = s.workArea end

    local seen = {}

    for _, move in ipairs(plan.moves) do
        local id = tonumber(move.id)
        local known = id and byId[id]

        if not known then
            rejected[#rejected + 1] = "unknown window id " .. tostring(move.id)
        elseif id == snapshot.focusedWindowId then
            rejected[#rejected + 1] = known.app .. ": refused, window is focused"
        elseif seen[id] then
            rejected[#rejected + 1] = known.app .. ": duplicate move"
        else
            local frame = sanitizeFrame(move, workAreaByIndex[known.screen])
            if not frame then
                rejected[#rejected + 1] = known.app .. ": degenerate frame"
            else
                local cur = known.frame
                local moved = math.abs(frame.x - cur.x) > 4 or math.abs(frame.y - cur.y) > 4
                    or math.abs(frame.w - cur.w) > 4 or math.abs(frame.h - cur.h) > 4
                if not moved then
                    rejected[#rejected + 1] = known.app .. ": no-op"
                else
                    seen[id] = true
                    accepted[#accepted + 1] = {
                        id = id,
                        app = known.app,
                        frame = frame,
                        reason = move.reason or "",
                    }
                end
            end
        end
    end

    return accepted, rejected
end

-- Queue drain ---------------------------------------------------------------

--- Apply one queued move per tick. Re-checks focus at apply time, since the
--- user may well have clicked something else while the agent was thinking.
local function drainTick()
    local move = table.remove(WindowTidy.queue, 1)
    if not move then
        if WindowTidy.drainTimer then
            WindowTidy.drainTimer:stop()
            WindowTidy.drainTimer = nil
        end
        logLine("DONE: queue drained, %d window(s) can be undone", #WindowTidy.undoStack)
        return
    end

    local win = hs.window.get(move.id)
    if not win then
        logLine("  SKIP %s (%d): window no longer exists", move.app, move.id)
        return
    end

    local focused = hs.window.focusedWindow()
    if focused and focused:id() == move.id then
        logLine("  SKIP %s (%d): window took focus while the agent was thinking",
            move.app, move.id)
        return
    end

    local before = win:frame()
    WindowTidy.undoStack[#WindowTidy.undoStack + 1] = { id = move.id, frame = before }

    local okFrame = WindowManager.setFrameInScreenWithRetry(win, hs.geometry.rect(move.frame))
    local after = win:frame()
    logLine("  %s %s (%d): %d,%d %dx%d -> %d,%d %dx%d",
        okFrame and "MOVED" or "PARTIAL", move.app, move.id,
        math.floor(before.x), math.floor(before.y), math.floor(before.w), math.floor(before.h),
        math.floor(after.x), math.floor(after.y), math.floor(after.w), math.floor(after.h))
end

--- Hand a validated move list to the drain loop.
function WindowTidy.enqueue(moves)
    if #moves == 0 then return end

    WindowTidy.undoStack = {}
    for _, m in ipairs(moves) do
        WindowTidy.queue[#WindowTidy.queue + 1] = m
    end

    if not WindowTidy.drainTimer then
        WindowTidy.drainTimer = hs.timer.doEvery(WindowTidy.config.drainInterval, drainTick)
    end
end

--- Put every window the last run touched back where it was.
function WindowTidy.undo()
    if #WindowTidy.undoStack == 0 then
        hs.alert.show("WindowTidy: nothing to undo")
        return
    end

    logHeader("UNDO")
    local restored = 0
    for _, entry in ipairs(WindowTidy.undoStack) do
        local win = hs.window.get(entry.id)
        if win then
            WindowManager.setFrameInScreenWithRetry(win, entry.frame)
            restored = restored + 1
        else
            logLine("  SKIP %d: window no longer exists", entry.id)
        end
    end
    logLine("restored %d of %d window(s)", restored, #WindowTidy.undoStack)

    WindowTidy.undoStack = {}
    hs.alert.show("WindowTidy: restored " .. restored .. " windows")
end

-- Agent invocation ----------------------------------------------------------

local function handleResponse(snapshot, stdOut, stdErr, exitCode)
    WindowTidy.lastResponse = stdOut

    if WindowTidy.config.logRawResponse then
        logLine("raw stdout (%d bytes):\n%s", #(stdOut or ""), stdOut or "<empty>")
    end
    if stdErr and stdErr ~= "" then
        logLine("stderr:\n%s", stdErr)
    end

    if exitCode ~= 0 then
        hs.alert.show("WindowTidy: agent failed (" .. tostring(exitCode) .. ") — see log")
        logLine("ABORT: agent exited non-zero")
        return
    end

    local plan = WindowTidy.extractJson(stdOut)
    if not plan then
        hs.alert.show("WindowTidy: unparseable response — see log")
        logLine("ABORT: no decodable JSON object in the agent output")
        return
    end

    WindowTidy.lastPlan = plan
    if plan.summary then logLine("agent summary: %s", tostring(plan.summary)) end
    logLine("agent proposed %d move(s)", (type(plan.moves) == "table") and #plan.moves or 0)

    local moves, rejected = WindowTidy.validatePlan(plan, snapshot)
    for _, r in ipairs(rejected) do logLine("  REJECTED %s", r) end
    for _, m in ipairs(moves) do
        logLine("  ACCEPTED %s (%d) -> %d,%d %dx%d  |  %s",
            m.app, m.id, m.frame.x, m.frame.y, m.frame.w, m.frame.h, m.reason)
    end

    if #moves == 0 then
        hs.alert.show("WindowTidy: no usable moves — see log")
        logLine("DONE: nothing survived validation")
        return
    end

    if WindowTidy.config.dryRun then
        local lines = { "WindowTidy dry run — " .. #moves .. " moves:" }
        for _, m in ipairs(moves) do
            lines[#lines + 1] = string.format("%s -> %d,%d %dx%d (%s)",
                m.app, m.frame.x, m.frame.y, m.frame.w, m.frame.h, m.reason)
        end
        local text = table.concat(lines, "\n")
        logLine("DRY RUN: queueing nothing")
        hs.alert.show(text, 6)
        return
    end

    hs.alert.show("WindowTidy: applying " .. #moves .. " moves")
    logLine("queueing %d move(s)", #moves)
    WindowTidy.enqueue(moves)
end

--- Snapshot the desktop, ask the agent, and queue whatever survives validation.
function WindowTidy.run()
    if WindowTidy.task and WindowTidy.task:isRunning() then
        hs.alert.show("WindowTidy: already thinking")
        logLine("IGNORED: a run is already in flight")
        return
    end
    if WindowTidy.drainTimer then
        hs.alert.show("WindowTidy: still applying the last plan")
        logLine("IGNORED: still draining the previous plan")
        return
    end

    logHeader(WindowTidy.config.dryRun and "RUN (dry run)" or "RUN")

    local bin = resolveGemini()
    if not bin then
        hs.alert.show("WindowTidy: gemini CLI not found — see log")
        logLine("ABORT: could not resolve a gemini binary on any known path")
        return
    end
    logLine("binary: %s", bin)

    local snapshot = WindowTidy.snapshot()
    if #snapshot.windows < 2 then
        hs.alert.show("WindowTidy: not enough windows")
        logLine("ABORT: only %d visible standard window(s)", #snapshot.windows)
        return
    end

    logLine("%d screen(s), %d window(s), %d overlap pair(s)",
        #snapshot.screens, #snapshot.windows, #snapshot.overlaps)
    for _, w in ipairs(snapshot.windows) do
        logLine("  window %d  %-22s screen %d  %d,%d %dx%d%s",
            w.id, w.app, w.screen, w.frame.x, w.frame.y, w.frame.w, w.frame.h,
            w.focused and "   <- FOCUSED, will not be moved" or "")
    end
    for _, o in ipairs(snapshot.overlaps) do
        logLine("  overlap %d <-> %d  %d px^2 (%d%% of the smaller window)",
            o.a, o.b, o.area, o.pctOfSmaller)
    end

    -- --skip-trust: headless gemini refuses to run in an untrusted directory,
    -- and hs.task inherits Hammerspoon's cwd, which will never be trusted.
    local args = { "-y", "--skip-trust", "-p", buildPrompt(snapshot) }
    if WindowTidy.config.model then
        table.insert(args, 1, WindowTidy.config.model)
        table.insert(args, 1, "-m")
    end

    local out, err = {}, {}
    local startedAt = hs.timer.secondsSinceEpoch()

    WindowTidy.task = hs.task.new(bin,
        function(exitCode)
            WindowTidy.task = nil
            logLine("agent exited %s after %.1fs",
                tostring(exitCode), hs.timer.secondsSinceEpoch() - startedAt)
            handleResponse(snapshot, table.concat(out), table.concat(err), exitCode)
        end,
        function(_task, stdOut, stdErr)
            if stdOut and stdOut ~= "" then out[#out + 1] = stdOut end
            if stdErr and stdErr ~= "" then err[#err + 1] = stdErr end
            return true
        end,
        args)

    -- gemini needs HOME for its credentials and a PATH that includes node.
    local home = os.getenv("HOME") or ""
    WindowTidy.task:setEnvironment({
        HOME = home,
        PATH = (os.getenv("PATH") or "") ..
            ":/opt/homebrew/bin:/usr/local/bin:" .. home .. "/.local/bin:" ..
            bin:match("^(.*)/[^/]+$"),
        TERM = "dumb",
    })

    hs.alert.show("WindowTidy: asking the agent about " .. #snapshot.windows .. " windows...")
    logLine("dispatching %s for %d windows", bin, #snapshot.windows)
    WindowTidy.task:start()

    hs.timer.doAfter(WindowTidy.config.timeout, function()
        if WindowTidy.task and WindowTidy.task:isRunning() then
            WindowTidy.task:terminate()
            WindowTidy.task = nil
            hs.alert.show("WindowTidy: agent timed out")
            logLine("ABORT: killed the agent after %ds", WindowTidy.config.timeout)
        end
    end)
end

--- Same run, but only report the plan instead of applying it.
function WindowTidy.preview()
    local was = WindowTidy.config.dryRun
    WindowTidy.config.dryRun = true
    WindowTidy.run()
    hs.timer.doAfter(WindowTidy.config.timeout + 1, function()
        WindowTidy.config.dryRun = was
    end)
end

_G.WindowTidy = WindowTidy
return WindowTidy
