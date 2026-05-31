# Properties Panel

The right panel. Shows the **currently selected** item and lets you edit it
inline. With nothing selected it reads *"Select an item to edit its
properties."*

```
Properties
┌──────────────────────────────────┐
│ Name   [ On Warp Window        ]  │
│ Type   [ trigger               ]  │   ← read-only
│ Event  [ Window.Created.Warp   ]  │   ← triggers only
│         Tip: click an event in     │
│         the log below to bind it.  │
│        [ Save ]   [ Cancel ]       │
└──────────────────────────────────┘
```

## Fields

- **Name** — a label for you. Rename freely; it has no effect on behavior.
- **Type** — read-only (folder / trigger / action / sequence).
- **Event Name** — **triggers only.** The event this trigger listens for. This is
  the link between an event and the actions underneath the trigger.

## Event Name: what to type

The Event Name is matched against live events
([see the full list](event-log.md)). It can be:

- A **literal**: `System.WillSleep`, `App.Activated.Safari`
- A **wildcard**: `App.Activated.*` (any app), `Window.*.Warp`,
  `MQTT.status.*.claude.*`
  - `*` matches any run of characters (including dots); `?` matches one.

Don't know the exact name? Trigger the event once (switch an app, plug in a USB
device, …), find it in the [Event Log](event-log.md), and click it to fill this
field automatically — see below.

## Save / Cancel

- **Save** — writes the name (and, for triggers, the event name) and persists the
  tree. If the item somehow isn't in the tree anymore, Save tells you instead of
  silently doing nothing.
- **Cancel** — discards edits and clears the panel.

## Binding an event by clicking the log

The fast way to set a trigger's Event Name:

1. Select the trigger.
2. Click any row in the [Event Log](event-log.md).

The clicked event's name is bound to the trigger immediately (you'll see a
confirmation). This is the "see it fire, click it onto a trigger" loop — no
typing or guessing exact event names.

## Editing actions and sequences

Actions, sequences, and conditions aren't edited here — selecting them and
clicking **✏️** in the tree opens their dedicated [editor windows](editors.md),
which expose type-specific parameters.
