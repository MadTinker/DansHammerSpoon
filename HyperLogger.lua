-- HyperLogger.lua
-- A small namespaced console logger for Hammerspoon: colored, level-gated,
-- variadic. Same public API as before, minus the clickable-link machinery
-- (which was fragile and rarely used).
--
-- Public API (unchanged, so existing call sites keep working):
--   local log = HyperLogger.new(namespace, loglevel)   -- singleton per namespace
--   log:i(...) / log:d(...) / log:w(...) / log:e(...)   -- info/debug/warn/error
--   log:setLogLevel(level) / log:getLogLevel()
--   HyperLogger.getLoggers() / getCreationStack(ns) / resetLoggers()
--
-- Behaviour notes:
--   * Level gating now actually works. A logger created at "info" drops its
--     debug lines instead of printing everything forever.
--   * Every level method is variadic: log:i('applied', name, 'from', old, to)
--     concatenates its args with spaces, hs.inspect()-ing tables. This is what
--     nearly every call site already assumed.
--   * Calls made with a dot (log.i(...)) are tolerated as well as the intended
--     colon form (log:i(...)); the leading self is detected and dropped. This
--     un-breaks the ~2 dozen dot-form call sites that were silently logging
--     "[nil]".
--   * A trailing (file.lua, line) pair is still recognised and rendered as a
--     dim source suffix, so the old (message, file, line) callers stay tidy.
--     When absent, the caller's own file:line is derived automatically.

local HyperLogger = {}

local loggers = {}          -- namespace -> logger (singletons)
local creationStacks = {}   -- namespace -> where it was first created
local DEFAULT_LOG_LEVEL = "info"  -- quiet by default; opt into debug via cycle

-- hs.logger's ordering. Lower number = more severe. A message prints when its
-- severity number is <= the logger's configured level number.
local LEVELS = {
    nothing = 0, error = 1, warning = 2, info = 3, debug = 4, verbose = 5,
}

local LEVEL_META = {
    info    = { num = 3, color = { red = 0.3, green = 0.7, blue = 1.0 }, tag = "INFO" },
    debug   = { num = 4, color = { white = 0.7 },                        tag = "DEBUG" },
    warning = { num = 2, color = { red = 0.9, green = 0.7, blue = 0.0 }, tag = "WARN" },
    error   = { num = 1, color = { red = 1.0, green = 0.3, blue = 0.3 }, tag = "ERROR" },
}

local NS_COLOR   = { red = 0.55, green = 0.55, blue = 0.6 }
local FILE_COLOR = { white = 0.45 }
local MESSAGE_FONT = { name = "Menlo", size = 16 }
local FILE_FONT    = { name = "Menlo", size = 12 }

-- One-off styled notice for the module's own lifecycle events.
local function printInit(message, isError)
    pcall(function()
        hs.console.printStyledtext(hs.styledtext.new("[HyperLogger] " .. message, {
            font = MESSAGE_FONT,
            color = isError and LEVEL_META.error.color or { white = 0.6 },
        }))
    end)
end

-- Compact caller location for the source suffix, when none was passed in.
local function callerLocation()
    -- Walk out past this function, emit(), and the level method to the caller.
    for i = 4, 8 do
        local info = debug.getinfo(i, "Sl")
        if not info then break end
        local src = info.short_src or ""
        if not src:match("HyperLogger%.lua$") then
            return src:gsub("^.*/", ""), info.currentline or 0
        end
    end
    return nil, nil
end

local function stringify(v)
    local t = type(v)
    if t == "string" then return v end
    if t == "nil" then return "[nil]" end
    if t == "number" or t == "boolean" then return tostring(v) end
    if t == "table" then
        local ok, s = pcall(hs.inspect, v)
        return ok and s or "[table]"
    end
    return "[" .. t .. "]"
end

-- Turn the variadic tail into (messageString, file, line).
-- Recognises a trailing (string-ending-in-.lua, number) pair as explicit
-- file/line metadata so the legacy (msg, "foo.lua", 0) callers stay clean.
local function assembleMessage(args, n)
    local file, line
    if n >= 2 and type(args[n]) == "number"
        and type(args[n - 1]) == "string" and args[n - 1]:match("%.lua$") then
        file, line = args[n - 1], args[n]
        n = n - 2
    end

    local parts = {}
    for i = 1, n do parts[i] = stringify(args[i]) end
    return table.concat(parts, " "), file, line
end

local function render(namespace, meta, msg, file, line)
    local ok = pcall(function()
        local st = hs.styledtext.new("[" .. namespace .. "] ",
            { font = MESSAGE_FONT, color = NS_COLOR })
        st = st .. hs.styledtext.new(msg, { font = MESSAGE_FONT, color = meta.color })
        if file then
            st = st .. hs.styledtext.new("  " .. file .. ":" .. tostring(line or 0),
                { font = FILE_FONT, color = FILE_COLOR })
        end
        hs.console.printStyledtext(st)
    end)
    if not ok then
        -- Never let a styling failure swallow the line.
        print(string.format("[%s] %s (%s) %s%s", meta.tag, namespace, os.date("%H:%M:%S"),
            msg, file and ("  " .. file .. ":" .. tostring(line or 0)) or ""))
    end
end

-- The single code path all four level methods funnel through. `first` is the
-- method's first positional arg, used to detect a colon (self) call.
local function emit(logger, levelName, first, ...)
    local meta = LEVEL_META[levelName]
    if logger._level < meta.num then return logger end -- gated out

    -- select('#') rather than #{...}: a trailing nil argument (log:i('x:', nil))
    -- makes the table length unreliable, and dropping it would hide exactly the
    -- nil the caller was trying to surface.
    local args, n
    if first == logger then          -- colon call: log:i(...)
        args, n = { ... }, select("#", ...)
    else                             -- dot call:  log.i(...)
        args, n = { first, ... }, select("#", ...) + 1
    end

    local msg, file, line = assembleMessage(args, n)
    if not file then file, line = callerLocation() end

    render(logger._namespace, meta, msg, file, line)
    return logger
end

-- The level new loggers inherit when none is passed. Changed by setGlobalLevel
-- so a single toggle raises/lowers verbosity across every namespace at once.
HyperLogger.globalLevel = DEFAULT_LOG_LEVEL

-- Canonical level ordering for UIs (quiet -> loud). Exported so the control
-- panel doesn't hardcode it. Matches the level methods, which top out at debug.
HyperLogger.LEVEL_CHOICES = { "error", "warning", "info", "debug" }

-- Persisted overrides, loaded from hs.settings by loadLevels(). `ns[namespace]`
-- is a per-logger override that beats the global default, both for existing
-- loggers and ones created later.
local persisted = { global = nil, ns = {} }

--- Create (or fetch the existing) logger for a namespace.
function HyperLogger.new(namespace, loglevel)
    namespace = tostring(namespace or "HammerspoonLogger")
    -- No explicit level: a saved per-namespace override wins over the global
    -- default, so a module registering its logger after loadLevels() still
    -- picks up the level the user chose for it.
    loglevel = tostring(loglevel or persisted.ns[namespace] or HyperLogger.globalLevel)

    local existing = loggers[namespace]
    if existing then
        if loglevel and LEVELS[loglevel] and loglevel ~= existing:getLogLevel() then
            existing:setLogLevel(loglevel)
        end
        return existing
    end

    -- A muted base hs.logger is kept purely as the level store, so any code
    -- reaching for ._baseLogger still finds a real logger object.
    local baseLogger = hs.logger.new(namespace, loglevel)
    baseLogger.setLogLevel("nothing") -- we do our own printing

    local logger = {
        _namespace = namespace,
        _baseLogger = baseLogger,
        _level = LEVELS[loglevel] or LEVELS[DEFAULT_LOG_LEVEL],
    }

    logger.i = function(first, ...) return emit(logger, "info", first, ...) end
    logger.d = function(first, ...) return emit(logger, "debug", first, ...) end
    logger.w = function(first, ...) return emit(logger, "warning", first, ...) end
    logger.e = function(first, ...) return emit(logger, "error", first, ...) end

    logger.setLogLevel = function(self, level)
        self = (self == logger) and self or logger
        local num = LEVELS[tostring(level)]
        if num then
            self._level = num
            pcall(function() self._baseLogger.setLogLevel(level) end)
        end
        return self
    end

    logger.getLogLevel = function(self)
        self = (self == logger) and self or logger
        for name, num in pairs(LEVELS) do
            if num == self._level then return name end
        end
        return "unknown"
    end

    loggers[namespace] = logger
    creationStacks[namespace] = debug.traceback("created " .. namespace, 2)
    return logger
end

function HyperLogger.getLoggers()
    local result = {}
    for namespace in pairs(loggers) do result[#result + 1] = namespace end
    return result
end

function HyperLogger.getCreationStack(namespace)
    return creationStacks[namespace]
end

function HyperLogger.resetLoggers()
    loggers = {}
    creationStacks = {}
    printInit("all loggers reset")
end

local SETTINGS_KEY = "HyperLogger.levels"

-- Persist the current global + per-namespace overrides to hs.settings
-- (machine-local; deliberately not a file in the auto-committing data/ submodule).
function HyperLogger.saveLevels()
    pcall(function()
        hs.settings.set(SETTINGS_KEY, {
            global = HyperLogger.globalLevel,
            ns = persisted.ns,
        })
    end)
end

-- Set the level on every existing logger and on the default for future ones.
-- A global set means "everything to X", so it supersedes and clears the
-- per-namespace overrides. `skipSave` is used by loadLevels to avoid writing
-- back the values it just read.
function HyperLogger.setGlobalLevel(level, skipSave)
    level = tostring(level)
    if not LEVELS[level] then
        printInit("ignored unknown log level: " .. level, true)
        return HyperLogger.globalLevel
    end
    HyperLogger.globalLevel = level
    persisted.ns = {}
    for _, lg in pairs(loggers) do lg:setLogLevel(level) end
    if not skipSave then HyperLogger.saveLevels() end
    return level
end

function HyperLogger.getGlobalLevel()
    return HyperLogger.globalLevel
end

-- Set a single namespace's level as an override on top of the global default,
-- and persist it. Applies immediately if that logger already exists.
function HyperLogger.setNamespaceLevel(namespace, level)
    namespace = tostring(namespace)
    level = tostring(level)
    if not LEVELS[level] then
        printInit("ignored unknown log level: " .. level, true)
        return
    end
    persisted.ns[namespace] = level
    local lg = loggers[namespace]
    if lg then lg:setLogLevel(level) end
    HyperLogger.saveLevels()
    return level
end

-- Snapshot of every live logger's level, sorted by namespace, for a UI.
function HyperLogger.getLevels()
    local out = {}
    for ns, lg in pairs(loggers) do
        out[#out + 1] = { ns = ns, level = lg:getLogLevel() }
    end
    table.sort(out, function(a, b) return a.ns:lower() < b.ns:lower() end)
    return out
end

-- Restore global + per-namespace levels saved by a previous session. Applies
-- the global to all existing loggers, then overlays the per-namespace overrides.
function HyperLogger.loadLevels()
    local saved = nil
    pcall(function() saved = hs.settings.get(SETTINGS_KEY) end)
    if type(saved) ~= "table" then return end

    if saved.global and LEVELS[saved.global] then
        HyperLogger.setGlobalLevel(saved.global, true) -- clears ns; skip re-save
    end
    if type(saved.ns) == "table" then
        for ns, level in pairs(saved.ns) do
            if LEVELS[level] then
                persisted.ns[ns] = level
                local lg = loggers[ns]
                if lg then lg:setLogLevel(level) end
            end
        end
    end
end

-- Reset everything to the info default and forget all overrides.
function HyperLogger.resetLevels()
    HyperLogger.setGlobalLevel("info")  -- clears persisted.ns and saves
    return "info"
end

--- Advance the global level one step round the cycle. Returns the new level.
--- Cycle runs quiet -> loud (LEVEL_CHOICES), wrapping back to error after debug.
function HyperLogger.cycleGlobalLevel()
    local cycle = HyperLogger.LEVEL_CHOICES
    local idx = 1
    for i, l in ipairs(cycle) do
        if l == HyperLogger.globalLevel then idx = i; break end
    end
    return HyperLogger.setGlobalLevel(cycle[(idx % #cycle) + 1])
end

return HyperLogger
