--- === HammerGhost ===
---
--- EventGhost-like macro editor for Hammerspoon
---
--- Features:
--- * Tree-based macro organization
--- * Visual macro editor
--- * Support for actions, sequences, and folders
--- * Dark theme matching EventGhost
---
--- Download: [https://github.com/Hammerspoon/Spoons/raw/master/Spoons/HammerGhost.spoon.zip](https://github.com/Hammerspoon/Spoons/raw/master/Spoons/HammerGhost.spoon.zip)

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
local xmlparser = dofile(hs.spoons.resourcePath("scripts/xmlparser.lua"))
local control_panel = dofile(hs.spoons.resourcePath("scripts/control_panel.lua"))

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

-- Initialize modules with dependencies
config.init({ xmlparser = xmlparser })

-- Internal variables
obj.window = nil
obj.toolbar = nil
obj.actionEditor = nil
obj.sequenceEditor = nil
obj.actionChooser = nil
obj.conditionEditor = nil
obj.configPath = hs.configdir .. "/hammerghost_config.xml"
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

    -- Load action types
    self.actionTypes = action_system.getActionTypes()
    self.conditionTypes = action_system.getConditionTypes()

    -- Load saved macros if they exist
    self.macroTree, self.lastId = config.loadMacros(self.configPath)

    -- Check if the loaded configuration is empty or nil
    if not self.macroTree or #self.macroTree == 0 then
        -- Set up a default configuration
        self.macroTree = {
            {
                id = "1",
                name = "Default Macro",
                type = "action",
                actionType = "alert",
                params = { text = "Default Action Triggered" },
                expanded = false,
                children = {},
            }
        }
        self.lastId = 1
        config.saveMacros(self.configPath, self.macroTree)
    end

    return self
end

-- Function to execute an action
function obj:executeAction(id)
    local item = treeHelpers.findItem(self.macroTree, id)
    if item then
        if item.type == "action" then
            action_system.executeAction(item)
        elseif item.type == "sequence" then
            -- Walk steps with a running "gate": a condition opens or closes the
            -- gate for every action that follows it, until the next condition.
            -- Actions run only while the gate is open (default open at start).
            -- Steps are executed directly; findItem only walks .children, not
            -- .steps, so an id round-trip would never resolve a step.
            local gate = true
            for _, step in ipairs(item.steps) do
                if step.type == "condition" then
                    gate = action_system.executeCondition(step) and true or false
                elseif step.type == "action" and gate then
                    action_system.executeAction(step)
                end
            end
        end
    end
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

function obj:openActionEditor(action)
    if not self.actionEditor then
        self.actionEditor = action_editor.create(self)
    end
    self.actionEditor:show()
    if action then
        local js = string.format("populateEditor(%s)", hs.json.encode(action))
        self.actionEditor:evaluateJavaScript(js)
    end
end

function obj:openSequenceEditor(sequence)
    if not self.sequenceEditor then
        self.sequenceEditor = sequence_editor.create(self)
    end
    self.sequenceEditor:show()
    if sequence then
        local js = string.format("populateEditor(%s)", hs.json.encode(sequence))
        self.sequenceEditor:evaluateJavaScript(js)
    end
end

function obj:openActionChooser()
    if not self.actionChooser then
        self.actionChooser = action_chooser.create(self)
    end
    self.actionChooser:show()
end

function obj:openConditionEditor(condition)
    if not self.conditionEditor then
        self.conditionEditor = condition_editor.create(self)
    end
    self.conditionEditor:show()
    if condition then
        local js = string.format("populateEditor(%s)", hs.json.encode(condition))
        self.conditionEditor:evaluateJavaScript(js)
    end
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
        children = (type == "folder" or type == "sequence") and {} or nil,
    }
    if data then
        for k, v in pairs(data) do
            item[k] = v
        end
    end

    if parent and parent.children then
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
    if item then
        item.name = data.name
        self:saveConfig()
        ui.refresh(self)
        ui.clearProperties(self)
    end
end

function obj:handleURL(url)
    ui.handleURL(self, url)
end

function obj:handleActionEditorURL(url)
    local cmd, args = url:match("hammerspoon://([^?]+)%??(.*)")
    if not cmd then return end

    if cmd == "getActionTypes" then
        local js = string.format("populateActionTypes(%s)", hs.json.encode(self.actionTypes))
        self.actionEditor:evaluateJavaScript(js)
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
        local js = string.format("populateEditor(%s)", hs.json.encode(self.currentSelection))
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
        local js = string.format("populateConditionTypes(%s)", hs.json.encode(self.conditionTypes))
        self.conditionEditor:evaluateJavaScript(js)
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
