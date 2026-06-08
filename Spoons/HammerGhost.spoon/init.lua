--- === HammerGhost ===
---
--- EventGhost-like, event-driven automation GUI for Hammerspoon.
---
--- System events (app/window/USB/power, MQTT) flow onto a shared event bus;
--- triggers bound to those events run their child actions on a match.
---
--- Features:
--- * Event bus fed by app/window/USB/system-power/MQTT sources
--- * Triggers with EventGhost-style wildcard (*/?) event matching
--- * Action library + payload templating ({event.name}, {payload.app})
--- * Tree-based macro organization (folders, sequences, conditions)
--- * Visual webview editor with a live event log; JSON persistence
---
--- See README.md for the model, event names, and how to wire a macro.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "HammerGhost"
obj.version = "1.9"
obj.author = "Dan Edens"
obj.homepage = "https://github.com/MadTinker/DansHammerSpoon/tree/main/Spoons/HammerGhost.spoon"
obj.license = "MIT - https://opensource.org/licenses/MIT"

-- Load additional modules
-- local config = dofile(hs.spoons.resourcePath("scripts/config.lua"))
-- local ui = dofile(hs.spoons.resourcePath("scripts/ui.lua"))
-- local treeHelpers = dofile(hs.spoons.resourcePath("scripts/tree_helpers.lua"))
-- local action_editor = dofile(hs.spoons.resourcePath("scripts/action_editor.lua"))
-- local action_system = dofile(hs.spoons.resourcePath("scripts/action_system.lua"))
-- local sequence_editor = dofile(hs.spoons.resourcePath("scripts/sequence_editor.lua"))
-- local action_chooser = dofile(hs.spoons.resourcePath("scripts/action_chooser.lua"))
-- local condition_editor = dofile(hs.spoons.resourcePath("scripts/condition_editor.lua"))
-- local plugin_manager = dofile(hs.spoons.resourcePath("scripts/plugin_manager.lua"))
-- local xmlparser = dofile(hs.spoons.resourcePath("scripts/xmlparser.lua"))
local config = dofile(hs.spoons.resourcePath("scripts/config.lua"))
local ui = dofile(hs.spoons.resourcePath("scripts/ui.lua"))
local treeHelpers = dofile(hs.spoons.resourcePath("scripts/tree_helpers.lua"))
local action_editor = dofile(hs.spoons.resourcePath("scripts/action_editor.lua"))
local action_system = dofile(hs.spoons.resourcePath("scripts/action_system.lua"))
local sequence_editor = dofile(hs.spoons.resourcePath("scripts/sequence_editor.lua"))
local action_chooser = dofile(hs.spoons.resourcePath("scripts/action_chooser.lua"))
local condition_editor = dofile(hs.spoons.resourcePath("scripts/condition_editor.lua"))
local plugin_manager = dofile(hs.spoons.resourcePath("scripts/plugin_manager.lua"))
-- Reserved for future EventGhost-XML import (.egtree). Persistence is JSON now
-- (config.lua), so config never calls this -- it's kept wired for the EG-parity
-- import path, not for saving the tree.
local xmlparser = dofile(hs.spoons.resourcePath("scripts/xmlparser.lua"))
local control_panel = dofile(hs.spoons.resourcePath("scripts/control_panel.lua"))
local event_bus = dofile(hs.spoons.resourcePath("scripts/event_bus.lua"))
local event_sources = dofile(hs.spoons.resourcePath("scripts/event_sources.lua"))

-- Percent-decode a URL component. hs.urlevent has no unquote(); the JS side uses
-- encodeURIComponent (no form-style '+' for spaces), so we only decode %xx bytes.
local function urlDecode(s)
    if not s then return s end
    return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

-- Decode a URL-encoded JSON payload from the JS bridge. Returns the decoded
-- table, or nil after logging + alerting if the payload is malformed — callers
-- must bail on nil so a bad bridge message can't silently corrupt the tree.
local function safeDecodeArgs(args)
    local ok, decoded = pcall(function() return hs.json.decode(urlDecode(args)) end)
    if not ok or type(decoded) ~= "table" then
        local msg = "HammerGhost: failed to decode bridge payload"
        if _G.AppLogger then _G.AppLogger:e(msg, "init.lua", 0) end
        hs.alert.show(msg)
        return nil
    end
    return decoded
end

-- EventGhost-style event matching. A trigger's bound eventName may be a literal
-- (exact match, the common case) or a glob with '*' (any run, crosses dots) and
-- '?' (exactly one char). e.g. "App.Activated.*" matches any app activation;
-- "MQTT.status.*.claude.*" matches the device-mid MQTT topics.
local _globCache = {}  -- glob string -> compiled anchored Lua pattern
local function matchEvent(pattern, name)
    if not pattern or not name then return false end
    -- Fast path: no wildcards -> plain equality, no pattern compile.
    if not pattern:find("[*?]") then return pattern == name end
    local compiled = _globCache[pattern]
    if not compiled then
        -- Escape every Lua-pattern magic char EXCEPT our wildcards * and ?,
        -- then expand: * -> ".*", ? -> ".". Anchored so it matches the whole
        -- event name (an unanchored pattern would match too broadly).
        local p = pattern:gsub("[%^%$%(%)%%%.%[%]%+%-]", "%%%1")
        p = p:gsub("%*", ".*"):gsub("%?", ".")
        compiled = "^" .. p .. "$"
        _globCache[pattern] = compiled
    end
    return name:find(compiled) ~= nil
end

-- A trigger may bind MULTIPLE events, one per line (EventGhost lets a macro carry
-- several events; any of them fires it). Match if ANY non-blank line matches.
local function matchesAnyEvent(spec, name)
    if not spec or spec == "" then return false end
    for line in spec:gmatch("[^\r\n]+") do
        local pat = line:match("^%s*(.-)%s*$")  -- trim surrounding whitespace
        if pat ~= "" and matchEvent(pat, name) then
            return true
        end
    end
    return false
end

-- Initialize modules with dependencies
config.init({ xmlparser = xmlparser })

-- Internal variables
obj.window = nil
obj.toolbar = nil
obj.actionEditor = nil
obj.sequenceEditor = nil
obj.actionChooser = nil
obj.conditionEditor = nil
obj.configPath = hs.configdir .. "/hammerghost_config.json"
obj.macroTree = {}
obj.currentSelection = nil
obj.lastId = 0
obj.actionTypes = {}
obj.conditionTypes = {}

-- Initialize the spoon
function obj:init()
    self.logger = hs.logger.new("HammerGhost", "debug")
    self.logger:i("Initializing HammerGhost")

    -- Load plugins
    plugin_manager.loadPlugins()

    -- Load action types for the editor. The UI copies are handler-free so they
    -- survive hs.json.encode (a function value makes encode return nil, which
    -- left the Type dropdown empty). Execution still goes through
    -- action_system, which keeps the real defs with their handlers.
    self.actionTypes = action_system.getActionTypesForUI()
    self.conditionTypes = action_system.getConditionTypesForUI()

    -- Load saved macros if they exist
    self.macroTree, self.lastId = config.loadMacros(self.configPath)

    -- Check if the loaded configuration is empty or nil
    if not self.macroTree or #self.macroTree == 0 then
        -- Seed a fresh install with one runnable action: hit ▶️ and it opens the
        -- HammerGhost repo in the default browser. Doubles as the "this is what an
        -- action is" sample and proves the manual-run path end to end.
        self.macroTree = {
            {
                id = "1",
                name = "Open DansHammerSpoon repo",
                type = "action",
                actionType = "openURL",
                params = { url = "https://github.com/MadTinker/DansHammerSpoon.git" },
                expanded = false,
                children = {},
            }
        }
        self.lastId = 1
        config.saveMacros(self.configPath, self.macroTree)
    end

    -- Start the event subsystem: system watchers feed the bus, and a forwarder
    -- pushes each event into the live log panel when the window is open. The
    -- watcher runs regardless of window state; the bus's ring buffer back-fills
    -- the panel on open.
    -- Idempotent: hs.loadSpoon auto-calls init() AND the user's init.lua calls
    -- it explicitly, so this runs twice. event_sources.start() self-guards;
    -- drop any prior subscriptions before re-subscribing so events aren't logged
    -- or dispatched twice.
    event_sources.start()
    self.eventBus = event_bus  -- exposed for console inspection + triggers
    if self._logUnsub then self._logUnsub() end
    if self._dispatchUnsub then self._dispatchUnsub() end
    self._logUnsub = event_bus.subscribe(function(event)
        self:_pushLogEntry(event)
    end)
    self._dispatchUnsub = event_bus.subscribe(function(event)
        self:_dispatchEvent(event)
    end)

    -- Run any autostart items once. init() runs twice (loadSpoon + user init.lua),
    -- so guard with a flag -- otherwise autostart actions would fire twice.
    if not self._autostarted then
        self._autostarted = true
        self:_runAutostart()
    end

    return self
end

-- Run every item flagged autostart (EventGhost's Autostart macro), now that the
-- tree and action system are loaded. Disabled items are skipped.
function obj:_runAutostart()
    local function walk(items)
        for _, item in ipairs(items or {}) do
            if item.autostart and item.enabled ~= false then
                self:runItem(item.id)
            end
            if item.children then walk(item.children) end
        end
    end
    walk(self.macroTree)
end

-- Push a single bus event into the live log panel (no-op when hidden; the ring
-- buffer is rendered on next open instead).
function obj:_pushLogEntry(event)
    if not self.window or not self.window:isVisible() then return end
    local entry = hs.json.encode({
        seq = event.seq,
        time = os.date("%H:%M:%S", event.time),
        name = event.name,
        payload = event.payload or {},
    })
    -- A payload with a non-encodable value would make hs.json.encode return nil;
    -- skip rather than inject "appendLogEntry(nil)" (a JS error). The row just
    -- won't tail live; the ring buffer still renders it on next open.
    if not entry then return end
    self.window:evaluateJavaScript(string.format("window.appendLogEntry(%s)", entry))
end

-- Clear both the bus history and the panel's rows.
function obj:clearLog()
    event_bus.clear()
    if self.window and self.window:isVisible() then
        self.window:evaluateJavaScript("window.clearLogEntries()")
    end
end

-- Run a tree item. Actions execute, sequences run their gated steps, folders
-- run their children in order. Disabled items (enabled == false) are skipped, so
-- a greyed item never fires. Triggers are NOT runnable here: they are *fired* by
-- the event dispatcher, which runs their children directly — running a trigger
-- from a parent folder would bypass its event gate.
-- `event` is the bus event that triggered this run (nil for manual runs). It is
-- threaded to action/condition handlers as a second arg so payload-aware actions
-- can read event.payload; existing handlers that take only (params) ignore it.
function obj:executeItem(item, event)
    if not item or item.enabled == false then return end

    if item.type == "action" then
        action_system.executeAction(item, event)
    elseif item.type == "sequence" then
        -- Walk steps with a running "gate": a condition opens or closes the gate
        -- for every action that follows it, until the next condition. Actions run
        -- only while the gate is open (default open at start). Each step is
        -- {type, data}: a condition's type/params live inline in data; an action
        -- step REFERENCES a tree action node by data.id, so we resolve and run that
        -- node (it carries the real actionType/params).
        local gate = true
        for _, step in ipairs(item.steps or {}) do
            if step.enabled == false then
                -- Disabled step skipped (toggled off in the editor). A disabled
                -- condition leaves the gate as-is, so the actions after it run in
                -- whatever gate was already open -- same rule as _runChildren, and
                -- what the editor's gate visualization draws.
            else
                local data = step.data or {}
                if step.type == "condition" then
                    gate = action_system.executeCondition(
                        { conditionType = data.type, params = data.params }, event) and true or false
                elseif step.type == "action" and gate then
                    local node = data.id and treeHelpers.findItem(self.macroTree, data.id)
                    if node then self:executeItem(node, event) end
                end
            end
        end
    elseif item.type == "folder" then
        self:_runChildren(item.children, event)
    elseif item.type == "condition" then
        -- A condition gates its siblings (handled in _runChildren); running one on
        -- its own just reports whether it currently passes -- handy while building.
        local passed = action_system.executeCondition(item, event)
        hs.alert.show(string.format("%s: %s", item.name or "condition", passed and "TRUE" or "FALSE"))
    end
end

-- Run a list of child items with EventGhost-style condition gating: a condition
-- child opens/closes the gate for the actions that FOLLOW it (until the next
-- condition); the gate starts open. This is the same gate the sequence editor
-- applies to steps, but for the tree children of a trigger or folder -- so the
-- variable/app/time conditions work as flow control without needing a sequence.
-- Disabled children are skipped (and don't change the gate).
function obj:_runChildren(children, event)
    local gate = true
    for _, child in ipairs(children or {}) do
        if child.enabled == false then
            -- skipped; leaves the gate as-is
        elseif child.type == "condition" then
            gate = action_system.executeCondition(child, event) and true or false
        elseif gate then
            self:executeItem(child, event)
        end
    end
end

-- Run `fn` as a coroutine so a Wait/Delay action inside it can suspend the macro
-- (the delay action yields the number of seconds to wait) without blocking the
-- main thread. The driver resumes the coroutine after that delay via hs.timer.
-- Each macro run gets its own coroutine, so concurrent runs interleave
-- cooperatively rather than one stalling the others.
local function driveMacro(fn)
    local co = coroutine.create(fn)
    local function step()
        local ok, waitSecs = coroutine.resume(co)
        if not ok then
            -- waitSecs holds the error on failure. print() unconditionally so a
            -- macro error is visible in the Hammerspoon console even when the
            -- optional AppLogger isn't present -- this is the only diagnostic for
            -- the executor that runs on every matched event.
            print("[HammerGhost] macro run error: " .. tostring(waitSecs))
            if _G.AppLogger then
                _G.AppLogger:e("macro run error: " .. tostring(waitSecs), "init.lua", 0)
            end
            return
        end
        if coroutine.status(co) ~= "dead" then
            -- The coroutine yielded a delay (seconds); resume after it elapses.
            hs.timer.doAfter(tonumber(waitSecs) or 0, step)
        end
    end
    step()
end

-- Execute an item by id (legacy entry point). Routed through runItem so it shares
-- the coroutine driver (a Wait inside it must not run on the bare main thread).
function obj:executeAction(id)
    self:runItem(id)
end

-- Manual run from the UI (▶️ row button / "Run Selected"). Lets you test an item
-- without producing its real system event; the firing event is nil, so
-- payload-templated params ({payload.app}) resolve to "". A trigger isn't itself
-- runnable in executeItem (it's gated by the dispatcher), so a manual run on a
-- trigger means "fire what it would fire" -> run its children, mirroring
-- _dispatchEvent. Everything else runs directly. The walk runs in a coroutine so
-- a Wait/Delay action can suspend it.
function obj:runItem(id)
    local item = treeHelpers.findItem(self.macroTree, id)
    if not item then return end
    driveMacro(function()
        if item.type == "trigger" then
            self:_runChildren(item.children, nil)
        else
            self:executeItem(item, nil)
        end
    end)
end

-- Fire every enabled trigger whose bound eventName matches a fired bus event,
-- running that trigger's children in order. eventName is matched with EG-style
-- globbing (matchEvent): literals match exactly, '*'/'?' wildcards match broadly.
-- Each matched trigger's children run in their own coroutine so a Wait/Delay
-- suspends only that macro, not the dispatch loop or sibling triggers.
function obj:_dispatchEvent(event)
    -- A TriggerEvent action emits synchronously back through here, so a
    -- self-referential event name would recurse without bound (a hard main-thread
    -- hang, not EventGhost's queued re-entry). Cap the depth: turn a runaway loop
    -- into a logged stop instead of a frozen Hammerspoon.
    self._dispatchDepth = (self._dispatchDepth or 0) + 1
    if self._dispatchDepth > 20 then
        print("[HammerGhost] event dispatch too deep at '" .. tostring(event and event.name) ..
            "' -- aborting (likely a TriggerEvent feedback loop)")
        self._dispatchDepth = self._dispatchDepth - 1
        return
    end

    local function walk(items)
        for _, item in ipairs(items) do
            if item.type == "trigger"
                and item.enabled ~= false
                and matchesAnyEvent(item.eventName, event.name) then
                local children = item.children or {}
                driveMacro(function()
                    self:_runChildren(children, event)
                end)
            end
            if item.children then walk(item.children) end
        end
    end
    walk(self.macroTree)

    self._dispatchDepth = self._dispatchDepth - 1
end

-- Function to toggle the main window
function obj:toggle()
    if not self.window then
        ui.createMainWindow(self)
    elseif self.window:isVisible() then
        self.window:hide()
    else
        self.window:show()
    end
end

-- Function to show the Mad Tinker Dashboard (control panel for all spoons)
function obj:showControlPanel()
    control_panel.show(self)
end

-- Function to hide the control panel
function obj:hideControlPanel()
    control_panel.hide()
end

-- Function to toggle the control panel
function obj:toggleControlPanel()
    control_panel.toggle(self)
end

-- Function to refresh the control panel (push updated state)
function obj:refreshControlPanel()
    control_panel.refresh()
end

-- Bind hotkeys for the spoon
function obj:bindHotkeys(mapping)
    local spec = {
        toggle = function() self:toggle() end,
        showActionEditor = function() self:openActionEditor() end,
        controlPanel = function() self:toggleControlPanel() end,
    }
    hs.spoons.bindHotkeysToSpec(spec, mapping)
    return self
end

-- The editor windows are recreated on every open rather than cached. Their
-- contents are pushed by the page itself: on load each page navigates to a
-- hammerspoon:// "get..." URL and the handler answers with the data + prefill.
-- A cached window never re-fires that on-load handshake (DOMContentLoaded runs
-- once per page), and pushing right after show() races the page load (the JS
-- entry points aren't defined yet, so the push is silently dropped -> blank
-- form, and on Save an empty id takes the "create" branch, duplicating the node
-- instead of updating it). A fresh page each open dodges both problems.

-- The node currently being edited, read back by the get* handshake handlers to
-- prefill the form. nil means a fresh "add".
obj.editingAction = nil
obj.editingCondition = nil
obj.editingSequence = nil

-- Drop a previous editor window. pcall because the user may have closed it with
-- the title-bar button, leaving stale userdata that errors on :delete().
local function discard(win)
    if win then pcall(function() win:delete() end) end
end

function obj:openActionEditor(action)
    self.editingAction = action
    discard(self.actionEditor)
    self.actionEditor = action_editor.create(self)
    self.actionEditor:show()
end

function obj:openSequenceEditor(sequence)
    self.editingSequence = sequence
    discard(self.sequenceEditor)
    self.sequenceEditor = sequence_editor.create(self)
    self.sequenceEditor:show()
end

function obj:openActionChooser()
    discard(self.actionChooser)
    self.actionChooser = action_chooser.create(self)
    self.actionChooser:show()
end

function obj:openConditionEditor(condition)
    self.editingCondition = condition
    discard(self.conditionEditor)
    self.conditionEditor = condition_editor.create(self)
    self.conditionEditor:show()
end


-- Function to select an item
function obj:selectItem(id)
    self.currentSelection = treeHelpers.findItem(self.macroTree, id)
    ui.refresh(self)
    ui.showProperties(self, self.currentSelection)
end

-- Function to add a new folder
function obj:addFolder()
    local name = "New Folder"
    self:createMacroItem(name, "folder", self:getCurrentSelection())
    ui.refresh(self)
end

-- Function to add a new trigger (an event-bound container for actions)
function obj:addTrigger()
    local item = self:createMacroItem("New Trigger", "trigger", self:getCurrentSelection())
    self.currentSelection = item
    ui.refresh(self)
    ui.showProperties(self, item)
end

-- Function to add a new action
function obj:addAction()
    self:openActionEditor()
end

-- Add a sequence as a tree node (an ordered, condition-gated list of action
-- references), then open the editor to fill its steps. Created up front so
-- saveSequence has a node to write item.steps onto.
function obj:addSequence()
    local item = self:createMacroItem("New Sequence", "sequence", self:getCurrentSelection())
    self.currentSelection = item
    ui.refresh(self)
    self:openSequenceEditor(item)
end

-- Add a condition as a tree node (a gate for the actions that follow it among
-- its siblings). Created then opened in the editor to pick its type/params.
function obj:addCondition()
    local item = self:createMacroItem("New Condition", "condition", self:getCurrentSelection())
    self.currentSelection = item
    ui.refresh(self)
    self:openConditionEditor(item)
end

-- Add a child under a specific node, used by the tree's right-click "Add" items.
-- The add* methods nest into the current selection, so we point the selection at
-- the target first, then reuse them -- the new node lands inside the right-clicked
-- container (createMacroItem falls back to the top level if it isn't a container).
-- Unknown types are ignored.
function obj:addChildTo(id, itemType)
    local item = treeHelpers.findItem(self.macroTree, id)
    if item then
        self.currentSelection = item
    end
    if itemType == "folder" then
        self:addFolder()
    elseif itemType == "trigger" then
        self:addTrigger()
    elseif itemType == "action" then
        self:addAction()
    elseif itemType == "sequence" then
        self:addSequence()
    end
end

-- Function to create a new macro item
function obj:createMacroItem(name, type, parent, data)
    self.lastId = self.lastId + 1
    local item = {
        id = tostring(self.lastId),
        name = name,
        type = type,
        expanded = true,  -- new containers start expanded so added children are visible
        children = (type == "folder" or type == "sequence" or type == "trigger") and {} or nil,
    }
    -- Triggers carry the event name they fire on; empty until bound.
    if type == "trigger" then
        item.eventName = ""
    end
    if data then
        for k, v in pairs(data) do
            item[k] = v
        end
    end

    -- Only nest into the selection if it's a real container AND still reachable
    -- in the live tree (identity match, not just same id). A detached selection
    -- would swallow the new item into an orphan -> it never appears. Fall back
    -- to top level in that case.
    if parent and parent.children
        and treeHelpers.findItem(self.macroTree, parent.id) == parent then
        table.insert(parent.children, item)
    else
        table.insert(self.macroTree, item)
    end

    config.saveMacros(self.configPath, self.macroTree)
    return item
end

-- Function to get the current selection
function obj:getCurrentSelection()
    return self.currentSelection
end

-- Function to save configuration
function obj:saveConfig()
    config.saveMacros(self.configPath, self.macroTree)
    hs.alert.show("Configuration saved")
end

-- Function to reload configuration
function obj:reloadConfig()
    self.macroTree, self.lastId = config.loadMacros(self.configPath)
    -- The tree object was replaced; the old selection now points at a detached
    -- node. Drop it so Add/Save operate on the live tree.
    self.currentSelection = nil
    ui.clearProperties(self)
    ui.refresh(self)
    hs.alert.show("Configuration reloaded")
end

-- Import an EventGhost tree.xml. EventGhost's tree is <EventGhost> containing
-- <Folder>/<Macro>, where a <Macro> holds <Event>s (the trigger) and <Action>s.
-- We map Folder->folder and Macro->trigger (its Events become the trigger's
-- newline event list, its Actions become child action nodes). EG actions are
-- plugin-specific and can't run here, so each imports as a labeled placeholder
-- ("[EG] <name>") for you to re-wire -- the STRUCTURE and event bindings carry
-- over, which is what cross-tool import realistically means. Plugin/Autostart
-- sections are skipped. Imported items are appended to the current tree.
function obj:importMacros(xmlString)
    if not xmlString or xmlString == "" then return end
    -- The lightweight xmlparser can't handle the XML prolog, comments, or CDATA
    -- (EG wraps action config in CDATA); strip them -- we only read structure.
    local clean = xmlString
        :gsub("<%?.-%?>", "")
        :gsub("<!%[CDATA%[.-%]%]>", "")
        :gsub("<!%-%-.-%-%->", "")

    local ok, roots = pcall(xmlparser.parse, clean)
    if not ok or type(roots) ~= "table" then
        hs.alert.show("Import failed: couldn't parse XML")
        return
    end

    local function mapAction(el)
        local nm = (el.attributes and (el.attributes.Name or el.attributes.GUID)) or "Action"
        return {
            name = "[EG] " .. nm,
            type = "action",
            actionType = "alert",
            params = { text = "Imported from EventGhost: " .. nm .. " (re-configure)" },
        }
    end

    local function mapNode(el)
        local name = el.attributes and el.attributes.Name
        if el.tag == "Folder" then
            local folder = { name = name or "Folder", type = "folder", expanded = true, children = {} }
            for _, child in ipairs(el.children or {}) do
                local mapped = mapNode(child)
                if mapped then table.insert(folder.children, mapped) end
            end
            return folder
        elseif el.tag == "Macro" then
            local trigger = { name = name or "Macro", type = "trigger", expanded = true, children = {}, eventName = "" }
            local events = {}
            for _, child in ipairs(el.children or {}) do
                if child.tag == "Event" then
                    local en = child.attributes and child.attributes.Name
                    if en then events[#events + 1] = en end
                elseif child.tag == "Action" then
                    table.insert(trigger.children, mapAction(child))
                end
            end
            trigger.eventName = table.concat(events, "\n")
            return trigger
        elseif el.tag == "Action" then
            return mapAction(el)
        end
        return nil  -- Plugin, Autostart, unknown: skip
    end

    -- Descend into the <EventGhost> root if present; otherwise map top-level nodes.
    local imported = {}
    local function consider(el)
        local mapped = mapNode(el)
        if mapped then table.insert(imported, mapped) end
    end
    for _, el in ipairs(roots) do
        if el.tag == "EventGhost" then
            for _, child in ipairs(el.children or {}) do consider(child) end
        else
            consider(el)
        end
    end

    if #imported == 0 then
        hs.alert.show("Import: no Folder/Macro/Action nodes found")
        return
    end

    -- Assign fresh ids across the imported subtree so they don't collide with the
    -- existing tree (ids are the highest-seen + 1, tracked in self.lastId).
    local function assignIds(node)
        self.lastId = self.lastId + 1
        node.id = tostring(self.lastId)
        for _, c in ipairs(node.children or {}) do assignIds(c) end
    end
    for _, node in ipairs(imported) do
        assignIds(node)
        table.insert(self.macroTree, node)
    end

    self:saveConfig()
    ui.refresh(self)
    hs.alert.show(string.format("Imported %d top-level item(s) from EventGhost", #imported))
end

-- Function to edit item
function obj:editItem(id)
    local item = treeHelpers.findItem(self.macroTree, id)
    if item then
        if item.type == "action" then
            self:openActionEditor(item)
        elseif item.type == "sequence" then
            self:openSequenceEditor(item)
        elseif item.type == "condition" then
            self:openConditionEditor(item)
        else
            self.currentSelection = item
            ui.showProperties(self, item)
        end
    end
end

-- Function to delete item
function obj:deleteItem(id)
    local function removeItem(items, targetId)
        for i, item in ipairs(items) do
            if item.id == targetId then
                table.remove(items, i)
                return true
            end
            if item.children and removeItem(item.children, targetId) then
                return true
            end
        end
        return false
    end

    if removeItem(self.macroTree, id) then
        -- Removing the node must not leave currentSelection dangling: a later
        -- Add would insert into the orphan and Save would silently miss it.
        if self.currentSelection and not treeHelpers.findItem(self.macroTree, self.currentSelection.id) then
            self.currentSelection = nil
            ui.clearProperties(self)
        end
        self:saveConfig()
        ui.refresh(self)
    end
end

-- Function to toggle an item's enabled/disabled state
function obj:toggleItem(id)
    local item = treeHelpers.findItem(self.macroTree, id)
    if not item then return end

    -- Items are enabled by default; absence of the flag means enabled
    if item.enabled == nil then
        item.enabled = true
    end
    item.enabled = not item.enabled

    self:saveConfig()        -- persist state change
    ui.refresh(self)         -- update visual state

    hs.alert.show(string.format("%s %s", item.name, item.enabled and "enabled" or "disabled"))
    return item.enabled
end

-- --- Plugin API ------------------------------------------------------------
-- Stable surface for plugin action/condition handlers (plugins/*.lua). Handlers
-- reach the live spoon through the `spoon.HammerGhost` global; these wrap the
-- common operations so plugins don't poke at internals.

-- Return the first tree item whose name matches (depth-first), or nil. Lets
-- flow-control actions address items by their human name instead of id.
function obj:findItemByName(name)
    if not name then return nil end
    local function walk(items)
        for _, item in ipairs(items) do
            if item.name == name then return item end
            if item.children then
                local found = walk(item.children)
                if found then return found end
            end
        end
        return nil
    end
    return walk(self.macroTree)
end

-- Set an item's enabled state by id or name, then persist + refresh. Used by the
-- EnableItem / DisableItem flow actions.
function obj:setItemEnabled(idOrName, enabled)
    local item = treeHelpers.findItem(self.macroTree, idOrName) or self:findItemByName(idOrName)
    if not item then return false end
    item.enabled = enabled and true or false
    self:saveConfig()
    ui.refresh(self)
    return true
end

-- Emit a named event on the bus (so a TriggerEvent action can fire a custom
-- event that other triggers match). payload defaults to an empty table.
function obj:emitEvent(name, payload)
    if not name or name == "" then return end
    event_bus.emit(name, payload or {})
end

-- Function to expand/collapse a folder or sequence in the tree.
function obj:toggleExpand(id)
    local item = treeHelpers.findItem(self.macroTree, id)
    if not item then return end

    -- expanded defaults to true (nil/true render expanded); toggle flips it.
    if item.expanded == nil then
        item.expanded = true
    end
    item.expanded = not item.expanded

    self:saveConfig()  -- persist collapse state across reloads
    ui.refresh(self)
    return item.expanded
end

-- Function to move/reorder an item in the tree via drag and drop.
-- position is "before" | "after" (sibling of target) or "inside" (child of target).
function obj:moveItem(sourceId, targetId, position)
    if not sourceId or not targetId or sourceId == targetId then return end

    -- Locate an item by id, returning the item, its containing list, and index.
    local function locate(items, id)
        for i, item in ipairs(items) do
            if item.id == id then return item, items, i end
            if item.children then
                local it, list, idx = locate(item.children, id)
                if it then return it, list, idx end
            end
        end
        return nil
    end

    -- True if `id` is `node` itself or any descendant of it (cycle guard).
    local function containsId(node, id)
        if node.id == id then return true end
        if node.children then
            for _, child in ipairs(node.children) do
                if containsId(child, id) then return true end
            end
        end
        return false
    end

    local source, srcList, srcIdx = locate(self.macroTree, sourceId)
    if not source then return end

    -- Never drop a node into itself or one of its own descendants.
    if containsId(source, targetId) then return end

    -- Detach source from its current parent before re-inserting (indices into
    -- the target list are computed after this removal so they stay valid).
    table.remove(srcList, srcIdx)

    if position == "inside" then
        local target = locate(self.macroTree, targetId)
        if target then
            target.children = target.children or {}
            table.insert(target.children, source)
        else
            table.insert(self.macroTree, source) -- target vanished; keep at root
        end
    else
        local _, tgtList, tgtIdx = locate(self.macroTree, targetId)
        if tgtList then
            local insertIdx = (position == "after") and (tgtIdx + 1) or tgtIdx
            table.insert(tgtList, insertIdx, source)
        else
            table.insert(self.macroTree, source)
        end
    end

    self:saveConfig()
    ui.refresh(self)
end

-- Function to save properties
function obj:saveProperties(data)
    local item = treeHelpers.findItem(self.macroTree, data.id)
    if not item then
        -- The edited item is no longer in the tree (e.g. it was a stale/detached
        -- selection). Don't silently swallow the Save -- tell the user why their
        -- edit didn't stick instead of leaving "0 items" with no feedback.
        hs.alert.show("Couldn't save: that item is no longer in the tree. Re-add it.")
        if _G.AppLogger then
            _G.AppLogger:w("saveProperties: id " .. tostring(data.id) .. " not found in tree", "init.lua", 0)
        end
        ui.clearProperties(self)
        return
    end
    item.name = data.name
    -- Triggers carry an event name; persist it when the form supplied one.
    if item.type == "trigger" and data.eventName ~= nil then
        item.eventName = data.eventName
    end
    -- Autostart flag (run once at load); the checkbox always reports a boolean.
    if data.autostart ~= nil then
        item.autostart = data.autostart and true or false
    end
    self:saveConfig()
    ui.refresh(self)
    ui.clearProperties(self)
end

-- Bind a logged event name to the currently selected trigger (click a log row).
-- Closes the discovery->bind loop: see the event fire, click it onto a trigger.
function obj:bindEvent(eventName)
    local item = self.currentSelection
    if not item or item.type ~= "trigger" then
        hs.alert.show("Select a trigger first, then click an event to bind it")
        return
    end
    -- A trigger can hold several events (one per line); clicking a log row ADDS
    -- the event rather than replacing, so you can bind a few in a row. Skip if
    -- it's already bound.
    local existing = item.eventName or ""
    local already = false
    for line in existing:gmatch("[^\r\n]+") do
        if line:match("^%s*(.-)%s*$") == eventName then already = true end
    end
    if not already then
        item.eventName = (existing ~= "" and (existing .. "\n") or "") .. eventName
    end
    self:saveConfig()
    ui.refresh(self)
    ui.showProperties(self, item)
    hs.alert.show(string.format("Bound %s -> %s", item.name, eventName))
end

function obj:handleURL(url)
    ui.handleURL(self, url)
end

function obj:handleActionEditorURL(url)
    local cmd, args = url:match("hammerspoon://([^?]+)%??(.*)")
    if not cmd then return end

    if cmd == "getActionTypes" then
        -- Page-load handshake: fill the type dropdown, then prefill if editing.
        -- Back-to-back evaluateJavaScript calls run in order, so types land
        -- before populateEditor reads them.
        self.actionEditor:evaluateJavaScript(
            string.format("populateActionTypes(%s)", hs.json.encode(self.actionTypes)))
        if self.editingAction then
            self.actionEditor:evaluateJavaScript(
                string.format("populateEditor(%s)", hs.json.encode(self.editingAction)))
        end
    elseif cmd == "saveAction" then
        local actionData = safeDecodeArgs(args)
        if not actionData then return end
        if actionData.id and actionData.id ~= "" then
            -- Update existing action
            local item = treeHelpers.findItem(self.macroTree, actionData.id)
            if item then
                item.name = actionData.name
                item.actionType = actionData.type
                item.params = actionData.params
            end
        else
            -- Create new action
            self:createMacroItem(actionData.name, "action", self.currentSelection, {
                actionType = actionData.type,
                params = actionData.params
            })
        end
        self:saveConfig()
        ui.refresh(self)
        self.actionEditor:hide()
    elseif cmd == "cancelActionEditor" then
        self.actionEditor:hide()
    end
end

function obj:handleSequenceEditorURL(url)
    local cmd, args = url:match("hammerspoon://([^?]+)%??(.*)")
    if not cmd then return end

    if cmd == "getSequenceData" then
        -- Page-load handshake. editingSequence is the node passed to the editor
        -- (nil for a fresh add); {} gives the page an empty step list. Push the
        -- condition-type catalog first so renderSteps can show friendly names;
        -- back-to-back evaluateJavaScript calls run in order, so it lands before
        -- populateEditor reads it.
        self.sequenceEditor:evaluateJavaScript(
            string.format("setConditionTypes(%s)", hs.json.encode(self.conditionTypes or {})))
        local js = string.format("populateEditor(%s)", hs.json.encode(self.editingSequence or {}))
        self.sequenceEditor:evaluateJavaScript(js)
    elseif cmd == "selectActionForSequence" then
        self:openActionChooser()
    elseif cmd == "addConditionToSequence" then
        self:openConditionEditor()
    elseif cmd == "editActionStep" then
        -- An action step only references a tree action node (data.id); its params
        -- live on that node. Edit the node directly: the action editor saves back
        -- to it (saveAction matches by id), so every reference picks up the change.
        local data = safeDecodeArgs(args)
        local node = data and data.id and treeHelpers.findItem(self.macroTree, data.id)
        if node and node.type == "action" then
            self:openActionEditor(node)
        else
            hs.alert.show("This step's action no longer exists")
        end
    elseif cmd == "editConditionStep" then
        -- Condition steps carry their params inline in data; reopen the condition
        -- editor prefilled. Map data.type -> conditionType (the field applyCondition
        -- reads) and leave id unset so saveCondition routes the result back to the
        -- sequence editor (replacing the step) rather than to a tree node.
        local data = safeDecodeArgs(args)
        if data then
            self:openConditionEditor({ conditionType = data.type, params = data.params })
        end
    elseif cmd == "saveSequence" then
        local sequenceData = safeDecodeArgs(args)
        if not sequenceData then return end
        local item = self.currentSelection
        if item and item.type == "sequence" then
            item.steps = sequenceData.steps
            self:saveConfig()
            ui.refresh(self)
            self.sequenceEditor:hide()
        end
    elseif cmd == "cancelSequenceEditor" then
        self.sequenceEditor:hide()
    end
end

function obj:handleActionChooserURL(url)
    local cmd, args = url:match("hammerspoon://([^?]+)%??(.*)")
    if not cmd then return end

    if cmd == "getActions" then
        local actions = {}
        local function findActions(items)
            for _, item in ipairs(items) do
                if item.type == "action" then
                    table.insert(actions, {id = item.id, name = item.name})
                end
                if item.children then
                    findActions(item.children)
                end
            end
        end
        findActions(self.macroTree)
        local js = string.format("populateActions(%s)", hs.json.encode(actions))
        self.actionChooser:evaluateJavaScript(js)
    elseif cmd == "actionSelected" then
        local action = safeDecodeArgs(args)
        if not action then return end
        local js = string.format("addStepToSequence(%s)", hs.json.encode({type="action", data=action}))
        self.sequenceEditor:evaluateJavaScript(js)
        self.actionChooser:hide()
    elseif cmd == "cancelActionChooser" then
        if self.actionChooser then self.actionChooser:hide() end
    end
end

function obj:handleConditionEditorURL(url)
    local cmd, args = url:match("hammerspoon://([^?]+)%??(.*)")
    if not cmd then return end

    if cmd == "getConditionTypes" then
        -- Page-load handshake: fill the type dropdown, then prefill if editing.
        self.conditionEditor:evaluateJavaScript(
            string.format("populateConditionTypes(%s)", hs.json.encode(self.conditionTypes)))
        if self.editingCondition then
            self.conditionEditor:evaluateJavaScript(
                string.format("populateEditor(%s)", hs.json.encode(self.editingCondition)))
        end
    elseif cmd == "saveCondition" then
        local conditionData = safeDecodeArgs(args)
        if not conditionData then return end
        -- Two contexts: editing a condition NODE in the tree updates it; otherwise
        -- (picked from the sequence editor's Add Condition) hand it to the sequence
        -- editor as a step. The sequence editor may not be open -- guard it.
        local node = (conditionData.id and conditionData.id ~= "")
            and treeHelpers.findItem(self.macroTree, conditionData.id) or nil
        if node and node.type == "condition" then
            node.conditionType = conditionData.type
            node.params = conditionData.params
            -- The condition editor has no name field, so name the node after its
            -- type's friendly label ("Variable Equals") instead of leaving every
            -- condition reading "New Condition" in the tree.
            local def = self.conditionTypes[conditionData.type]
            node.name = (def and def.name) or node.name
            self:saveConfig()
            ui.refresh(self)
        elseif self.sequenceEditor then
            local js = string.format("addStepToSequence(%s)", hs.json.encode({type="condition", data=conditionData}))
            self.sequenceEditor:evaluateJavaScript(js)
        end
        if self.conditionEditor then self.conditionEditor:hide() end
    elseif cmd == "cancelConditionEditor" then
        self.conditionEditor:hide()
    end
end


-- Return the spoon object
return obj
