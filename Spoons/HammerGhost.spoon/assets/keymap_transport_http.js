// keymap_transport_http.js
//
// The loopback-HTTP surface's transport. Third sibling of
// keymap_transport_hs.js and keymap_transport_artifact.js: same contract,
// different host. keymap.js is identical in all three.
//
// This surface talks to hs.httpserver running inside Hammerspoon on
// 127.0.0.1, so unlike the artifact it CAN apply changes to the live keyboard.
//
// Auth: the server injects window.KEYMAP_TOKEN into the page it serves, and
// every /api/ call carries it in the X-Keymap-Token header. Two things follow
// from putting it in a custom header rather than the URL: it stays out of
// browser history and Referer, and a cross-origin request carrying it must
// clear a CORS preflight, which the server never answers. So a web page the
// user happens to be visiting cannot drive this API, even though it can reach
// the port.

(function () {
    'use strict';

    function api(method, path, payload) {
        var opts = {
            method: method,
            headers: { 'X-Keymap-Token': window.KEYMAP_TOKEN || '' }
        };
        // Always give a POST a body, even an empty object. hs.httpserver rejects
        // a bodyless POST with its own 400 before the request ever reaches the
        // Lua callback, which looks like a broken endpoint rather than a
        // malformed request.
        if (payload !== undefined || method === 'POST') {
            opts.headers['Content-Type'] = 'application/json';
            opts.body = JSON.stringify(payload === undefined ? {} : payload);
        }
        return fetch(path, opts).then(function (res) {
            return res.text().then(function (text) {
                if (!res.ok) {
                    throw new Error('HTTP ' + res.status + (text ? ': ' + text : ''));
                }
                return text ? JSON.parse(text) : {};
            });
        });
    }

    function note(text) {
        var el = document.getElementById('km-notice');
        if (el) { el.textContent = text; }
    }

    function fail(err) {
        var msg = err && err.message ? err.message : String(err);
        window.Keymap.setStatus(msg);
        note('Hammerspoon is not answering (' + msg + '). Is it still running, '
            + 'and is the keymap server started?');
    }

    // The server answers every mutation with the full table, so the page never
    // has to guess whether a write landed -- same rule as the other surfaces.
    function paint(data) {
        window.Keymap.render(data);
        note('');
    }

    window.KeymapTransport = {
        name: 'http',
        appliesLive: true,

        requestData: function () {
            api('GET', '/api/bindings').then(paint).catch(fail);
        },

        saveBinding: function (binding) {
            api('POST', '/api/binding', binding).then(function (res) {
                paint(res.table);
                window.Keymap.setStatus(res.message || ('Saved ' + binding.id + '.'));
            }).catch(fail);
        },

        deleteBinding: function (id) {
            api('POST', '/api/binding/delete', { id: id }).then(function (res) {
                paint(res.table);
                window.Keymap.setStatus(res.message || ('Deleted ' + id + '.'));
            }).catch(fail);
        },

        reload: function () {
            api('POST', '/api/reload').then(function (res) {
                paint(res.table);
                window.Keymap.setStatus(res.message || 'Reloaded.');
            }).catch(fail);
        }
    };
}());
