# PadForge.spoon

An editor for the XPPen shortcut-remote's exported config, for people who
would rather not use the stock desktop app to reassign buttons. Forked off
[BindForge](../BindForge.spoon)'s webview/bridge plumbing; tested against an
ACK05-B export (`PenTableLists` XML, driver version 4.0.0).

It does not talk to the tablet, the driver, or any HID interface — Hammerspoon
has no path to that. It edits the file the XPPen app itself writes and reads:

1. In the XPPen app: **Export Config** → a `.pcfg` file.
2. Here: open that file, reassign K3–K10 across modes I–IV. Each key can take
   a fresh combo, or reuse a shortcut already bound in `hotkeys.json` (via
   BindForge), so the pad rides an existing binding instead of inventing one.
3. Save — rewrites the one `<Kn>` node you changed, byte-identical everywhere
   else in the file (it holds profiles for every tablet model XPPen ships).
4. In the XPPen app: **Import Config**, pick that file, push it to the pad.

## Scope

- K1, K2, and the ring are firmware-fixed in this file format (no user
  override was ever observed for them across the sample file's ~200 device
  profiles) — shown read-only.
- Only the four global mode tabs (I–IV) are editable — the ones the app's
  main screen shows. Per-application override profiles (under `<Apps>`) are
  out of scope.
- Only plain keystroke assignments are supported (a `count=1` body: label +
  display + encoded keycodes). Pure modifier-chord slots and other
  non-keystroke actions (e.g. "switch monitor") are shown as unrecognized and
  left untouched.
- The Qt keycode half of each encoded pair is a best-effort table for the
  keys a shortcut pad actually uses (letters/digits/punctuation, F-keys,
  arrows, Return/Escape/Tab/Space/Delete, and the four modifiers). It has not
  been round-tripped through an actual device import — verify one small
  change works before trusting a batch of them.

## Usage

```lua
hs.loadSpoon("PadForge")
spoon.PadForge:init()
spoon.PadForge:bindHotkeys({ window = {{"cmd","alt","ctrl"}, "p"} })
```

Or drive it from the console without a hotkey: `spoon.PadForge:toggleWindow()`.
