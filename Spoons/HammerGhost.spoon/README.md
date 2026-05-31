# HammerGhost Spoon

An [EventGhost](https://www.eventghost.net/)-like, event-driven automation GUI
for Hammerspoon. System events (app/window/USB/power changes, MQTT messages) flow
onto a shared event bus; you bind **triggers** to those events and hang
**actions** off the triggers. When a matching event fires, the trigger runs its
actions.

```
 event source ──▶ event bus ──▶ trigger (eventName match) ──▶ its child actions
 (App/Window/USB/                                              (alert, runShell,
  System/MQTT)                                                  launchApp, …)
```

## The mental model

| Thing | What it is | Key fields |
|-------|-----------|------------|
| **Event** | A signal on the bus, named like `Window.Created.Warp`. Not a tree item — just a name. | — |
| **Trigger** | A container that listens for an event and runs its children when it fires. | `eventName`, `children` |
| **Action** | A leaf that *does* something (alert, launch an app, run a shell command…). | `actionType`, `params` |
| **Folder** | Grouping for organization; runs its children in order when executed. | `children` |
| **Sequence** | A gated step-list: conditions open/close a gate for the actions after them. | `steps` |

The connection is **parent → child**: actions live *inside* a trigger. The chain
is **Event → (matches) → Trigger → (runs) → its child Actions**.

## Wiring up a macro (in the GUI)

1. **Add Trigger** → in Properties set **Event Name** (e.g. `Window.Created.Warp`)
   → **Save**.
   - Shortcut: with the trigger selected, **click any row in the Event Log** to
     bind that event name automatically.
2. **Click the trigger** in the tree to select it. *(Load-bearing: the next
   action attaches to whatever is selected.)*
3. **Add Action** → choose the action type + parameters → **Save**. The action is
   created as a **child of the selected trigger**.
4. Done — when the event fires, the trigger runs the action.

> If you Add Action with nothing (or a non-container) selected, the action lands
> at the top level and never runs — only triggers/folders run their children on
> events. Select the trigger first.

## Event sources

Watchers normalize raw Hammerspoon callbacks into EventGhost-style dotted names
and emit them on the bus. All start/stop together and are idempotent across
`hs.reload()`.

| Source | Event names |
|--------|-------------|
| Application | `App.Launched/Terminated/Activated/Deactivated/Hidden/Unhidden.<app>` |
| Window | `Window.Focused/Created/Destroyed/TitleChanged.<app>` |
| USB | `USB.Added/Removed.<product>` |
| System power | `System.WillSleep/DidWake/ScreensDidLock/ScreensDidUnlock/…` |
| MQTT | `MQTT.<dotted topic>` — tails the local broker via `mosquitto_sub` |

The MQTT source defaults to **madqtt**'s claude-lifecycle topics
(`status/+/claude/#`); broker is `MADNESS_MQTT_HOST` /
`MADNESS_MQTT_PORT` (default `localhost:1883`). The chatty `activity/#` firehose
is opt-in (commented in `scripts/event_sources.lua`).

## Wildcard event matching

A trigger's **Event Name** is matched EventGhost-style:

- A literal (`System.WillSleep`) matches exactly.
- `*` matches any run of characters, **including dots**: `App.Activated.*` fires
  for any app activation; `MQTT.status.*.claude.*` matches the device-mid MQTT
  topics.
- `?` matches exactly one character.

## Payload-aware actions

Each event carries a payload. String action/condition parameters are templated
against the firing event before the handler runs:

- `{event.name}` → the full event name
- `{payload.app}`, `{payload.a.b}` → (nested) payload fields
- A missing key → empty string; an **unknown root** (e.g. shell `${HOME}`) is
  left untouched so shell expansions survive.

So a trigger on `App.Activated.*` can `notify` with text `"{payload.app} is up"`.

`executeScript` is the exception (its body is Lua — `{...}` is table syntax):
instead it receives the event as a call argument —

```lua
local event = ...
hs.alert.show(event.name .. " / " .. (event.payload.app or "?"))
```

## Built-in action types

`alert`, `executeScript`, `launchApp`, `keyStroke`, `typeText`, `runShell`
(non-blocking via `hs.task`), `openURL`, `notify`, `windowLayout`
(maximize/left/right/center), `mqttPublish`.

> `mqttPublish` paired with a `MQTT.*` trigger creates a feedback loop through
> the broker. Topic your publishes outside the subscribed space.

Conditions (used in sequences): `frontmost_window`, `frontmost_app`.

## Persistence

The macro tree is stored as JSON at `~/.hammerspoon/hammerghost_config.json`
(`scripts/config.lua`), round-tripping the whole tree — `actionType`, `params`,
`eventName`, `enabled`, `expanded`. It survives `hs.reload()`. An empty/missing
config self-heals to a single default macro on init.

## Programmatic API

```lua
hs.loadSpoon("HammerGhost")
spoon.HammerGhost:init()          -- load config + start event sources (no window)
spoon.HammerGhost:toggle()        -- show/hide the editor window
```

Hotkeys are bound in this config's `hotkeys.lua` (not via `bindHotkeys`):

| Keys | Action |
|------|--------|
| `hammer + h` | Toggle the HammerGhost editor window |
| `hammer + g` | Toggle the Mad Tinker control panel |
| `✧ (hyper) + m` | Open the Action Editor |

To bind via the Spoon helper instead, the recognized spec keys are `toggle`,
`showActionEditor`, `controlPanel`:

```lua
spoon.HammerGhost:bindHotkeys({
    toggle        = { {"cmd","alt","ctrl"}, "h" },
    showActionEditor = { {"cmd","alt","ctrl"}, "e" },
    controlPanel  = { {"cmd","alt","ctrl"}, "g" },
})
```

### Registering a custom action type

```lua
local action_system = dofile(hs.spoons.resourcePath("scripts/action_system.lua"))

action_system.registerActionType("myAction", {
    name = "My Action",
    parameters = {
        text = { type = "text", required = true, default = "hi" },
    },
    -- params are already templated; event is the firing bus event (may be nil).
    handler = function(params, event)
        hs.alert.show(params.text)
    end,
})
```

## Architecture notes

- **Event bus** (`scripts/event_bus.lua`): a `_G` singleton (so every `dofile`
  loader shares one bus) with a capped ring buffer so the live log can backfill
  recent history when the window opens.
- **Event sources** (`scripts/event_sources.lua`): thin, idempotent watcher
  wrappers; each normalizes to a dotted name and calls `eventBus.emit`.
- **Dispatcher** (`init.lua`): subscribes to the bus, matches each event against
  enabled triggers (wildcard), and runs matched triggers' children.
- **UI**: `hs.webview` with a `hammerspoon://` URL scheme bridging JS → Lua.
  HTML/CSS/JS live in `assets/`; the tree is pre-rendered into the document so
  the window opens fully populated.

## Roadmap

- Hotkey event source (`Hotkey.<mods+key>` on the bus)
- EventGhost `.egtree` XML import (the `xmlparser.lua` is kept wired for this)
- Richer sequence editor

## License

MIT License
