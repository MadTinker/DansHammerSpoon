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


shell = read("keymap_artifact.html")
transport = read("keymap_transport_artifact.js")
renderer = read("keymap.js")

for token, body in (("__TRANSPORT__", transport), ("__RENDERER__", renderer)):
    if token not in shell:
        sys.exit(f"shell is missing the {token} placeholder")
    # A literal "</script>" inside an inlined script would close the tag early.
    if "</script>" in body:
        sys.exit(f"{token} body contains a literal </script>")
    shell = shell.replace(token, body, 1)

OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(shell, encoding="utf-8")
print(f"wrote {OUT} ({len(shell):,} bytes)")
