#!/usr/bin/env python3
"""Assemble the artifact build of the keymap editor.

An artifact is a single self-contained page: the CSP blocks every external
script host except a short CDN allowlist, so the renderer and its transport
have to be inlined. This mirrors what editor_window.lua does for the
HammerGhost webview at runtime — same two files, inlined the same way, so
assets/keymap.js stays the one renderer for every surface.

    python3 scripts/build_keymap_artifact.py [out.html]
"""
import sys
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
ASSETS = ROOT / "Spoons/HammerGhost.spoon/assets"
OUT = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "build/keymap_artifact.html"


def read(name):
    path = ASSETS / name
    if not path.exists():
        sys.exit(f"missing asset: {path}")
    return path.read_text(encoding="utf-8")


shell = read("keymap_page.html")
transport = read("keymap_transport_artifact.js")
renderer = read("keymap.js")
widgets = read("param_widgets.js")
themes = read("keymap_themes.js")
theme = read("keymap_theme.js")

# The artifact surface is honest about being unable to reach the machine; the
# HTTP surface injects its own notice into this same shell (see keymap_server.lua).
NOTICE = """<p>
                    <strong>This is the offline editor.</strong> An artifact is sandboxed away
                    from your machine, so edits here are saved to this page, not applied to the
                    live keyboard. Export <code>hotkeys.json</code>, drop it in
                    <code>~/.hammerspoon</code>, and press <kbd>&#8984;&#8963;&#8997;&#39;</kbd>
                    to apply &mdash; no reload.
                </p>"""

for token, body in (("__NOTICE__", NOTICE), ("__WIDGETS__", widgets),
                    ("__THEMES__", themes), ("__THEME__", theme),
                    ("__TRANSPORT__", transport), ("__RENDERER__", renderer)):
    # Exactly once: the shell must not mention a token anywhere but its slot,
    # or the substitution lands in the wrong place (it did, once).
    if shell.count(token) != 1:
        sys.exit(f"shell has {shell.count(token)} occurrences of {token}, expected 1")
    # A literal "</script>" inside an inlined script would close the tag early.
    if "</script>" in body:
        sys.exit(f"{token} body contains a literal </script>")
    shell = shell.replace(token, body, 1)

OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(shell, encoding="utf-8")
print(f"wrote {OUT} ({len(shell):,} bytes)")
