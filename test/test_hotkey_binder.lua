-- Test for HotkeyBinder path resolution.
--
-- Unlike the other scripts in this directory, this one runs OUTSIDE Hammerspoon
-- (it stubs hs.* and HyperLogger), so it can be run from a terminal without
-- disturbing a live session:
--
--   luajit test/test_hotkey_binder.lua
--
-- To check the real bindings against the real loaded modules instead, use the
-- live instance:  hs -c "hs.inspect(require('HotkeyBinder').verify())"


-- LuaJIT is 5.1; Hammerspoon is 5.4. Only matters once a test invokes a
-- binding handler (makeHandler unpacks args), but cheap to keep correct.
table.unpack = table.unpack or unpack

local noop = function() end
_G.hs = {
  configdir = "/Users/d.edens/.hammerspoon",
  fs = { attributes = function() return nil end },
  json = { read = noop, write = noop },
  alert = { show = noop },
  hotkey = { bind = function() return { delete = noop } end },
}
package.loaded['HyperLogger'] = { new = function()
  return { d = noop, i = noop, w = noop, e = noop }
end }

local B = dofile("/Users/d.edens/.hammerspoon/HotkeyBinder.lua")

-- Fake the module shapes the real bindings resolve against
local calls = {}
_G.WindowManager = { applyLayout = function(a) calls[#calls+1] = {"applyLayout", a} end }
_G.spoon = { KineticLatch = {} }
_G.spoon.KineticLatch.toggle = function(self, x) calls[#calls+1] = {"toggle", self, x} end
_G.tempFunction = function() calls[#calls+1] = {"temp"} end
_G.hs.toggleConsole = function() calls[#calls+1] = {"console"} end
_G.NotAFunction = { field = 42 }

local pass, fail = 0, 0
local function check(name, cond, detail)
  if cond then pass = pass + 1
  else fail = fail + 1; print("  FAIL: " .. name .. (detail and (" -- " .. detail) or "")) end
end

-- plain dotted
local fn, selfObj, err = B.resolvePath("WindowManager.applyLayout")
check("dotted resolves", type(fn) == "function", err)
check("dotted has no self", selfObj == nil)

-- bare global
fn, selfObj, err = B.resolvePath("tempFunction")
check("bare global resolves", type(fn) == "function", err)

-- nested builtin
fn, selfObj, err = B.resolvePath("hs.toggleConsole")
check("hs.* resolves", type(fn) == "function", err)

-- method: must hand back the object as self
fn, selfObj, err = B.resolvePath("spoon.KineticLatch:toggle")
check("method resolves", type(fn) == "function", err)
check("method returns self", selfObj == _G.spoon.KineticLatch)
if fn then fn(selfObj, "arg1") end
check("method got correct self", calls[#calls] and calls[#calls][2] == _G.spoon.KineticLatch)
check("method got arg", calls[#calls] and calls[#calls][3] == "arg1")

-- failure modes must be errors, not crashes
fn, selfObj, err = B.resolvePath("Nope.missing")
check("missing module errors", fn == nil and err ~= nil, tostring(err))
fn, selfObj, err = B.resolvePath("NotAFunction.field")
check("non-function errors", fn == nil and err ~= nil, tostring(err))
fn, selfObj, err = B.resolvePath("spoon.Absent:go")
check("absent spoon errors", fn == nil and err ~= nil, tostring(err))
fn, selfObj, err = B.resolvePath("")
check("empty path errors", fn == nil and err ~= nil)
fn, selfObj, err = B.resolvePath(nil)
check("nil path errors", fn == nil and err ~= nil)

-- modifier set resolution
B.config = { modifierSets = { hammer = {"cmd","ctrl","alt"} }, bindings = {} }
local mods = B.resolveMods("hammer")
check("named set resolves", mods and #mods == 3)
mods = B.resolveMods({"ctrl","cmd"})
check("explicit list passes through", mods and #mods == 2)
local m, e2 = B.resolveMods("bogus")
check("unknown set errors", m == nil and e2 ~= nil)

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
