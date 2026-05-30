local config = {}

-- Helper function to find the highest ID
local function findHighestId(macroTree)
    local highestId = 0
    local function traverse(items)
        for _, item in ipairs(items) do
            if tonumber(item.id) and tonumber(item.id) > highestId then
                highestId = tonumber(item.id)
            end
            if item.children then
                traverse(item.children)
            end
        end
    end
    traverse(macroTree)
    return highestId
end

-- Add this function to validate the macro tree
local function validateMacroTree(macroTree)
    local hasError = false
    local function traverse(items)
        for _, item in ipairs(items) do
            if not item.name then
                hs.logger.new("HammerGhost"):e("Macro item missing 'name': " .. hs.inspect(item))
                hasError = true
            end
            if item.children then
                traverse(item.children)
            end
        end
    end
    traverse(macroTree)
    return not hasError
end

-- Initialize the module with dependencies
function config.init(deps)
    config.xmlparser = deps.xmlparser
    return config
end

-- Load the macro tree from a JSON file. Returns (macros, lastId).
--
-- JSON (not the old XML) is the store because the model is a nested table of
-- arbitrary fields — actionType, params, steps, eventName, enabled, expanded —
-- and the previous XML serializer only persisted id/name/type, silently
-- dropping every item's actual behavior on reload. JSON round-trips the whole
-- tree.
function config.loadMacros(filepath)
    local file = io.open(filepath, "r")
    if not file then
        -- No config yet; caller seeds a default tree.
        return {}, 0
    end

    local content = file:read("*all")
    file:close()

    local ok, decoded = pcall(function() return hs.json.decode(content) end)
    if not ok or type(decoded) ~= "table" then
        hs.logger.new("HammerGhost"):e("Could not parse config JSON; starting empty")
        return {}, 0
    end

    return decoded, findHighestId(decoded)
end

-- Save the macro tree to a JSON file. The whole tree is persisted verbatim.
function config.saveMacros(filepath, macros)
    -- Encode BEFORE opening the file: if encoding fails, the existing config
    -- (now the real macro data) must not be truncated to empty.
    local ok, json = pcall(function() return hs.json.encode(macros, true) end)
    if not ok or type(json) ~= "string" then
        hs.logger.new("HammerGhost"):e("Could not encode macro tree; not saving")
        return false
    end

    local file = io.open(filepath, "w")
    if not file then
        return false
    end
    file:write(json)
    file:close()
    return true
end

return config
