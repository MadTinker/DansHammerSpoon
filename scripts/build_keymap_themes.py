#!/usr/bin/env python3
"""Generate assets/keymap_themes.js from the MadnessThemes submodule.

The keymap editor styles itself from CSS custom properties. This maps each
Madness palette onto that token set ONCE, here, so the browser does no colour
maths and all three surfaces consume the identical generated file.

Only palettes carrying a `colors` tree are usable; the other files in that repo
are a different schema and are skipped.

    python3 scripts/build_keymap_themes.py
"""
import glob
import json
import os
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
THEMES = ROOT / "themes"
OUT = ROOT / "Spoons/BindForge.spoon/assets/keymap_themes.js"


def parse_color(value):
    """Return (r, g, b) for a hex or rgb/rgba string, else None. A gradient or
    anything else unparseable returns None and callers fall back."""
    if not isinstance(value, str):
        return None
    v = value.strip()
    m = re.fullmatch(r"#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})", v)
    if m:
        h = m.group(1)
        if len(h) == 3:
            h = "".join(c * 2 for c in h)
        return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))
    m = re.match(r"rgba?\(\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)", v)
    if m:
        return tuple(int(float(g)) for g in m.groups())
    return None


def luminance(rgb):
    """Relative luminance, for picking readable ink on an accent fill."""
    def channel(c):
        c = c / 255
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = (channel(c) for c in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def rgba(value, alpha, fallback="rgba(128,128,128,%s)"):
    rgb = parse_color(value)
    if not rgb:
        return fallback % alpha
    return f"rgba({rgb[0]},{rgb[1]},{rgb[2]},{alpha})"


def pick(*values):
    """First value that is a non-empty string."""
    for v in values:
        if isinstance(v, str) and v.strip():
            return v
    return None


def build_tokens(colors):
    bg = colors.get("background") or {}
    card = bg.get("card") or {}
    text = colors.get("text") or {}
    border = colors.get("border") or {}
    accent_tree = colors.get("accent") or {}

    accent = pick(colors.get("primary"), border.get("primary"), "#888888")
    # Ink that stays readable ON the accent fill, rather than assuming dark-on-light.
    accent_rgb = parse_color(accent)
    # 0.179 is the luminance where black and white ink give equal contrast;
    # a higher threshold picks white on mid-tone accents that black reads
    # better on (e.g. #ba68c8: white 3.6:1 vs black 5.8:1).
    accent_ink = "#0b0b0b" if (accent_rgb and luminance(accent_rgb) > 0.179) else "#ffffff"

    # background.main is frequently a linear-gradient, so it is only ever used as
    # a page background -- every surface colour comes from background.card, which
    # is a flat or translucent layer.
    ground = pick(bg.get("main"), "#12121a")
    surface = pick(card.get("normal"), bg.get("header"), "rgba(255,255,255,0.04)")
    surface2 = pick(card.get("hover"), card.get("selected"), "rgba(255,255,255,0.07)")

    return {
        "--ground": ground,
        "--surface": surface,
        "--surface-2": surface2,
        "--cap": surface,
        "--cap-edge": pick(border.get("subtle"), border.get("primary")) or rgba(accent, 0.3),
        "--ink": pick(text.get("primary"), "#e8e8ec"),
        "--ink-soft": pick(text.get("secondary"), text.get("tertiary"), "#a8a8b0"),
        "--ink-faint": pick(text.get("muted"), text.get("tertiary"), "#7a7a84"),
        "--rule": pick(border.get("subtle"), border.get("primary")) or rgba(accent, 0.22),
        "--accent": accent,
        "--accent-ink": accent_ink,
        "--accent-soft": rgba(accent, 0.18),
        "--teal": pick(accent_tree.get("cyan"), colors.get("secondary"), accent),
        "--bad": pick(colors.get("error"), text.get("error"), "#d9534f"),
        "--bad-soft": rgba(pick(colors.get("error"), "#d9534f"), 0.16),
        "--warn": pick(colors.get("warning"), text.get("warning"), "#d9a441"),
        "--shadow": "0 1px 0 rgba(0,0,0,.35), 0 2px 6px rgba(0,0,0,.30)",

        # HammerGhost's styles.css uses its own token names. The webview page
        # inherits those, so set both families and one palette themes every surface.
        "--bg-color": ground,
        "--text-color": pick(text.get("primary"), "#e8e8ec"),
        "--muted-color": pick(text.get("muted"), text.get("tertiary"), "#7a7a84"),
        "--border-color": pick(border.get("subtle"), border.get("primary")) or rgba(accent, 0.22),
        "--hover-color": surface2,
        "--active-color": pick(card.get("selected"), surface2),
        "--selected-color": rgba(accent, 0.28),
        "--input-bg": surface,
        "--accent-color": accent,
        "--accent-hover": pick(colors.get("primaryButton"), accent),
    }


def main():
    if not THEMES.is_dir() or not any(THEMES.glob("*.json")):
        sys.exit(f"themes submodule missing or empty at {THEMES}\n"
                 f"run: git submodule update --init themes")

    out = []
    skipped = []
    for path in sorted(glob.glob(str(THEMES / "*.json"))):
        name = os.path.basename(path)
        try:
            data = json.load(open(path))
        except Exception as exc:
            skipped.append((name, f"unreadable: {exc}"))
            continue
        colors = data.get("colors")
        if not isinstance(colors, dict):
            skipped.append((name, "no colors tree"))
            continue
        out.append({
            "name": data.get("themeName") or name.replace(".json", ""),
            "displayName": data.get("displayName") or data.get("themeName") or name,
            "icon": data.get("icon") or "",
            "tokens": build_tokens(colors),
        })

    body = json.dumps(out, separators=(",", ":"), ensure_ascii=False)
    OUT.write_text(
        "// GENERATED by scripts/build_keymap_themes.py from the MadnessThemes\n"
        "// submodule (themes/). Do not edit by hand -- rerun the script.\n"
        "// Each palette is pre-mapped to the keymap's CSS custom properties so\n"
        "// the browser does no colour maths and every surface consumes the same file.\n"
        f"window.KeymapThemes = {body};\n",
        encoding="utf-8",
    )
    print(f"wrote {OUT.relative_to(ROOT)}  ({len(out)} palettes, {len(body):,} bytes)")
    for t in out:
        print(f"  {t['icon'] or ' '} {t['displayName']}")
    if skipped:
        print(f"\nskipped {len(skipped)} file(s) with no colors tree:")
        for n, why in skipped[:6]:
            print(f"  {n}: {why}")


if __name__ == "__main__":
    main()
