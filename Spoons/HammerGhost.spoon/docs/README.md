# HammerGhost — Interface Guide

A tour of the HammerGhost window, section by section. New here? Read the
[main README](../README.md) first for the Event → Trigger → Actions model, then
come back for the details of each part of the UI.

## Window layout

```
┌─────────────────────────────────────────────────────────────────────┐
│  [Add Folder] [Add Trigger] [Add Action] [Add Sequence]   [Save] [↻] │  ← Toolbar
├─────────────────────────────────────────────────────────────────────┤
│  HammerGhost                                              3 items     │  ← Header
├──────────────────────────────────┬──────────────────────────────────┤
│  ▾ 📁 My Macros          ✏️ 🗑️    │  Properties                       │
│    ▾ ⚡ On Warp Window    ✏️ 🗑️    │  ┌────────────────────────────┐   │
│        ⚙️ Notify me       ✏️ 🗑️    │  │ Name  [ On Warp Window   ] │   │
│                                  ║   │ Type  [ trigger          ] │   │
│      Macro Tree                  ║   │ Event [ Window.Created.*  ] │   │
│                                  ║   │        [Save]  [Cancel]    │   │
│                          divider ║   │      Properties Panel      │   │
├──────────────────────────────────┴──────────────────────────────────┤
│  EVENT LOG                                                  [Clear]   │
│  13:39:05  Window.Created.Warp                                        │  ← Event Log
│  13:39:11  App.Activated.Safari                                       │
└─────────────────────────────────────────────────────────────────────┘
```

## Sections

| Section | What it's for | Doc |
|---------|---------------|-----|
| **Toolbar** | Add items to the tree; save/reload the whole config | [toolbar.md](toolbar.md) |
| **Macro Tree** | The live tree of folders, triggers, actions, sequences | [macro-tree.md](macro-tree.md) |
| **Properties Panel** | Edit the selected item's name and (for triggers) bound event | [properties.md](properties.md) |
| **Event Log** | Watch events fire in real time; click one to bind it to a trigger | [event-log.md](event-log.md) |
| **Editor Windows** | Configure actions, sequences, and conditions in detail | [editors.md](editors.md) |

## The 30-second workflow

1. **Add Trigger** → set its **Event Name** in Properties → **Save**.
2. Select the trigger, **Add Action** → pick a type → **Save**.
3. Watch the **Event Log** to confirm the event is firing.

That's a working automation: event fires → trigger matches → action runs.
