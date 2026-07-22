---@diagnostic disable: lowercase-global, undefined-global
-- HotkeyManager.lua
-- Module for managing and displaying hotkeys dynamically

local HyperLogger = require('HyperLogger')
local log = HyperLogger.new()

local HotkeyManager = {}

-- Store all hotkey bindings
HotkeyManager.bindings = {
    hammer = {},
    hyper = {},
    other = {}
}

-- Constants for modifiers
HotkeyManager.MODIFIERS = {
    HAMMER = "hammer",
    HYPER = "hyper",
    OTHER = "other"
}

-- Store display window state
HotkeyManager.displayWindows = {
    hammer = nil,
    hyper = nil,
    other = nil
}

-- Default configuration
HotkeyManager.config = {
    -- Display settings
    width = 800,           -- Width of the hotkey display
    height = 600,          -- Height of the hotkey display
    cornerRadius = 10,     -- Corner radius for the hotkey display
    font = "Menlo",        -- Font for the hotkey display
    fontSize = 14,         -- Font size for the hotkey display
    fadeInDuration = 0.3,  -- Duration of the fade in animation
    fadeOutDuration = 0.3, -- Duration of the fade out animation
    
    -- Display mode: "chooser" for searchable menu, "alert" for spread-out display
    displayMode = "chooser",

    -- Alert settings
    alertDuration = 7,                            -- Duration in seconds to show the hotkey alert
    alertFontSize = 16,                           -- Font size for the alert text
    alertTextColor = { 1, 1, 1, 1 },              -- White text
    alertBackgroundColor = { 0.1, 0.1, 0.1, 0.85 }, -- Dark background with transparency

    -- Category colors for the hotkey display
    categoryColors = {
        ["Window Management"] = { 0.4, 0.7, 0.9 },
        ["Applications"] = { 0.9, 0.5, 0.5 },
        ["Files"] = { 0.5, 0.9, 0.6 },
        ["UI & Display"] = { 0.8, 0.7, 0.3 },
        ["System"] = { 0.9, 0.5, 0.9 },
        ["Other"] = { 0.7, 0.7, 0.7 }
    }
}

-- Helper function to check if a table contains a value
local function tableContains(tbl, element)
    -- Safety check to ensure we're working with a table
    if type(tbl) ~= "table" then
        log:e("tableContains called with non-table: " .. type(tbl))
        return false
    end
    for _, value in pairs(tbl) do
        if value == element then
            return true
        end
    end
    return false
end

-- Compact modifier glyphs, shown in the combined list so an identical key in
-- both modifier layers (e.g. hammer+Space vs hyper+Space) stays distinguishable.
HotkeyManager.MODIFIER_GLYPHS = {
    hammer = "⌘⌃⌥",
    hyper  = "⌘⇧⌃⌥",
    other  = "•",
}

-- Assign a binding to a display category from its description. Shared by both
-- the chooser and the alert renderers so they never drift apart.
local function categorizeBinding(description)
    description = description or ""
    if description:match("[Ww]indow") or description:match("[Ll]ayout") or
        description:match("[Ss]creen") or description:match("[Ss]huffle") or
        description:match("[Mm]ove") or description:match("[Pp]osition") then
        return "Window Management"
    elseif description:match("[Oo]pen") or description:match("[Ll]aunch") or
        description:match("App") then
        return "Applications"
    elseif description:match("[Ff]ile") or description:match("[Ff]older") or
        description:match("[Ii]mage") or description:match("[Mm]enu") then
        return "Files"
    elseif description:match("[Ss]how") or description:match("[Tt]oggle") or
        description:match("[Ll]ist") or description:match("[Hh]otkey") then
        return "UI & Display"
    elseif description:match("[Ff]unction") or description:match("[Rr]eload") or
        description:match("[Cc]onsole") then
        return "System"
    end
    return "Other"
end

-- Register a hotkey binding
function HotkeyManager.registerBinding(modifiers, key, callback, description)
    local modType = nil

    -- Ensure modifiers is a table
    if type(modifiers) ~= "table" then
        -- Convert single string modifiers to a table
        log:w("Non-table modifiers passed to registerBinding: " .. tostring(modifiers))
        if type(modifiers) == "string" then
            modifiers = { modifiers }
        else
            modType = "other"
        end
    end

    -- Now we ensure modifiers is a table, determine the type
    if type(modifiers) == "table" then
        -- Determine if this is a hammer or hyper binding by checking for presence of modifiers
        -- regardless of their order
        if #modifiers == 3 and
            tableContains(modifiers, "cmd") and
            tableContains(modifiers, "ctrl") and
            tableContains(modifiers, "alt") then
            modType = HotkeyManager.MODIFIERS.HAMMER
        elseif #modifiers == 4 and
            tableContains(modifiers, "cmd") and
            tableContains(modifiers, "shift") and
            tableContains(modifiers, "ctrl") and
            tableContains(modifiers, "alt") then
            modType = HotkeyManager.MODIFIERS.HYPER
        else
            modType = "other" -- Store all other combos in 'other'
        end
    else
        modType = "other"
    end

    -- Extract function name for description if not provided
    if not description then
        description = "Unknown action"

        -- Try different methods to get a reasonable description
        local info = debug.getinfo(callback)
        if info.name and info.name ~= "" then
            description = info.name:gsub("^.*_", "")
        else
            -- Try to extract from function body if we can
            local success, funcStr = pcall(string.dump, callback)
            if success and funcStr then
                -- Look for common patterns like Manager.functionName()
                local match = string.match(funcStr, "([%w_]+Manager)%.[a-zA-Z_]+")
                if match then
                    description = match:gsub("Manager", "") .. " action"
                end
            end

            -- If we still don't have a good description, check for common patterns in the function
            if description == "Unknown action" then
                local success, funcType = pcall(function()
                    if string.match(tostring(callback), "WindowManager") then
                        return "Window action"
                    elseif string.match(tostring(callback), "AppManager") then
                        return "App action"
                    elseif string.match(tostring(callback), "FileManager") then
                        return "File action"
                    end
                    return "Unknown action"
                end)

                if success and funcType ~= "Unknown action" then
                    description = funcType
                end
            end
        end
    end

    -- Check if the function is a temp function
    local isTempFunction = false
    if description:match("tempFunction") then
        isTempFunction = true
    end

    -- Store the binding
    table.insert(HotkeyManager.bindings[modType], {
        key = key,
        description = description,
        isTemp = isTempFunction,
        callback = callback
    })

    -- Sort bindings by key
    table.sort(HotkeyManager.bindings[modType], function(a, b)
        return a.key < b.key
    end)

    return true
end

-- Normalize a modType argument (a single string or an array of strings) into a
-- validated, de-duplicated list of known modifier types.
local function resolveModTypes(modTypes)
    if type(modTypes) == "string" then modTypes = { modTypes } end
    if type(modTypes) ~= "table" then return {} end
    local out, seen = {}, {}
    for _, m in ipairs(modTypes) do
        if HotkeyManager.bindings[m] and not seen[m] then
            seen[m] = true
            out[#out + 1] = m
        end
    end
    return out
end

-- Show hotkey list for one or more modifier types with searchable chooser or
-- alert. Pass a single modType ("hammer") or a list ({"hammer","hyper"}).
function HotkeyManager.showHotkeyList(modTypes)
    local types = resolveModTypes(modTypes)
    if #types == 0 then
        log:e("Unknown modifier type(s) for showHotkeyList")
        return
    end

    local total = 0
    for _, m in ipairs(types) do total = total + #HotkeyManager.bindings[m] end
    if total == 0 then
        log:w("No bindings registered for the requested modifier(s)")
        hs.alert.show("No hotkeys registered")
        return
    end

    -- Alert layout only supports a single modifier; fall back to the first.
    if HotkeyManager.config.displayMode == "alert" then
        HotkeyManager.showHotkeyListAlert(types[1])
    else
        HotkeyManager.showHotkeyListChooser(types)
    end
end

-- Show hotkey list in searchable chooser format
function HotkeyManager.showHotkeyListChooser(modTypes)
    local types = resolveModTypes(modTypes)
    if #types == 0 then return end
    local combined = #types > 1

    -- Group bindings by category, tagging each with its modifier so the row can
    -- show which layer it belongs to when several are merged.
    local categories = {}
    for _, modType in ipairs(types) do
        for _, binding in ipairs(HotkeyManager.bindings[modType]) do
            if not binding.isTemp then
                local category = categorizeBinding(binding.description)
                categories[category] = categories[category] or {}
                table.insert(categories[category], {
                    key = binding.key,
                    description = binding.description,
                    callback = binding.callback,
                    modType = modType,
                })
            end
        end
    end

    -- Sort each category by key, then by modifier so duplicates group together.
    for _, catBindings in pairs(categories) do
        table.sort(catBindings, function(a, b)
            if a.key == b.key then return a.modType < b.modType end
            return a.key < b.key
        end)
    end

    local choices = {}
    local callbacks = {}
    local callbackIndex = 1

    -- Render one binding into a chooser choice. In combined mode the key column
    -- is prefixed with the modifier glyph, and the modifier name is folded into
    -- subText so it is searchable ("hyper", "hammer").
    local function addChoice(binding, catName)
        local glyph = HotkeyManager.MODIFIER_GLYPHS[binding.modType] or ""
        local keyLabel = combined and (glyph .. " " .. binding.key) or binding.key
        local subText = combined and (catName .. "  ·  " .. binding.modType) or catName
        table.insert(choices, {
            text = string.format("%-14s — %-30s", keyLabel, binding.description),
            subText = subText,
            key = binding.key,
            description = binding.description,
            category = catName,
            callbackIndex = callbackIndex,
        })
        callbacks[callbackIndex] = binding.callback
        callbackIndex = callbackIndex + 1
    end

    local orderedCategories = { "Window Management", "Applications", "Files", "UI & Display", "System", "Other" }
    for _, catName in ipairs(orderedCategories) do
        if categories[catName] and #categories[catName] > 0 then
            table.insert(choices, {
                text = "— " .. catName .. " —",
                subText = "────────────────────────────────────────",
                disabled = true,
            })
            for _, binding in ipairs(categories[catName]) do
                addChoice(binding, catName)
            end
        end
    end

    -- Title / placeholder reflects which layers are shown.
    local titleText
    if combined then
        titleText = "All Hotkeys"
    elseif types[1] == HotkeyManager.MODIFIERS.HAMMER then
        titleText = "Hammer Mode Hotkeys"
    elseif types[1] == HotkeyManager.MODIFIERS.HYPER then
        titleText = "Hyper Mode Hotkeys"
    else
        titleText = "Other Hotkeys"
    end

    local chooser = hs.chooser.new(function(choice)
        if choice and not choice.disabled and choice.callbackIndex and callbacks[choice.callbackIndex] then
            callbacks[choice.callbackIndex]()
        elseif choice and not choice.disabled then
            hs.alert.show("No callback associated with: " .. choice.key, 2)
        end
    end)

    chooser:placeholderText("Search " .. titleText:lower() .. "...")
    chooser:choices(choices)
    chooser:searchSubText(true)
    chooser:rows(15)
    chooser:width(25)
    chooser:show()
end

-- Show hotkey list in original alert format (spread out display)
function HotkeyManager.showHotkeyListAlert(modType)
    local bindings = HotkeyManager.bindings[modType]
    
    -- Group bindings by category
    local categories = {}

    -- First pass: categorize bindings
    for _, binding in ipairs(bindings) do
        if not binding.isTemp then
            local category = "Other"

            -- Determine category based on description
            if binding.description:match("[Ww]indow") or binding.description:match("[Ll]ayout") or
                binding.description:match("[Ss]creen") or binding.description:match("[Ss]huffle") or
                binding.description:match("[Mm]ove") or binding.description:match("[Pp]osition") then
                category = "Window Management"
            elseif binding.description:match("[Oo]pen") or binding.description:match("[Ll]aunch") or
                binding.description:match("App") then
                category = "Applications"
            elseif binding.description:match("[Ff]ile") or binding.description:match("[Ff]older") or
                binding.description:match("[Ii]mage") or binding.description:match("[Mm]enu") then
                category = "Files"
            elseif binding.description:match("[Ss]how") or binding.description:match("[Tt]oggle") or
                binding.description:match("[Ll]ist") or binding.description:match("[Hh]otkey") then
                category = "UI & Display"
            elseif binding.description:match("[Ff]unction") or binding.description:match("[Rr]eload") or
                binding.description:match("[Cc]onsole") then
                category = "System"
            end

            if not categories[category] then
                categories[category] = {}
            end

            table.insert(categories[category], binding)
        end
    end

    -- Sort each category's bindings by key
    for _, catBindings in pairs(categories) do
        table.sort(catBindings, function(a, b)
            return a.key < b.key
        end)
    end

    -- Generate the display text with categories
    local displayText = ""

    -- Add a title
    local titleText = modType == HotkeyManager.MODIFIERS.HAMMER and "Hammer Mode Hotkeys" or
        modType == HotkeyManager.MODIFIERS.HYPER and "Hyper Mode Hotkeys" or "Other Hotkeys"
    displayText = displayText .. titleText .. "\n\n"

    -- Order of categories
    local categoryOrder = { "Window Management", "Applications", "Files", "UI & Display", "System" }

    -- Add categories in preferred order
    for _, catName in ipairs(categoryOrder) do
        if categories[catName] and #categories[catName] > 0 then
            -- Add category header
            displayText = displayText .. "— " .. catName .. " —\n"

            -- Create two columns of hotkeys
            local colWidth = 40
            local col = 0
            local row = ""

            for i, binding in ipairs(categories[catName]) do
                local hotkeyText = string.format("%-6s -- %-25s", binding.key, binding.description)

                if col > 0 then
                    row = row .. string.rep(" ", colWidth - #hotkeyText) .. hotkeyText
                else
                    row = row .. hotkeyText
                end

                col = col + 1

                if col >= 2 or i == #categories[catName] then
                    displayText = displayText .. row .. "\n"
                    row = ""
                    col = 0
                end
            end

            displayText = displayText .. "\n"
        end
    end

    -- Handle "Other" category last
    if categories["Other"] and #categories["Other"] > 0 then
        displayText = displayText .. "— Other —\n"

        -- Create two columns of hotkeys
        local colWidth = 40
        local col = 0
        local row = ""

        for i, binding in ipairs(categories["Other"]) do
            local hotkeyText = string.format("%-6s -- %-25s", binding.key, binding.description)

            if col > 0 then
                row = row .. string.rep(" ", colWidth - #hotkeyText) .. hotkeyText
            else
                row = row .. hotkeyText
            end

            col = col + 1

            if col >= 2 or i == #categories["Other"] then
                displayText = displayText .. row .. "\n"
                row = ""
                col = 0
            end
        end
    end

    -- Show alert with a large size and longer duration
    hs.alert.closeAll()
    hs.alert.show(
        displayText,
        {
            strokeWidth = 0,
            fillColor = { white = 0.1, alpha = 0.95 },
            textColor = { white = 0.9, alpha = 1 },
            textFont = HotkeyManager.config.font,
            textSize = HotkeyManager.config.fontSize,
            radius = HotkeyManager.config.cornerRadius,
            atScreenEdge = 2,
            fadeInDuration = HotkeyManager.config.fadeInDuration,
            fadeOutDuration = HotkeyManager.config.fadeOutDuration,
            padding = 20
        },
        15
    )
end

-- Hide the hotkey list window for a specific modifier type
function HotkeyManager.hideHotkeyList(modType)
    -- Simply close all alerts
    hs.alert.closeAll()
end

-- Show hammer hotkey list or toggle it off if already showing
function HotkeyManager.showHammerList()
    HotkeyManager.showHotkeyList(HotkeyManager.MODIFIERS.HAMMER)
end

-- Show hyper hotkey list or toggle it off if already showing
function HotkeyManager.showHyperList()
    HotkeyManager.showHotkeyList(HotkeyManager.MODIFIERS.HYPER)
end

-- Show hammer and hyper hotkeys together in a single searchable list.
function HotkeyManager.showCombinedList()
    HotkeyManager.showHotkeyList({ HotkeyManager.MODIFIERS.HAMMER, HotkeyManager.MODIFIERS.HYPER })
end

-- Show other hotkey list or toggle it off if already showing
function HotkeyManager.showOtherList()
    HotkeyManager.showHotkeyList(HotkeyManager.MODIFIERS.OTHER)
end

-- Toggle display mode between chooser and alert
function HotkeyManager.toggleDisplayMode()
    if HotkeyManager.config.displayMode == "chooser" then
        HotkeyManager.config.displayMode = "alert"
        hs.alert.show("Hotkey display mode: Alert (spread-out)", 2)
    else
        HotkeyManager.config.displayMode = "chooser"
        hs.alert.show("Hotkey display mode: Chooser (searchable)", 2)
    end
    log:i("Display mode changed to: " .. HotkeyManager.config.displayMode)
end
-- Wrap the original hotkey.bind to automatically register the binding
local originalBind = hs.hotkey.bind
hs.hotkey.bind = function(mods, key, message, pressedfn, releasedfn, repeatfn)
    local description = nil
    local callback = nil

    -- Handle different function signatures
    if type(message) == "function" then
        callback = message
        releasedfn = pressedfn
        repeatfn = releasedfn
        pressedfn = message
    else
        description = message
        callback = pressedfn
    end

    -- Register the binding in our manager
    HotkeyManager.registerBinding(mods, key, callback, description)

    -- Call the original bind function
    return originalBind(mods, key, message, pressedfn, releasedfn, repeatfn)
end

-- Initialize hotkey manager by overriding the global functions
-- This will be called when the module is required
function HotkeyManager.init()
    log:i("Initializing HotkeyManager", __FILE__, 369)

    -- Replace the global functions
    _G.showHammerList = HotkeyManager.showHammerList
    _G.showHyperList = HotkeyManager.showHyperList
    _G.showCombinedList = HotkeyManager.showCombinedList
    _G.showOtherList = HotkeyManager.showOtherList
    _G.toggleHotkeyDisplayMode = HotkeyManager.toggleDisplayMode

    return HotkeyManager
end

-- Configure the display window appearance
function HotkeyManager.configureDisplay(options)
    if type(options) ~= "table" then
        log:e("configureDisplay requires a table of options", __FILE__, 381)
        return HotkeyManager
    end

    -- Apply each provided option with proper error handling
    pcall(function()
        for key, value in pairs(options) do
            if key == "width" or key == "height" or key == "fadeInDuration" or key == "fadeOutDuration" or key == "cornerRadius" or key == "fontSize" then
                if type(value) == "number" then
                    HotkeyManager.config[key] = value
                else
                    log:w("Invalid value for " .. key .. ", must be a number")
                end
            elseif key == "font" then
                if type(value) == "string" then
                    HotkeyManager.config[key] = value
                else
                    log:w("Invalid value for font, must be a string")
                end
            elseif key == "displayMode" then
                if value == "chooser" or value == "alert" then
                    HotkeyManager.config[key] = value
                else
                    log:w("Invalid displayMode, must be 'chooser' or 'alert'")
                end
            elseif key == "backgroundColor" or key == "textColor" then
                if type(value) == "table" and #value >= 3 then
                    HotkeyManager.config[key] = value
                else
                    log:w("Invalid value for " .. key .. ", must be a table of RGB(A) values")
                end
            elseif key == "categoryColors" and type(value) == "table" then
                -- Merge new category colors with existing ones
                for cat, color in pairs(value) do
                    if type(color) == "table" and #color >= 3 then
                        if not HotkeyManager.config.categoryColors then
                            HotkeyManager.config.categoryColors = {}
                        end
                        HotkeyManager.config.categoryColors[cat] = color
                    end
                end
            else
                log:w("Unknown configuration option: " .. key, __FILE__, 417)
            end
        end
    end)

    log:i("Display configuration updated", __FILE__, 421)
    return HotkeyManager
end
return HotkeyManager.init()
