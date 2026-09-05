// keymap_theme.js — applies a Madness palette to the keymap editor.
//
// The palettes come from the MadnessThemes submodule (themes/), pre-mapped to
// this editor's CSS custom properties by scripts/build_keymap_themes.py and
// delivered as window.KeymapThemes. Nothing here does colour maths; it only
// sets custom properties, so the whole page re-themes without a re-render.
//
// "Workshop" is the palette baked into the page's own stylesheet. Selecting it
// REMOVES the inline properties rather than writing a competing set, so the
// stylesheet's :root (and its light/dark handling) takes back over cleanly.

(function () {
    'use strict';

    var KEY = 'keymap.theme';
    var BUILT_IN = 'workshop';
    var current = BUILT_IN;

    function palettes() {
        return Array.isArray(window.KeymapThemes) ? window.KeymapThemes : [];
    }

    function find(name) {
        var all = palettes();
        for (var i = 0; i < all.length; i++) {
            if (all[i].name === name) { return all[i]; }
        }
        return null;
    }

    // Every token any palette sets, so switching palettes cannot leave a
    // property behind from the previous one.
    function allTokenNames() {
        var seen = {};
        palettes().forEach(function (p) {
            Object.keys(p.tokens || {}).forEach(function (k) { seen[k] = true; });
        });
        return Object.keys(seen);
    }

    function clear(root) {
        allTokenNames().forEach(function (k) { root.style.removeProperty(k); });
    }

    function apply(name) {
        var root = document.documentElement;
        var theme = find(name);
        clear(root);
        if (theme) {
            Object.keys(theme.tokens).forEach(function (k) {
                root.style.setProperty(k, theme.tokens[k]);
            });
            current = name;
        } else {
            current = BUILT_IN;
        }
        // Storage is a convenience, not state the editor depends on: a private
        // window, or a webview with no usable origin, throws on access.
        try { window.localStorage.setItem(KEY, current); } catch (e) { /* fine */ }
        return current;
    }

    function saved() {
        try { return window.localStorage.getItem(KEY); } catch (e) { return null; }
    }

    window.KeymapTheme = {
        current: function () { return current; },
        apply: apply,

        // Fill a <select> with the available palettes and wire it up. Hides the
        // control entirely when the generated palette file is absent, rather
        // than offering an empty picker.
        init: function (select) {
            if (!select) { return; }
            var all = palettes();
            if (!all.length) { select.hidden = true; return; }

            var opt = document.createElement('option');
            opt.value = BUILT_IN;
            opt.textContent = 'Workshop';
            select.appendChild(opt);

            all.forEach(function (p) {
                var o = document.createElement('option');
                o.value = p.name;
                o.textContent = (p.icon ? p.icon + '  ' : '') + p.displayName;
                select.appendChild(o);
            });

            var start = saved();
            if (start && (start === BUILT_IN || find(start))) {
                apply(start);
                select.value = start;
            } else {
                select.value = BUILT_IN;
            }

            select.addEventListener('change', function () { apply(select.value); });
        }
    };

    // Self-initialise rather than relying on a trailing <script> in the page.
    // The HammerGhost webview loses that tag: editor_window inlines the asset
    // scripts by string substitution and WKWebView's parser then drops the
    // following inline block, so the picker rendered empty there while working
    // on the other two surfaces. Wiring it from here removes the tag entirely.
    // Idempotent: init() bails on a select it has already filled.
    function boot() {
        var select = document.getElementById('km-theme');
        if (select && !select.options.length) { window.KeymapTheme.init(select); }
    }
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', boot);
    } else {
        boot();
    }
}());
