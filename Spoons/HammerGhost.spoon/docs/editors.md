# Editor Windows

Actions, sequences, and conditions are configured in their own small windows
(not the inline Properties Panel), because each has type-specific parameters.
They open when you **Add** one from the [toolbar](toolbar.md), or select one in
the [tree](macro-tree.md) and click **✏️**.

---

## Action Editor

```
Action Editor
┌──────────────────────────────┐
│ Name  [ Notify me          ]  │
│ Type  [ notify          ▾ ]  │
│ ── parameters (per type) ──   │
│ Title [ HammerGhost        ]  │
│ Text  [ {payload.app} is up]  │
│        [ Save ]  [ Cancel ]   │
└──────────────────────────────┘
```

- **Name** — your label for the action.
- **Type** — pick from the built-in action types. Choosing one swaps the
  parameter fields below to match.
- **Parameters** — depend on the type (text, textarea, or a dropdown).
- **Save** — a new action attaches to the [selected container](toolbar.md); an
  existing one is updated in place. **Cancel** closes without saving.

### Built-in action types

| Type | Does | Key parameters |
|------|------|----------------|
| `alert` | On-screen alert | `text` |
| `notify` | macOS notification | `title`, `text` |
| `launchApp` | Launch / focus an app | `app` |
| `keyStroke` | Send a key combo | `mods` (e.g. `cmd,shift`), `key` |
| `typeText` | Type a string at the cursor | `text` |
| `runShell` | Run a shell command (non-blocking) | `command` |
| `openURL` | Open a URL or file | `url` |
| `windowLayout` | Move the focused window | `layout` (maximize/left/right/center) |
| `mqttPublish` | Publish to MQTT | `topic`, `message` |
| `executeScript` | Run arbitrary Lua | `script` |

**Parameters can reference the event** that fired the trigger:
`{event.name}`, `{payload.app}`, `{payload.a.b}`. So a `notify` under an
`App.Activated.*` trigger can say `"{payload.app} is up"`. `executeScript` is the
exception — its script gets the event as `local event = ...` instead. See the
[main README](../README.md#payload-aware-actions).

> `mqttPublish` under a `MQTT.*` trigger can loop through the broker — publish to
> a topic outside the subscribed space.

---

## Sequence Editor

A **sequence** is an ordered list of **steps** — actions and conditions —
executed top to bottom.

```
Sequence Editor
┌──────────────────────────────┐
│  1. [condition] frontmost_app │
│  2. [action]    launchApp     │
│  3. [action]    notify        │
│  [ Add Action ] [ Add Cond. ] │
└──────────────────────────────┘
```

- **Add Action** — opens the action chooser to append an action step.
- **Add Condition** — appends a condition step.

### How gating works

A condition acts as a **gate** for the actions that follow it:

- The gate starts **open**.
- Each condition re-sets the gate to whether it passed (true = open).
- Actions run **only while the gate is open**, until the next condition changes
  it.

So `[condition: frontmost_app is Safari] → [action: typeText]` only types when
Safari is frontmost. Put a condition before the actions it should guard.

---

## Condition Editor

Conditions test the current state and return true/false. They live inside
sequences, where they gate the actions that follow them.

| Type | Tests | Parameters |
|------|-------|------------|
| `frontmost_window` | The focused window's **title** | `title`, `operator` (is / is not / contains) |
| `frontmost_app` | The frontmost **application** name | `app`, `operator` (is / is not / contains) |

Condition parameters support the same `{event}`/`{payload}` templating as
actions.

---

## Adding your own action types

Beyond the built-ins, you can register custom action types in Lua — see
[Registering a custom action type](../README.md#registering-a-custom-action-type)
in the main README.
