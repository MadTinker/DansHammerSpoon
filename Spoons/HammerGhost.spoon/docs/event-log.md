# Event Log

The panel along the bottom. A live, scrolling feed of every event on the bus, as
it fires — whether or not the window is open (it backfills recent history when
you open it).

```
EVENT LOG                                                        [Clear]
13:39:05  Window.Created.Warp
13:39:11  App.Activated.Safari
13:39:14  MQTT.status.macbook.claude.session.context
```

Each row is a **timestamp** + the **event name**. The feed auto-scrolls to the
newest; older rows are capped so it can't grow without bound.

## Click to bind (the killer feature)

This is the fastest way to wire a trigger:

1. Select a **trigger** in the [tree](macro-tree.md).
2. **Click any row** in the log.

The clicked event's name is bound to the trigger's Event Name. No typing, no
guessing the exact dotted name — make the thing happen, see it appear, click it.

(If no trigger is selected, you'll be reminded to select one first.)

## Clear

The **Clear** button empties the visible log. It only clears the display/history
buffer — it doesn't stop events or affect your macros.

## What events look like

Events are named `Source.Verb.Detail`. The detail (app name, product, topic) is
what makes `*` wildcards useful in a trigger's Event Name.

| Source | Examples |
|--------|----------|
| **Application** | `App.Launched.Safari`, `App.Activated.Warp`, `App.Terminated.Slack`, also `Deactivated` / `Hidden` / `Unhidden` |
| **Window** | `Window.Focused.Chrome`, `Window.Created.Warp`, `Window.Destroyed.Warp`, `Window.TitleChanged.Code` |
| **USB** | `USB.Added.Keychron K2`, `USB.Removed.<product>` |
| **System power** | `System.WillSleep`, `System.DidWake`, `System.ScreensDidLock`, `System.ScreensDidUnlock`, … |
| **MQTT** | `MQTT.status.macbook.claude.session.context` — the broker topic, dotted |

Window and MQTT sources can be chatty (Warp redraws fire a lot of
`Window.TitleChanged`/`Created`/`Destroyed`). That's normal — it's why triggers
match on specific names or narrow wildcards rather than everything.

See the [main README](../README.md#payload-aware-actions) for how an action can
read details out of the event that fired it (e.g. `{payload.app}`).
