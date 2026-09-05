// keymap_transport_hs.js
//
// THE ONLY SURFACE-SPECIFIC FILE IN THE KEYMAP EDITOR.
//
// keymap.js is a pure renderer: it reads a binding table, draws the keyboard,
// and calls back through window.KeymapTransport. Swapping this one file moves
// the same editor to another host:
//
//   this file          HammerGhost webview  -> hammerspoon:// URL bridge
//   Phase 2 (artifact) claude.ai artifact    -> claude.use("db") / downloads
//   Phase 3 (http)     browser tab           -> fetch('/api/bindings')
//
// Contract:
//   requestData()        ask the host for the table. The host answers
//                        asynchronously by calling window.Keymap.render(data).
//                        (Push, not promise: the Hammerspoon bridge is one-way
//                        per navigation, and a promise-shaped API here would be
//                        a lie the other two surfaces would have to fake.)
//   saveBinding(binding) persist + apply one binding.
//   deleteBinding(id)    remove one binding.
//   reload()             re-read from the store and re-apply.
//
// The host is expected to call window.Keymap.render() again after any mutation,
// so the page never guesses whether a write succeeded.

(function () {
    'use strict';

    // Navigating to hammerspoon://… is how the page talks to Lua: the webview's
    // policyCallback intercepts it, hands the URL to the handler and returns
    // false so the page never actually navigates (see editor_window.lua).
    // Assignments are queued rather than fired back-to-back — two synchronous
    // writes to window.location.href in the same tick and the first one is
    // dropped, which silently loses a save.
    var queue = [];
    var draining = false;

    function drain() {
        if (!queue.length) {
            draining = false;
            return;
        }
        draining = true;
        var url = queue.shift();
        window.location.href = url;
        setTimeout(drain, 0);
    }

    function send(cmd, payload) {
        var url = 'hammerspoon://' + cmd;
        if (payload !== undefined) {
            url += '?' + encodeURIComponent(JSON.stringify(payload));
        }
        queue.push(url);
        if (!draining) { drain(); }
    }

    window.KeymapTransport = {
        name: 'hammerghost',
        // Whether the host can apply a change to the live keyboard. The artifact
        // surface cannot (it is sandboxed away from the machine), so the editor
        // words its confirmation differently there.
        appliesLive: true,

        requestData: function () { send('keymapData'); },
        saveBinding: function (binding) { send('keymapSave', binding); },
        deleteBinding: function (id) { send('keymapDelete', { id: id }); },
        reload: function () { send('keymapReload'); }
    };
}());
