// keymap_transport_artifact.js
//
// The artifact surface's transport. Sibling of keymap_transport_hs.js: same
// contract, different host. keymap.js is identical in both.
//
// WHAT THIS SURFACE CANNOT DO, and why the wording differs: an artifact runs
// sandboxed on claude.ai, where the CSP blocks fetch/XHR to every host —
// 127.0.0.1 included. It cannot reach Hammerspoon. No runtime capability
// changes that; mcp reaches claude.ai connectors, never the local machine.
// So this is an offline editor with one-hop sync: edit anywhere, then export
// hotkeys.json (or have Claude read the store back) and drop it on the Mac,
// where HotkeyBinder.reload() applies it. appliesLive is false so the shared
// renderer stops promising edits take effect immediately.

(function () {
    'use strict';

    var DOC = 'keymap/current';
    var dbPromise = null;
    var table = null;   // last known table, so a save can rewrite the whole doc
    var unavailable = false;

    function db() {
        if (!dbPromise) {
            dbPromise = (window.claude && window.claude.use)
                ? window.claude.use('db')
                : Promise.resolve(null);
        }
        return dbPromise;
    }

    function empty() {
        return { bindings: [], modifierSets: {}, actionTypes: {}, problems: {} };
    }

    function paint() {
        window.Keymap.render(table || empty());
    }

    function note(text) {
        var el = document.getElementById('km-notice');
        if (el) { el.textContent = text; }
    }

    // A save rewrites the whole document. The table is ~26 KB against a 256 KiB
    // per-document limit, and it is the same shape as the file on disk, so one
    // document keeps the artifact and hotkeys.json trivially interchangeable.
    function persist(message) {
        return db().then(function (store) {
            if (!store) { return; }
            return store.doc(DOC).set(table).then(function () {
                window.Keymap.setStatus(message);
            });
        }).catch(function (err) {
            window.Keymap.setStatus('Could not save: ' + (err && err.message ? err.message : err));
        });
    }

    window.KeymapTransport = {
        name: 'artifact',
        appliesLive: false,

        requestData: function () {
            db().then(function (store) {
                if (!store) {
                    unavailable = true;
                    note('This view cannot reach the artifact store, so there is nothing to edit. '
                        + 'Open the artifact from your own gallery.');
                    paint();
                    return;
                }
                // Live subscription: two devices editing the same keymap stay in
                // step, and a seed written from Claude Code appears without a
                // reload.
                store.doc(DOC).onSnapshot(function (snap) {
                    table = snap.exists ? snap.data : null;
                    if (!table) {
                        note('The store is empty. Ask Claude to seed it from your hotkeys.json.');
                    }
                    paint();
                }, function (err) {
                    note('Store error: ' + (err && err.message ? err.message : err));
                });
            });
        },

        saveBinding: function (binding) {
            if (unavailable || !table) {
                return window.Keymap.setStatus('No store to save into.');
            }
            var replaced = false;
            for (var i = 0; i < table.bindings.length; i++) {
                if (table.bindings[i].id === binding.id) {
                    table.bindings[i] = binding;
                    replaced = true;
                    break;
                }
            }
            if (!replaced) { table.bindings.push(binding); }
            persist('Saved ' + binding.id + ' to the artifact. Export to apply it on the Mac.');
        },

        deleteBinding: function (id) {
            if (unavailable || !table) {
                return window.Keymap.setStatus('No store to save into.');
            }
            table.bindings = table.bindings.filter(function (b) { return b.id !== id; });
            persist('Deleted ' + id + '. Export to apply it on the Mac.');
        },

        reload: function () {
            db().then(function (store) {
                if (!store) { return; }
                return store.doc(DOC).get().then(function (snap) {
                    table = snap.exists ? snap.data : null;
                    paint();
                    window.Keymap.setStatus('Reloaded from the store.');
                });
            });
        }
    };

    // Export the table as hotkeys.json. Not part of the transport contract —
    // it is this surface's answer to "how does the edit reach the machine".
    window.KeymapExport = {
        available: false,

        init: function (button) {
            if (!button) { return; }
            if (!(window.claude && window.claude.use)) { button.hidden = true; return; }
            window.claude.use('downloads').then(function (downloads) {
                if (!downloads) { button.hidden = true; return; }
                window.KeymapExport.available = true;
                button.addEventListener('click', function () {
                    if (!table) { return note('Nothing to export yet.'); }
                    // Strip the fields the artifact adds for display; what lands
                    // on disk must be exactly what HotkeyBinder expects to read.
                    var doc = {
                        version: table.version || 1,
                        modifierSets: table.modifierSets || {},
                        bindings: table.bindings || []
                    };
                    downloads.save({
                        filename: 'hotkeys.json',
                        data: JSON.stringify(doc, null, 2) + '\n'
                    }).then(function () {
                        // The apply hotkey is the apostrophe key, so this string
                        // is double-quoted on purpose.
                        note("Saved. Drop it in ~/.hammerspoon and press ⌘⌃⌥' to apply.");
                    }).catch(function (err) {
                        if (err && err.code === 'declined') { return; }
                        note('Export failed: ' + (err && err.message ? err.message : err));
                    });
                });
            });
        }
    };
}());
