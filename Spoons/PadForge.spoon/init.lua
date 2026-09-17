--- === PadForge ===
---
--- An editor for the XPPen shortcut-remote .pcfg export (tested against an
--- ACK05-B), because the stock XPPen desktop app is a chore to use for
--- reassigning K1-K10. Forked off BindForge's webview/theme plumbing.
---
--- This does NOT talk to the tablet or its driver at all -- it edits the
--- exported config file XPPen's own app writes and reads (File > Export /
--- Import in that app). The intended loop:
---   1. In the XPPen app: Export Config -> a .pcfg file.
---   2. Here: open that file, reassign K3-K10 across modes I-IV -- either to
---      a fresh combo, or to a shortcut Hammerspoon already owns (so the pad
---      button rides an existing binding instead of you inventing a new one).
---   3. Save (rewrites the file in place, touching only the node you changed).
---   4. Back in the XPPen app: Import Config, pick that file.
---
--- K1, K2 and the ring are firmware-fixed in this file format (no user body
--- ever observed for them) and are shown read-only. Per-application override
--- profiles under <Apps> are out of scope -- only the four global mode tabs
--- (I-IV) that the app's main screen shows are editable.
---
--- Usage:
---   hs.loadSpoon("PadForge")
---   spoon.PadForge:bindHotkeys({ window = {{"cmd","alt","ctrl"}, "p"} })

local obj = {}
obj.__index = obj

obj.name = "PadForge"
obj.version = "1.0"
obj.author = "Dan Edens"
obj.license = "MIT - https://opensource.org/licenses/MIT"

obj.codec = nil
obj.window = nil

local function scripts(name)
    local mod = dofile(hs.spoons.resourcePath("scripts/" .. name))
    if mod and obj.spoonPath then mod.assetDir = obj.spoonPath .. "assets/" end
    return mod
end

function obj:init()
    self.codec = dofile(hs.spoons.resourcePath("PcfgCodec.lua"))
    return self
end

--- PadForge:toggleWindow()
--- Method
--- Opens (or closes) the editor window.
function obj:toggleWindow()
    self.window = self.window or scripts("window.lua")
    return self.window.toggle()
end

function obj:bindHotkeys(mapping)
    hs.spoons.bindHotkeysToSpec({
        window = hs.fnutils.partial(self.toggleWindow, self),
    }, mapping)
    return self
end

return obj
