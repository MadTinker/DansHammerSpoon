// Shared param-widget renderer for HammerGhost editors. Used by the popup editors
// (action_editor.js / condition_editor.js) AND the inline properties panel
// (app.js), so the same param def renders identically everywhere. Inlined ahead of
// those scripts (see editor_window.lua / webview.lua); exposed on window.HG so the
// later-inlined scripts can reach it.
//
// A param def is { type, required, default, options? }. Supported widget types:
//   text | number | select | textarea | hotkey
// (app / file pickers are added in a later phase; unknown types fall back to text.)
(function () {
    const HG = window.HG = window.HG || {};

    // Map a KeyboardEvent to a Hammerspoon key name. Returns null for a pure
    // modifier press (wait for the real key). hs.eventtap.keyStroke wants names
    // like "left"/"return"/"space"/"f5"/"a".
    const KEY_MAP = {
        ' ': 'space', 'Escape': 'escape', 'Enter': 'return', 'Tab': 'tab',
        'Backspace': 'delete', 'Delete': 'forwarddelete',
        'ArrowUp': 'up', 'ArrowDown': 'down', 'ArrowLeft': 'left', 'ArrowRight': 'right',
    };
    function normalizeKey(e) {
        const k = e.key;
        if (k === 'Meta' || k === 'Control' || k === 'Alt' || k === 'Shift') return null;
        if (KEY_MAP[k]) return KEY_MAP[k];
        return k.length === 1 ? k.toLowerCase() : k.toLowerCase();
    }

    // Read-only input that records a pressed chord ("cmd+shift+k"). Esc/Backspace
    // (with no modifier) clears it.
    function buildHotkeyInput() {
        const input = document.createElement('input');
        input.type = 'text';
        input.readOnly = true;
        input.className = 'hotkey-input';
        input.placeholder = 'click, then press a chord';
        input.addEventListener('keydown', (e) => {
            e.preventDefault();
            const bare = !e.metaKey && !e.ctrlKey && !e.altKey;
            if (bare && (e.key === 'Escape' || e.key === 'Backspace' || e.key === 'Delete')) {
                input.value = '';
                input.dispatchEvent(new Event('change', { bubbles: true }));
                return;
            }
            const mods = [];
            if (e.metaKey) mods.push('cmd');
            if (e.ctrlKey) mods.push('ctrl');
            if (e.altKey) mods.push('alt');
            if (e.shiftKey) mods.push('shift');
            const key = normalizeKey(e);
            if (!key) return; // modifier-only so far
            input.value = mods.concat(key).join('+');
            input.dispatchEvent(new Event('change', { bubbles: true }));
        });
        return input;
    }

    // Build the input element for one param def (no label/wrapper).
    function buildInput(param) {
        const type = param.type || 'text';
        let input;
        if (type === 'select') {
            input = document.createElement('select');
            (param.options || []).forEach((opt) => {
                const o = document.createElement('option');
                o.value = opt;
                o.textContent = opt;
                input.appendChild(o);
            });
        } else if (type === 'textarea') {
            input = document.createElement('textarea');
            input.rows = 6;
        } else if (type === 'hotkey') {
            input = buildHotkeyInput();
        } else {
            input = document.createElement('input');
            input.type = (type === 'number') ? 'number' : 'text';
        }
        input.dataset.paramType = type;
        return input;
    }

    // Render every param in `parameters` into `container` (cleared first), prefilled
    // from `values` (falling back to each def's `default`).
    HG.renderParams = function (container, parameters, values) {
        container.innerHTML = '';
        if (!parameters) return;
        values = values || {};
        Object.keys(parameters).forEach((name) => {
            const param = parameters[name];
            const group = document.createElement('div');
            group.className = 'form-group';

            const label = document.createElement('label');
            label.textContent = name;
            group.appendChild(label);

            const input = buildInput(param);
            input.name = name;
            input.required = !!param.required;

            const v = values[name];
            const initial = (v !== undefined && v !== null && v !== '')
                ? v
                : (param.default !== undefined ? param.default : undefined);
            if (initial !== undefined) input.value = initial;

            group.appendChild(input);
            container.appendChild(group);
        });
    };

    // Collect { name: value } from every named field in `container`.
    HG.collectParams = function (container) {
        const out = {};
        container.querySelectorAll('input, select, textarea').forEach((el) => {
            if (el.name) out[el.name] = el.value;
        });
        return out;
    };
})();
