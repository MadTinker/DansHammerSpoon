# Macro Tree

The left panel: a nested, drag-and-drop tree of everything you've built. The
header above it shows the total item count ("3 items").

```
▾ 📁 My Macros               ✏️ 🗑️
  ▾ ⚡ On Warp Window         ✏️ 🗑️
      ⚙️ Notify me            ✏️ 🗑️
  ▸ 📁 Disabled stuff         ✏️ 🗑️
```

## Item types

| Icon role | Type | Holds |
|-----------|------|-------|
| Folder | `folder` | Anything — for grouping |
| Trigger | `trigger` | Actions to run when its event fires |
| Action | `action` | Nothing — it's a leaf that *does* something |
| Sequence | `sequence` | A gated list of steps (actions + conditions) |

## Row anatomy

Each row reacts differently depending on **where** you click it:

- **Disclosure triangle** (`▾` / `▸`) — on containers with children. Click to
  expand/collapse. The state is saved, so a folder stays collapsed across
  reloads.
- **Item icon** — click the icon itself to **enable/disable** the item (see
  below).
- **Name / empty row area** — click to **select** the item. The
  [Properties Panel](properties.md) updates to show it.
- **✏️ Edit** — opens the right editor for the type: actions/sequences/conditions
  open their dedicated [editor window](editors.md); folders and triggers open in
  the inline Properties Panel.
- **🗑️ Delete** — removes the item (and its children). Confirms first.

## Selecting

Clicking the name or row body selects. Selection matters: it's both what the
Properties Panel edits **and** where the next [toolbar](toolbar.md) "Add" lands.
The selected row is highlighted.

## Drag and drop

Drag any row onto another to move it:

- Drop **on the upper/lower half** of a row → place it **before/after** that row
  (same level).
- Drop **onto a container** → place it **inside** as a child.

Moves save automatically.

## Enable / disable

**Click an item's icon** to toggle it enabled/disabled. A disabled item is
skipped when its parent runs, and a disabled trigger never fires — a way to mute
something without deleting it. Disabled items render greyed out, and the state
is saved so it survives reloads.
