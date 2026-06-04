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
obj.homepage = "https://github.com/Hammerspoon/Spoons"
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

    return self
end

-- Push a single bus event into the live log panel (no-op when hidden; the ring
-- buffer is rendered on next open instead).
function obj:_pushLogEntry(event)
    if not self.window or not self.window:isVisible() then return end
    local payload = hs.json.encode({
        seq = event.seq,
        time = os.date("%H:%M:%S", event.time),
        name = event.name,
    })
    self.window:evaluateJavaScript(string.format("window.appendLogEntry(%s)", payload))
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
        -- Walk steps with a running "gate": a condition opens or closes the
        -- gate for every action that follows it, until the next condition.
        -- Actions run only while the gate is open (default open at start).
        -- Steps are executed directly; findItem only walks .children, not
        -- .steps, so an id round-trip would never resolve a step.
        local gate = true
        for _, step in ipairs(item.steps or {}) do
            if step.type == "condition" then
                gate = action_system.executeCondition(step, event) and true or false
            elseif step.type == "action" and gate then
                action_system.executeAction(step, event)
            end
        end
    elseif item.type == "folder" then
        for _, child in ipairs(item.children or {}) do
            self:executeItem(child, event)
        end
    end
end

-- Execute an item by id (e.g. a future "run" button). Triggers fire via events.
function obj:executeAction(id)
    self:executeItem(treeHelpers.findItem(self.macroTree, id))
end

-- Manual run from the UI (▶️ row button / "Run Selected"). Lets you test an item
-- without producing its real system event; the firing event is nil, so
-- payload-templated params ({payload.app}) resolve to "". A trigger isn't itself
-- runnable in executeItem (it's gated by the dispatcher), so a manual run on a
-- trigger means "fire what it would fire" -> run its children, mirroring
-- _dispatchEvent. Everything else runs directly.
function obj:runItem(id)
    local item = treeHelpers.findItem(self.macroTree, id)
    if not item then return end
    if item.type == "trigger" then
        for _, child in ipairs(item.children or {}) do
            self:executeItem(child, nil)
        end
    else
        self:executeItem(item, nil)
    end
end

-- Fire every enabled trigger whose bound eventName matches a fired bus event,
-- running that trigger's children in order. eventName is matched with EG-style
-- globbing (matchEvent): literals match exactly, '*'/'?' wildcards match broadly.
function obj:_dispatchEvent(event)
    local function walk(items)
        for _, item in ipairs(items) do
            if item.type == "trigger"
                and item.enabled ~= false
                and matchEvent(item.eventName, event.name) then
                for _, child in ipairs(item.children or {}) do
                    self:executeItem(child, event)
                end
            end
            if item.children then walk(item.children) end
        end
    end
    walk(self.macroTree)
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

-- Function to add a sequence
function obj:addSequence()
    self:openSequenceEditor()
end

function obj:addCondition()
    self:openConditionEditor()
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
    item.eventName = eventName
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
        -- (nil for a fresh add); {} gives the page an empty step list.
        local js = string.format("populateEditor(%s)", hs.json.encode(self.editingSequence or {}))
        self.sequenceEditor:evaluateJavaScript(js)
    elseif cmd == "selectActionForSequence" then
        self:openActionChooser()
    elseif cmd == "addConditionToSequence" then
        self:openConditionEditor()
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
        local js = string.format("addStepToSequence(%s)", hs.json.encode({type="condition", data=conditionData}))
        self.sequenceEditor:evaluateJavaScript(js)
        self.conditionEditor:hide()
    elseif cmd == "cancelConditionEditor" then
        self.conditionEditor:hide()
    end
end


-- Return the spoon object
return obj
