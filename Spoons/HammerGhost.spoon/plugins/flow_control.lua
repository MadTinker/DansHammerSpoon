-- Spoons/HammerGhost.spoon/plugins/flow_control.lua
--
-- EventGhost-parity flow control: enable / disable / toggle / run another tree
-- item by NAME. Handlers reach the live spoon through the `spoon.HammerGhost`
-- global and its plugin API (findItemByName / setItemEnabled / toggleItem /
-- runItem). Addressing by name (not id) keeps macros readable and portable.

return function(action_system)
    -- Enable a tree item by name (so a disabled macro can be armed from another).
    action_system.registerActionType("enableItem", {
        name = "Enable Item",
        parameters = {
            target = { type = "text", required = true, default = "" }
        },
        handler = function(params)
            if not params.target or params.target == "" then return end
            if not spoon.HammerGhost:setItemEnabled(params.target, true) then
                hs.alert.show("No item named: " .. tostring(params.target))
            end
        end
    })

    -- Disable a tree item by name.
    action_system.registerActionType("disableItem", {
        name = "Disable Item",
        parameters = {
            target = { type = "text", required = true, default = "" }
        },
        handler = function(params)
            if not params.target or params.target == "" then return end
            if not spoon.HammerGhost:setItemEnabled(params.target, false) then
                hs.alert.show("No item named: " .. tostring(params.target))
            end
        end
    })

    -- Flip a tree item's enabled state by name.
    action_system.registerActionType("toggleItem", {
        name = "Toggle Item",
        parameters = {
            target = { type = "text", required = true, default = "" }
        },
        handler = function(params)
            local item = spoon.HammerGhost:findItemByName(params.target)
            if item then
                spoon.HammerGhost:toggleItem(item.id)
            else
                hs.alert.show("No item named: " .. tostring(params.target))
            end
        end
    })

    -- Run another item by name (EventGhost's "Jump" / run-macro). A trigger runs
    -- its children; an action/sequence/folder runs directly.
    action_system.registerActionType("runItem", {
        name = "Run Item (Jump)",
        parameters = {
            target = { type = "text", required = true, default = "" }
        },
        handler = function(params)
            local item = spoon.HammerGhost:findItemByName(params.target)
            if item then
                spoon.HammerGhost:runItem(item.id)
            else
                hs.alert.show("No item named: " .. tostring(params.target))
            end
        end
    })
end
