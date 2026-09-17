// padforge.js -- renders the pad grid and talks to Lua via hammerspoon://.
//
// One file, one surface (a Hammerspoon window), unlike BindForge's
// multi-surface split -- there is no browser-tab or artifact version of this
// editor, so a transport abstraction would be a layer with nothing on the
// other side of it.

(function () {
    'use strict';

    // Same "queue navigations, don't fire them back to back" fix as
    // BindForge: two synchronous window.location.href writes in one tick and
    // the first is silently dropped.
    var queue = [];
    var draining = false;
    function drain() {
        if (!queue.length) { draining = false; return; }
        draining = true;
        window.location.href = queue.shift();
        setTimeout(drain, 0);
    }
    function send(cmd, payload) {
        var url = 'hammerspoon://' + cmd;
        if (payload !== undefined) { url += '?' + encodeURIComponent(JSON.stringify(payload)); }
        queue.push(url);
        if (!draining) { drain(); }
    }

    var data = null;        // last payload from Lua
    var activeMode = null;  // e.g. "K_2"
    var editing = null;     // key name currently open in the editor panel

    var MOD_LIST = [
        { id: 'ctrl', label: '⌃ Control' },
        { id: 'alt', label: '⌥ Option' },
        { id: 'shift', label: '⇧ Shift' },
        { id: 'cmd', label: '⌘ Command' },
    ];

    function el(tag, attrs, children) {
        var node = document.createElement(tag);
        for (var k in attrs || {}) {
            if (k === 'class') node.className = attrs[k];
            else if (k === 'text') node.textContent = attrs[k];
            else if (k.indexOf('on') === 0) node.addEventListener(k.slice(2), attrs[k]);
            else node.setAttribute(k, attrs[k]);
        }
        (children || []).forEach(function (c) { if (c) node.appendChild(c); });
        return node;
    }

    function renderBar() {
        document.getElementById('pf-path').textContent = data.loaded
            ? data.path
            : (data.error ? ('Error: ' + data.error) : 'No file loaded');
        document.getElementById('pf-reveal').disabled = !data.loaded;
        document.getElementById('pf-reload').disabled = !data.loaded;
    }

    function renderTabs() {
        var host = document.getElementById('pf-tabs');
        host.innerHTML = '';
        if (!data.loaded) return;
        data.modes.forEach(function (mode) {
            host.appendChild(el('div', {
                class: 'pf-tab' + (mode === activeMode ? ' active' : ''),
                text: data.modeLabels[mode] || mode,
                onclick: function () { activeMode = mode; editing = null; renderAll(); },
            }));
        });
    }

    function renderGrid() {
        var host = document.getElementById('pf-grid');
        host.innerHTML = '';
        if (!data.loaded || !activeMode) return;

        var modeData = data.data[activeMode] || {};
        var order = data.fixedKeys.slice(0, 2) // K1, K2 up top like the real pad
            .concat(data.editableKeys)
            .concat(data.fixedKeys.slice(2)); // ring last

        order.forEach(function (keyName) {
            var k = modeData[keyName] || {};
            var box;
            if (k.fixed) {
                box = el('div', { class: 'pf-key fixed' }, [
                    el('div', { class: 'pf-key-name', text: keyName }),
                    el('div', { class: 'pf-key-combo empty', text: 'firmware-fixed' }),
                ]);
            } else {
                var comboText = k.display || '(unassigned)';
                var children = [
                    el('div', { class: 'pf-key-name', text: keyName }),
                    el('div', { class: 'pf-key-combo' + (k.display ? '' : ' empty'), text: comboText }),
                ];
                if (k.custom && !k.recognized) {
                    children.push(el('div', { class: 'pf-key-unrecognized', text: 'not a simple keystroke -- edit in XPPen app' }));
                }
                box = el('div', {
                    class: 'pf-key' + (editing === keyName ? ' selected' : ''),
                    onclick: function () { editing = keyName; renderAll(); },
                }, children);
            }
            host.appendChild(box);
        });
    }

    function renderEditor() {
        var host = document.getElementById('pf-editor');
        host.innerHTML = '';
        if (!editing || !data.loaded) { host.hidden = true; return; }
        host.hidden = false;

        var k = (data.data[activeMode] || {})[editing] || {};
        var currentMods = [];
        if (k.encoded) {
            // Best-effort: infer which modifiers are already set from the
            // display string, since encoded pairs don't self-label which
            // half is a modifier.
            ['ctrl', 'alt', 'shift', 'cmd'].forEach(function (m) {
                var glyph = { ctrl: 'Control', alt: 'Option', shift: 'Shift', cmd: 'Command' }[m];
                if (k.display && k.display.indexOf(glyph) !== -1) currentMods.push(m);
            });
        }

        var modBoxes = MOD_LIST.map(function (m) {
            var cb = el('input', { type: 'checkbox' });
            cb.checked = currentMods.indexOf(m.id) !== -1;
            cb.dataset.mod = m.id;
            return el('label', {}, [cb, document.createTextNode(m.label)]);
        });

        var keyInput = el('input', { type: 'text', placeholder: 'g, f5, return, down, space…' });
        // Best-effort seed from the display string's last token.
        if (k.display) {
            var last = k.display.split('+').pop();
            var GLYPH_BACK = { '↵': 'return', '⎋': 'escape', '↑': 'up', '↓': 'down', '←': 'left', '→': 'right' };
            keyInput.value = GLYPH_BACK[last] || last.toLowerCase();
        }

        var labelInput = el('input', { type: 'text', placeholder: '(defaults to the combo itself)' });

        var reuseSelect = el('select', {}, [el('option', { value: '', text: '— reuse an existing Hammerspoon shortcut —' })]);
        (data.hotkeyChoices || []).forEach(function (h, i) {
            reuseSelect.appendChild(el('option', { value: String(i), text: h.label }));
        });
        reuseSelect.addEventListener('change', function () {
            if (reuseSelect.value === '') return;
            var h = data.hotkeyChoices[Number(reuseSelect.value)];
            modBoxes.forEach(function (label) {
                var cb = label.querySelector('input');
                cb.checked = h.mods.indexOf(cb.dataset.mod) !== -1;
            });
            keyInput.value = h.key.toLowerCase();
        });

        function doSave() {
            var mods = modBoxes
                .map(function (label) { return label.querySelector('input'); })
                .filter(function (cb) { return cb.checked; })
                .map(function (cb) { return cb.dataset.mod; });
            var baseKey = keyInput.value.trim();
            if (!baseKey) { setStatus('Pick a key first.'); return; }
            send('saveKey', { mode: activeMode, key: editing, mods: mods, baseKey: baseKey, label: labelInput.value.trim() });
        }

        host.appendChild(el('div', { class: 'pf-editor-title', text: 'Edit ' + editing + ' — mode ' + (data.modeLabels[activeMode] || activeMode) }));
        host.appendChild(el('div', { class: 'pf-row' }, [el('label', { class: 'pf-field-label', text: 'Reuse:' }), reuseSelect]));
        host.appendChild(el('div', { class: 'pf-mods' }, modBoxes));
        host.appendChild(el('div', { class: 'pf-row' }, [el('label', { class: 'pf-field-label', text: 'Key:' }), keyInput]));
        host.appendChild(el('div', { class: 'pf-row' }, [el('label', { class: 'pf-field-label', text: 'Label:' }), labelInput]));
        host.appendChild(el('div', { class: 'pf-hint', text: 'Save rewrites this one node in the file. Re-import it in the XPPen app afterward to push it to the pad.' }));
        host.appendChild(el('div', { class: 'pf-editor-actions' }, [
            el('button', { text: 'Cancel', onclick: function () { editing = null; renderAll(); } }),
            el('button', { class: 'pf-primary', text: 'Save', onclick: doSave }),
        ]));
    }

    function renderAll() {
        renderBar();
        renderTabs();
        renderGrid();
        renderEditor();
    }

    function setStatus(text) {
        document.getElementById('pf-status').textContent = text;
    }

    window.PadForge = {
        render: function (payload) {
            data = payload;
            if (data.loaded && !activeMode) activeMode = data.modes[0];
            if (!data.loaded) { activeMode = null; editing = null; }
            renderAll();
        },
        setStatus: setStatus,
    };

    document.getElementById('pf-open').addEventListener('click', function () { send('pickFile'); });
    document.getElementById('pf-reveal').addEventListener('click', function () { send('revealFinder'); });
    document.getElementById('pf-reload').addEventListener('click', function () { editing = null; send('reload'); });

    send('padData');
}());
