-- Spoons/HammerGhost.spoon/scripts/event_bus.lua
--
-- Central event bus for HammerGhost. System watchers normalize their raw
-- callbacks into EventGhost-style dotted names (App.Activated.Safari) and emit
-- them here. The live log panel subscribes to display them; macro triggers will
-- subscribe later to fire actions on a match.
--
-- A capped ring buffer keeps recent history so the log can be back-filled when
-- the window opens after events have already fired (the watcher runs whether or
-- not the window is visible).

-- Singleton: modules load this with dofile(), which (unlike require) does NOT
-- cache — each call returns a fresh table. The watcher, log forwarder, and
-- webview renderer must share ONE bus, so the first load stashes the instance on
-- a global and later loads return it.
if rawget(_G, "_HammerGhostEventBus") then
    return _G._HammerGhostEventBus
end

local M = {}
_G._HammerGhostEventBus = M

M.MAX_HISTORY = 200
M.history = {}      -- ring buffer, oldest first; entries = {seq, name, payload, time}
M.subscribers = {}  -- list of fn(event)
M.seq = 0           -- monotonic counter for stable DOM keys

-- Emit a normalized event. Returns the event table.
function M.emit(name, payload)
    M.seq = M.seq + 1
    local event = {
        seq = M.seq,
        name = name,
        payload = payload,
        time = os.time(),
    }
    table.insert(M.history, event)
    -- Trim oldest entries beyond the cap so memory stays bounded.
    while #M.history > M.MAX_HISTORY do
        table.remove(M.history, 1)
    end
    -- Subscriber errors must not break the emit chain or stall the watcher.
    for _, fn in ipairs(M.subscribers) do
        local ok, err = pcall(fn, event)
        if not ok and _G.AppLogger then
            _G.AppLogger:e("event subscriber error: " .. tostring(err), "event_bus.lua", 0)
        end
    end
    return event
end

-- Subscribe fn(event). Returns an unsubscribe function.
function M.subscribe(fn)
    table.insert(M.subscribers, fn)
    return function()
        for i, s in ipairs(M.subscribers) do
            if s == fn then
                table.remove(M.subscribers, i)
                return
            end
        end
    end
end

-- Recent events in chronological order (oldest first), capped to n.
function M.recent(n)
    n = n or M.MAX_HISTORY
    local out = {}
    local start = math.max(1, #M.history - n + 1)
    for i = start, #M.history do
        out[#out + 1] = M.history[i]
    end
    return out
end

function M.clear()
    M.history = {}
end

return M
