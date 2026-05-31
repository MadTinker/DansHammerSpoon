# Toolbar

The strip of buttons across the top of the window. Everything here acts on the
**macro tree** as a whole, or adds a new item to it.

```
[Add Folder]  [Add Trigger]  [Add Action]  [Add Sequence]      [Save]  [Reload]
```

## Add buttons

New items are placed **relative to the current selection**:

- Nothing selected → the new item goes to the **top level** of the tree.
- A **container** selected (folder/trigger/sequence) → the new item becomes a
  **child** of it.

So to nest an action inside a trigger, **select the trigger first**, then
Add Action. (Add Action with nothing selected makes a top-level action that
never runs — only triggers and folders execute their children on events.)

| Button | Adds | Notes |
|--------|------|-------|
| **Add Folder** | A folder | Pure organization. Holds any items. |
| **Add Trigger** | A trigger | The thing that listens for an event. Set its Event Name in [Properties](properties.md). Opens for editing immediately. |
| **Add Action** | An action | Opens the [Action Editor](editors.md) to pick a type + parameters. Attaches to the selected container. |
| **Add Sequence** | A sequence | Opens the [Sequence Editor](editors.md) — a gated list of actions and conditions. |

## Save

Writes the **entire macro tree** to disk
(`~/.hammerspoon/hammerghost_config.json`) and flashes "Configuration saved".

You usually don't need this — adding, editing, deleting, toggling, and moving
items all save automatically. It's here for peace of mind.

## Reload

Re-reads the config file from disk, discarding any unsaved in-memory state, and
clears the current selection. Use it if you edited the JSON by hand, or to
recover a known-good state.

> **Reload** here ≠ Hammerspoon's `hs.reload()`. This only reloads HammerGhost's
> macro tree, not your whole Hammerspoon config.
