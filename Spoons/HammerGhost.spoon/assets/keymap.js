// keymap.js — keyboard grid editor for hotkeys.json.
//
// Pure renderer. It never talks to a host directly: everything goes through
// window.KeymapTransport (see keymap_transport_hs.js), which is the only file
// that changes between the HammerGhost window, the artifact and the HTTP
// surface. Keep it that way — a stray hammerspoon:// in here forks the editor.
//
// The host pushes data in by calling window.Keymap.render(data).

(function () {
    'use strict';

    // ── keyboard geometry ───────────────────────────────────────────────────
    // ANSI layout in keyboard units: 1u is one alphanumeric cap, and the row
    // stagger falls out of the wide keys rather than being faked with padding.
    // Entries are one of:
    //   {k}   a bindable key. `k` is the Hammerspoon key name, so it must match
    //         what hotkeys.json stores ('Space', 'return', 'left', ...).
    //   {mod} a structural key. The modifiers this whole grid is LAYERED on
    //         cannot themselves be bound, but the board does not read as a
    //         keyboard without them, so they are drawn and made inert.
    //   {sp}  empty space, for the gaps in the function row.
    // `u` is width in units (default 1); `cap` overrides the printed legend.
    //
    // Any bound key missing from this layout is still rendered, in an "Other
    // keys" row, so a binding can never become invisible.
    var ROWS = [
        { keys: [
            { k: 'escape', cap: 'esc' }, { sp: 1 },
            { k: 'F1' }, { k: 'F2' }, { k: 'F3' }, { k: 'F4' }, { sp: 0.5 },
            { k: 'F5' }, { k: 'F6' }, { k: 'F7' }, { k: 'F8' }, { sp: 0.5 },
            { k: 'F9' }, { k: 'F10' }, { k: 'F11' }, { k: 'F12' }
        ] },
        { gap: true, keys: [
            { k: '`' }, { k: '1' }, { k: '2' }, { k: '3' }, { k: '4' }, { k: '5' },
            { k: '6' }, { k: '7' }, { k: '8' }, { k: '9' }, { k: '0' }, { k: '-' },
            { k: '=' }, { k: 'delete', cap: '⌫', u: 2 }
        ] },
        { keys: [
            { k: 'Tab', u: 1.5 },
            { k: 'q' }, { k: 'w' }, { k: 'e' }, { k: 'r' }, { k: 't' }, { k: 'y' },
            { k: 'u' }, { k: 'i' }, { k: 'o' }, { k: 'p' }, { k: '[' }, { k: ']' },
            { k: '\\', u: 1.5 }
        ] },
        { keys: [
            { mod: 'caps', u: 1.75 },
            { k: 'a' }, { k: 's' }, { k: 'd' }, { k: 'f' }, { k: 'g' }, { k: 'h' },
            { k: 'j' }, { k: 'k' }, { k: 'l' }, { k: ';' }, { k: "'" },
            { k: 'return', cap: '⏎', u: 2.25 }
        ] },
        { keys: [
            { mod: '⇧', u: 2.25 },
            { k: 'z' }, { k: 'x' }, { k: 'c' }, { k: 'v' }, { k: 'b' }, { k: 'n' },
            { k: 'm' }, { k: ',' }, { k: '.' }, { k: '/' },
            { mod: '⇧', u: 2.75 }
        ] },
        { keys: [
            { mod: '⌃', u: 1.25 }, { mod: '⌥', u: 1.25 }, { mod: '⌘', u: 1.25 },
            { k: 'Space', u: 6.25 },
            { mod: '⌘', u: 1.25 }, { mod: '⌥', u: 1.25 },
            { sp: 0.5 },
            { k: 'left', cap: '←' }, { k: 'up', cap: '↑' },
            { k: 'down', cap: '↓' }, { k: 'right', cap: '→' }
        ] }
    ];

    var CAPS = {
        'left': '←', 'right': '→', 'up': '↑', 'down': '↓',
        'return': '⏎', 'Space': 'Space', 'Tab': 'Tab', 'escape': 'esc', 'delete': '⌫'
    };

    var MOD_GLYPH = { cmd: '⌘', shift: '⇧', ctrl: '⌃', alt: '⌥', fn: 'fn' };

    // ── state ───────────────────────────────────────────────────────────────
    var data = { bindings: [], modifierSets: {}, actionTypes: {}, problems: {} };
    var layer = null;      // currently displayed modifier layer
    var selectedId = null; // binding id, or a synthetic "layer\u0000key" for a free slot
    var filter = '';
    var status = '';

    // ── helpers ─────────────────────────────────────────────────────────────

    function layerOf(binding) {
        return typeof binding.mods === 'string' ? binding.mods : binding.mods.join('+');
    }

    // Modifier list for a layer name: either a named set from hotkeys.json or a
    // literal "ctrl+cmd" style layer built from an explicit list.
    function modsOf(layerName) {
        if (data.modifierSets && data.modifierSets[layerName]) {
            return data.modifierSets[layerName];
        }
        return layerName.split('+');
    }

    function glyphs(layerName) {
        return modsOf(layerName).map(function (m) {
            return MOD_GLYPH[m] || m;
        }).join('');
    }

    function bindingAt(layerName, key) {
        for (var i = 0; i < data.bindings.length; i++) {
            var b = data.bindings[i];
            if (layerOf(b) === layerName && b.key === key) { return b; }
        }
        return null;
    }

    function layers() {
        var seen = {};
        var out = [];
        data.bindings.forEach(function (b) {
            var l = layerOf(b);
            if (!seen[l]) { seen[l] = 0; out.push(l); }
            seen[l] += 1;
        });
        // Named sets first (hammer, hyper, meta), then ad-hoc combos, so the
        // two layers holding ~125 of the bindings are always the first tabs.
        out.sort(function (a, b) {
            var an = data.modifierSets[a] ? 0 : 1;
            var bn = data.modifierSets[b] ? 0 : 1;
            if (an !== bn) { return an - bn; }
            return seen[b] - seen[a];
        });
        return out.map(function (l) { return { name: l, count: seen[l] }; });
    }

    function problemFor(binding) {
        return binding && data.problems ? data.problems[binding.id] : null;
    }

    function actionSummary(binding) {
        if (!binding) { return ''; }
        var a = binding.action || {};
        if (a.kind === 'call') {
            var args = (a.args && a.args.length)
                ? '(' + a.args.map(function (x) { return JSON.stringify(x); }).join(', ') + ')'
                : '()';
            return a.fn + args;
        }
        if (a.kind === 'action') { return a.actionType || '(no action type)'; }
        return 'unbound';
    }

    function matchesFilter(binding, key) {
        if (!filter) { return true; }
        var hay = [key, binding && binding.description, binding && actionSummary(binding)]
            .filter(Boolean).join(' ').toLowerCase();
        return hay.indexOf(filter) !== -1;
    }

    function el(tag, cls, text) {
        var n = document.createElement(tag);
        if (cls) { n.className = cls; }
        // textContent throughout: binding descriptions and notes are user data
        // and must never be parsed as markup.
        if (text !== undefined && text !== null) { n.textContent = text; }
        return n;
    }

    // ── rendering: header + layers ──────────────────────────────────────────

    function renderStats() {
        var node = document.getElementById('km-stats');
        node.textContent = '';
        var total = data.bindings.length;
        var disabled = data.bindings.filter(function (b) { return b.enabled === false; }).length;
        node.appendChild(document.createTextNode(total + ' bindings'));
        if (disabled) {
            node.appendChild(document.createTextNode(' · ' + disabled + ' disabled'));
        }
        var problems = Object.keys(data.problems || {}).length;
        if (problems) {
            var w = el('span', 'km-warn', ' · ⚠ ' + problems + ' problem' + (problems > 1 ? 's' : ''));
            node.appendChild(w);
        }
    }

    function renderLayers() {
        var host = document.getElementById('km-layers');
        host.textContent = '';
        layers().forEach(function (info) {
            var btn = el('button', 'km-layer' + (info.name === layer ? ' km-active' : ''));
            btn.appendChild(el('span', 'km-glyph', glyphs(info.name)));
            btn.appendChild(el('span', null, info.name));
            btn.appendChild(el('span', 'km-count', info.count));
            btn.addEventListener('click', function () {
                layer = info.name;
                selectedId = null;
                renderAll();
            });
            host.appendChild(btn);
        });
    }

    // ── rendering: the board ────────────────────────────────────────────────

    function keyNode(entry) {
        // A structural key: drawn for shape, never bindable, never clickable.
        if (entry.mod) {
            var slug = el('div', 'km-key km-mod');
            slug.style.setProperty('--w', entry.u || 1);
            slug.appendChild(el('span', 'km-cap', entry.mod));
            return slug;
        }

        var key = entry.k;
        var binding = bindingAt(layer, key);
        var cls = ['km-key'];

        if (!binding) {
            cls.push('km-free');
        } else {
            cls.push('km-bound');
            if (binding.placeholder) { cls.push('km-placeholder'); }
            if (binding.enabled === false) { cls.push('km-disabled'); }
            if (problemFor(binding)) { cls.push('km-broken'); }
        }
        if (!matchesFilter(binding, key)) { cls.push('km-dimmed'); }

        var id = binding ? binding.id : (layer + '\u0000' + key);
        if (id === selectedId) { cls.push('km-selected'); }

        var node = el('button', cls.join(' '));
        node.style.setProperty('--w', entry.u || 1);
        node.appendChild(el('span', 'km-cap', entry.cap || CAPS[key] || key));
        node.appendChild(el('span', 'km-desc',
            binding ? (binding.description || actionSummary(binding)) : ''));

        // No badge text on the cap. Every state it used to name is already
        // encoded visually -- struck-through legend for disabled, red for a
        // broken target, italic for a placeholder -- and the specifics are in
        // the hover title and the detail panel. A real keycap carries a legend,
        // not a status line, and the space is better spent on the description.

        // The full note/description is worth having on hover; the tile itself
        // only has room for three lines.
        if (binding) {
            node.title = [binding.description, actionSummary(binding), binding.note]
                .filter(Boolean).join('\n');
        }

        node.addEventListener('click', function () {
            selectedId = id;
            renderAll();
        });
        return node;
    }

    function renderBoard() {
        var host = document.getElementById('km-board');
        host.textContent = '';
        if (!layer) { return; }

        var placed = {};
        ROWS.forEach(function (row) {
            var r = el('div', 'km-row' + (row.gap ? ' km-gap' : ''));
            row.keys.forEach(function (entry) {
                if (entry.sp) {
                    var spacer = el('div', 'km-spacer');
                    spacer.style.setProperty('--w', entry.sp);
                    r.appendChild(spacer);
                    return;
                }
                if (entry.k) { placed[entry.k] = true; }
                r.appendChild(keyNode(entry));
            });
            host.appendChild(r);
        });

        // Any bound key the layout above does not know about still gets a tile.
        var extras = data.bindings
            .filter(function (b) { return layerOf(b) === layer && !placed[b.key]; })
            .map(function (b) { return b.key; });
        if (extras.length) {
            host.appendChild(el('div', 'km-stats', 'Other keys'));
            var r2 = el('div', 'km-row km-gap');
            extras.forEach(function (key) { r2.appendChild(keyNode({ k: key })); });
            host.appendChild(r2);
        }
    }

    // ── rendering: the detail editor ────────────────────────────────────────

    function field(labelText, control) {
        var wrap = el('div', 'km-field');
        wrap.appendChild(el('label', null, labelText));
        wrap.appendChild(control);
        return wrap;
    }

    function input(value) {
        var i = document.createElement('input');
        i.type = 'text';
        i.value = value === undefined || value === null ? '' : value;
        return i;
    }

    function textarea(value, rows) {
        var t = document.createElement('textarea');
        t.rows = rows || 3;
        t.value = value === undefined || value === null ? '' : value;
        return t;
    }

    function select(options, current) {
        var s = document.createElement('select');
        options.forEach(function (opt) {
            var o = document.createElement('option');
            o.value = opt.value;
            o.textContent = opt.label;
            if (opt.value === current) { o.selected = true; }
            s.appendChild(o);
        });
        return s;
    }

    function renderDetail() {
        var host = document.getElementById('km-detail');
        host.textContent = '';

        if (!selectedId) {
            host.appendChild(el('div', 'km-empty',
                'Select a key to see or change what it does.'));
            return;
        }

        var binding = null;
        var key, layerName;
        for (var i = 0; i < data.bindings.length; i++) {
            if (data.bindings[i].id === selectedId) { binding = data.bindings[i]; break; }
        }
        if (binding) {
            key = binding.key;
            layerName = layerOf(binding);
        } else {
            // A free slot: synthetic id "layer\u0000key".
            var parts = selectedId.split('\u0000');
            layerName = parts[0];
            key = parts[1];
        }

        var head = el('div', 'km-detail-head');
        head.appendChild(el('span', 'km-combo', glyphs(layerName) + ' ' + (CAPS[key] || key)));
        head.appendChild(el('span', 'km-stats',
            binding ? binding.id : 'unbound — filling this in creates a binding'));
        host.appendChild(head);

        var problem = problemFor(binding);
        if (problem) {
            host.appendChild(el('div', 'km-note km-note-error', problem));
        }
        if (binding && binding.note) {
            host.appendChild(el('div', 'km-note', binding.note));
        }

        var action = (binding && binding.action) || { kind: 'call' };

        var fDesc = input(binding ? binding.description : '');
        host.appendChild(field('Description', fDesc));

        var kindSel = select([
            { value: 'call', label: 'call — a function in the loaded modules' },
            { value: 'action', label: 'action — a HammerGhost action type' },
            { value: 'none', label: 'none — reserve the key, do nothing' }
        ], action.kind || 'call');
        host.appendChild(field('Action', kindSel));

        // -- call fields
        var callWrap = el('div');
        var fFn = input(action.fn || '');
        fFn.placeholder = 'e.g. WindowManager.applyLayout  or  spoon.KineticLatch:toggle';
        callWrap.appendChild(field('Function path', fFn));
        var fArgs = input(action.args ? JSON.stringify(action.args) : '');
        fArgs.placeholder = '[] — JSON array, e.g. ["topLeft"]';
        callWrap.appendChild(field('Arguments', fArgs));
        host.appendChild(callWrap);

        // -- action fields
        var actWrap = el('div');
        var typeNames = Object.keys(data.actionTypes || {}).sort();
        var typeSel = select(
            [{ value: '', label: '— pick an action type —' }].concat(
                typeNames.map(function (n) {
                    return { value: n, label: (data.actionTypes[n].name || n) + ' (' + n + ')' };
                })
            ),
            action.actionType || ''
        );
        actWrap.appendChild(field('Action type', typeSel));
        var fParams = textarea(action.params ? JSON.stringify(action.params, null, 2) : '{}', 4);
        actWrap.appendChild(field('Parameters (JSON)', fParams));
        host.appendChild(actWrap);

        function syncKind() {
            var k = kindSel.value;
            callWrap.className = k === 'call' ? '' : 'km-hide';
            actWrap.className = k === 'action' ? '' : 'km-hide';
        }
        kindSel.addEventListener('change', syncKind);
        syncKind();

        // -- flags
        var flags = el('div', 'km-cols');
        var enabledBox = document.createElement('input');
        enabledBox.type = 'checkbox';
        enabledBox.checked = !binding || binding.enabled !== false;
        var l1 = el('label', 'km-check');
        l1.appendChild(enabledBox);
        l1.appendChild(document.createTextNode('Enabled'));
        flags.appendChild(l1);

        var repeatBox = document.createElement('input');
        repeatBox.type = 'checkbox';
        repeatBox.checked = !!(binding && binding.noRepeat);
        var l2 = el('label', 'km-check');
        l2.appendChild(repeatBox);
        l2.appendChild(document.createTextNode('Suppress key repeat'));
        flags.appendChild(l2);
        host.appendChild(flags);

        // -- buttons
        var actions = el('div', 'km-actions');
        var saveBtn = el('button', 'km-btn km-primary', 'Save');
        actions.appendChild(saveBtn);

        if (binding) {
            var delBtn = el('button', 'km-btn km-danger', 'Delete');
            delBtn.addEventListener('click', function () {
                setStatus('Deleting ' + binding.id + '…');
                window.KeymapTransport.deleteBinding(binding.id);
                selectedId = null;
            });
            actions.appendChild(delBtn);
        }

        var statusNode = el('span', 'km-status', status);
        actions.appendChild(statusNode);
        host.appendChild(actions);

        saveBtn.addEventListener('click', function () {
            var kind = kindSel.value;
            var newAction = { kind: kind };

            if (kind === 'call') {
                var fn = fFn.value.trim();
                if (!fn) { return setStatus('A call needs a function path.', statusNode); }
                newAction.fn = fn;
                var rawArgs = fArgs.value.trim();
                if (rawArgs) {
                    var parsedArgs;
                    try { parsedArgs = JSON.parse(rawArgs); } catch (e) {
                        return setStatus('Arguments must be JSON: ' + e.message, statusNode);
                    }
                    if (!Array.isArray(parsedArgs)) {
                        return setStatus('Arguments must be a JSON array.', statusNode);
                    }
                    if (parsedArgs.length) { newAction.args = parsedArgs; }
                }
            } else if (kind === 'action') {
                if (!typeSel.value) { return setStatus('Pick an action type.', statusNode); }
                newAction.actionType = typeSel.value;
                var rawParams = fParams.value.trim() || '{}';
                try { newAction.params = JSON.parse(rawParams); } catch (e2) {
                    return setStatus('Parameters must be JSON: ' + e2.message, statusNode);
                }
                if (typeof newAction.params !== 'object' || Array.isArray(newAction.params)) {
                    return setStatus('Parameters must be a JSON object.', statusNode);
                }
            }

            var payload = {
                id: binding ? binding.id : (layerName + '+' + key),
                mods: data.modifierSets[layerName] ? layerName : modsOf(layerName),
                key: key,
                description: fDesc.value.trim() || key,
                action: newAction,
                enabled: enabledBox.checked
            };
            if (repeatBox.checked) { payload.noRepeat = true; }
            // Preserve provenance and hand-written notes across an edit.
            if (binding) {
                if (binding.note) { payload.note = binding.note; }
                if (binding.migratedFrom) { payload.migratedFrom = binding.migratedFrom; }
                if (binding.placeholder && newAction.fn === 'tempFunction') {
                    payload.placeholder = true;
                }
            }

            setStatus(window.KeymapTransport.appliesLive ? 'Saving and applying…' : 'Saving…',
                statusNode);
            window.KeymapTransport.saveBinding(payload);
        });
    }

    function setStatus(text, node) {
        status = text;
        if (node) { node.textContent = text; }
        return false;
    }

    // ── top level ───────────────────────────────────────────────────────────

    function renderAll() {
        renderStats();
        renderLayers();
        renderBoard();
        renderDetail();
    }

    window.Keymap = {
        render: function (incoming) {
            data = incoming || {};
            data.bindings = data.bindings || [];
            data.modifierSets = data.modifierSets || {};
            data.actionTypes = data.actionTypes || {};
            data.problems = data.problems || {};

            var available = layers();
            if (!layer || !available.some(function (l) { return l.name === layer; })) {
                layer = available.length ? available[0].name : null;
            }
            status = '';
            renderAll();
        },
        // Let the host report a save result without re-sending the whole table.
        setStatus: function (text) {
            status = text;
            var node = document.querySelector('.km-status');
            if (node) { node.textContent = text; }
        }
    };

    document.getElementById('km-search').addEventListener('input', function (e) {
        filter = e.target.value.trim().toLowerCase();
        renderBoard();
    });

    document.addEventListener('keydown', function (e) {
        if (e.key === 'Escape') {
            if (document.activeElement === document.getElementById('km-search')) { return; }
            selectedId = null;
            renderAll();
        }
    });

    // Page-load handshake, mirroring the other HammerGhost editors: the page
    // asks, the host answers by calling window.Keymap.render().
    window.KeymapTransport.requestData();
}());
