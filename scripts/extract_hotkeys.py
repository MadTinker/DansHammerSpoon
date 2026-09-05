#!/usr/bin/env python3
"""One-time extraction: hotkeys.lua bind wall -> hotkeys.json binding table.

Kept in-tree (scripts/) rather than run-and-discarded so the migration is
auditable: rerun it against the pre-migration hotkeys.lua and diff the result.
Anything it cannot parse is reported, never silently dropped.
"""
import json
import re
import sys
from collections import OrderedDict

SRC = sys.argv[1] if len(sys.argv) > 1 else "/Users/d.edens/.hammerspoon/hotkeys.lua"
OUT = sys.argv[2] if len(sys.argv) > 2 else "/Users/d.edens/.hammerspoon/hotkeys.json"

MOD_ALIASES = {"hammer": "hammer", "_hyper": "hyper", "_meta": "meta"}

# hs.hotkey.bind( mods , "key" , "desc" , function() body end [, ...] )
BIND_RE = re.compile(
    r'^\s*hs\.hotkey\.bind\('
    r'(?P<mods>hammer|_hyper|_meta|"[^"]+"|\{[^}]*\})\s*,\s*'
    r'"(?P<key>(?:[^"\\]|\\.)+)"\s*,\s*'
    r'"(?P<desc>[^"]*)"\s*,\s*'
    r'function\(\)\s*(?P<body>.*?)\s*end'
    r'(?P<tail>.*)$'
)

# A body that is exactly one call: Foo.bar(args) / Foo:bar(args) / foo(args)
CALL_RE = re.compile(r'^(?P<path>[A-Za-z_][\w.]*(?::[A-Za-z_]\w*)?)\((?P<args>.*)\)$')


LUA_ESCAPES = {"\\\\": "\\", '\\"': '"', "\\'": "'", "\\n": "\n", "\\t": "\t"}


def lua_unescape(s):
    r"""Resolve Lua string escapes. The '\\' key binding is literally one
    backslash in Lua source; carried through raw it becomes a 2-char key that
    hs.hotkey.bind will never match."""
    return re.sub(r'\\[\\"\'nt]', lambda m: LUA_ESCAPES[m.group(0)], s)


def parse_mods(raw):
    """Return (mods_value, is_alias). Alias name, or explicit list of modifiers."""
    if raw in MOD_ALIASES:
        return MOD_ALIASES[raw], True
    if raw.startswith('"'):
        return [raw.strip('"')], False
    inner = raw.strip("{}").strip()
    if not inner:
        return [], False
    return [p.strip().strip('"') for p in inner.split(",") if p.strip()], False


def parse_args(raw):
    """Lua arg list -> JSON values. Only literals; returns None if anything else."""
    raw = raw.strip()
    if not raw:
        return []
    out = []
    for part in [p.strip() for p in raw.split(",")]:
        if re.fullmatch(r'"[^"]*"', part):
            out.append(part[1:-1])
        elif re.fullmatch(r"'[^']*'", part):
            out.append(part[1:-1])
        elif re.fullmatch(r"-?\d+", part):
            out.append(int(part))
        elif re.fullmatch(r"-?\d*\.\d+", part):
            out.append(float(part))
        elif part in ("true", "false"):
            out.append(part == "true")
        elif part == "nil":
            out.append(None)
        else:
            return None  # non-literal (variable, expression) -> caller must skip
    return out


def main():
    with open(SRC) as fh:
        lines = fh.readlines()

    bindings = []
    unparsed = []
    pending_note = []   # comment lines immediately above a bind
    seen_ids = {}

    for lineno, line in enumerate(lines, 1):
        stripped = line.strip()

        # Collect comments so load-bearing notes survive the move to JSON.
        if stripped.startswith("--"):
            text = stripped.lstrip("-").strip()
            # Skip section headers ("Keybindings - Top Row", "Shift Row") and
            # commented-out binds; keep only real explanatory notes.
            is_header = text.startswith("Keybindings") or re.fullmatch(r"[\w\s]*Row", text)
            if text and not is_header and "hs.hotkey.bind" not in text:
                pending_note.append(text)
            continue

        m = BIND_RE.match(line)
        if not m:
            if "hs.hotkey.bind(" in line and not stripped.startswith("--"):
                unparsed.append((lineno, stripped))
            if stripped:
                pending_note = []
            continue

        note = " ".join(pending_note) if pending_note else None
        pending_note = []

        mods_raw, key, desc, body, tail = (
            m.group("mods"), lua_unescape(m.group("key")), lua_unescape(m.group("desc")),
            m.group("body"), m.group("tail"),
        )
        mods, is_alias = parse_mods(mods_raw)

        cm = CALL_RE.match(body)
        if not cm:
            unparsed.append((lineno, stripped))
            continue
        args = parse_args(cm.group("args"))
        if args is None:
            unparsed.append((lineno, stripped))
            continue

        path = cm.group("path")
        action = OrderedDict([("kind", "call"), ("fn", path)])
        if args:
            action["args"] = args

        # A no-op release handler (", nil, function() end") is how the existing
        # binds suppress key-repeat on toggles. Carry the intent, not the closure.
        norepeat = "function() end" in tail

        key_label = mods if is_alias else "+".join(mods)
        bid = f"{key_label}+{key}"
        if bid in seen_ids:
            seen_ids[bid] += 1
            bid = f"{bid}#{seen_ids[bid]}"
        else:
            seen_ids[bid] = 1

        entry = OrderedDict()
        entry["id"] = bid
        entry["mods"] = mods
        entry["key"] = key
        entry["description"] = desc
        entry["action"] = action
        if norepeat:
            entry["noRepeat"] = True
        if path == "tempFunction":
            entry["placeholder"] = True
        if note:
            entry["note"] = note
        entry["source"] = f"hotkeys.lua:{lineno}"
        bindings.append(entry)

    doc = OrderedDict()
    doc["version"] = 1
    doc["_comment"] = (
        "Declarative hotkey table. Edited by hand, by the HammerGhost keymap tab, "
        "or by the artifact editor -- all three write this same schema. "
        "See HotkeyBinder.lua for how it is applied."
    )
    doc["modifierSets"] = OrderedDict([
        ("hammer", ["cmd", "ctrl", "alt"]),
        ("hyper", ["cmd", "shift", "ctrl", "alt"]),
        ("meta", ["cmd", "shift", "alt"]),
    ])
    doc["bindings"] = bindings

    with open(OUT, "w") as fh:
        json.dump(doc, fh, indent=2)
        fh.write("\n")

    print(f"extracted {len(bindings)} bindings -> {OUT}")
    placeholders = sum(1 for b in bindings if b.get("placeholder"))
    print(f"  placeholders (tempFunction): {placeholders}")
    print(f"  with carried notes:          {sum(1 for b in bindings if b.get('note'))}")
    if unparsed:
        print(f"\nUNPARSED ({len(unparsed)}) -- these must stay imperative in hotkeys.lua:")
        for lineno, text in unparsed:
            print(f"  {lineno}: {text[:110]}")


if __name__ == "__main__":
    main()
