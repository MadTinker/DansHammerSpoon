// --- Live event log (global so Lua's evaluateJavaScript can call them) ---
const LOG_MAX_ROWS = 300;

// Flatten a payload object into dotted token paths so each leaf can be shown as
// the exact {payload.x.y} string you'd type into an action param.
function flattenPayload(obj, prefix, out) {
    out = out || [];
    if (obj && typeof obj === 'object' && !Array.isArray(obj)) {
        Object.keys(obj).forEach(k => flattenPayload(obj[k], prefix + '.' + k, out));
    } else {
        out.push({ token: prefix, value: Array.isArray(obj) ? JSON.stringify(obj) : String(obj) });
    }
    return out;
}

// Build the expandable payload detail: one row per leaf, token + value.
function renderPayloadDetail(payload) {
    const detail = document.createElement('div');
    detail.className = 'log-payload';
    const rows = flattenPayload(payload, 'payload', []);
    if (rows.length === 0) {
        detail.textContent = 'No payload';
        return detail;
    }
    rows.forEach(r => {
        const line = document.createElement('div');
        line.className = 'log-token';
        const tok = document.createElement('span');
        tok.className = 'tok';
        tok.textContent = '{' + r.token + '}';
        line.appendChild(tok);
        line.appendChild(document.createTextNode(' = ' + r.value));
        detail.appendChild(line);
    });
    return detail;
}

// Toggle the payload detail for a log row (payload JSON stashed on data-payload).
function togglePayload(row) {
    const existing = row.querySelector('.log-payload');
    if (existing) { existing.remove(); return; }
    let payload = {};
    try { payload = JSON.parse(row.dataset.payload || '{}'); } catch (e) { /* leave {} */ }
    // hs.json encodes an empty payload as [] -> treat as no payload, not a token.
    if (Array.isArray(payload) && payload.length === 0) payload = {};
    row.appendChild(renderPayloadDetail(payload));
}

// Append one event row. entry = { seq, time, name, payload }. Auto-scrolls to the
// newest row when the view is already pinned to the bottom, so live tailing works
// but a user who has scrolled up to read history is not yanked back down.
window.appendLogEntry = (entry) => {
    const container = document.getElementById('log-entries');
    if (!container) return;

    const empty = container.querySelector('.log-empty');
    if (empty) empty.remove();

    const pinned = container.scrollTop + container.clientHeight >= container.scrollHeight - 4;

    const row = document.createElement('div');
    row.className = 'log-entry fresh';
    row.dataset.seq = entry.seq;
    row.dataset.payload = JSON.stringify(entry.payload || {});

    const time = document.createElement('span');
    time.className = 'log-time';
    time.textContent = entry.time;

    const name = document.createElement('span');
    name.className = 'log-name';
    name.textContent = entry.name;

    const toggle = document.createElement('button');
    toggle.className = 'log-toggle';
    toggle.title = 'Show payload tokens';
    toggle.textContent = '{}';

    row.appendChild(time);
    row.appendChild(name);
    row.appendChild(toggle);
    container.appendChild(row);

    // Cap DOM size by dropping the oldest rows.
    while (container.childElementCount > LOG_MAX_ROWS) {
        container.removeChild(container.firstElementChild);
    }

    if (pinned) container.scrollTop = container.scrollHeight;
};

window.clearLogEntries = () => {
    const container = document.getElementById('log-entries');
    if (container) container.innerHTML = '<div class="log-empty">No events yet.</div>';
};

document.addEventListener('DOMContentLoaded', () => {
    const treeContainer = document.getElementById('tree-container');
    const propertiesPanel = document.getElementById('properties-panel');

    // Clear button wipes both the DOM and the Lua-side ring buffer.
    const logClear = document.getElementById('log-clear');
    if (logClear) {
        logClear.addEventListener('click', () => {
            window.location.href = 'hammerspoon://clearLog';
        });
    }

    // Keep the log pinned to the newest entry on initial load.
    const logEntries = document.getElementById('log-entries');
    if (logEntries) {
        logEntries.scrollTop = logEntries.scrollHeight;
        // Click a log row to bind its event to the selected trigger; the {} button
        // reveals the event's payload tokens instead of binding.
        logEntries.addEventListener('click', (event) => {
            const row = event.target.closest('.log-entry');
            if (!row) return;
            if (event.target.closest('.log-toggle')) {
                togglePayload(row);
                return;
            }
            if (event.target.closest('.log-payload')) return; // interacting with detail, not binding
            const nameEl = row.querySelector('.log-name');
            if (nameEl) {
                window.location.href = `hammerspoon://bindEvent?name=${encodeURIComponent(nameEl.textContent)}`;
            }
        });
    }

    // Use event delegation for tree actions
    treeContainer.addEventListener('click', (event) => {
        const target = event.target;
        const itemElement = target.closest('.tree-item');
        if (!itemElement) {
            return;
        }

        const id = itemElement.dataset.id;

        if (target.matches('.disclosure')) {
            window.location.href = `hammerspoon://toggleExpand?id=${id}`;
        } else if (target.matches('.toggle-button')) {
            window.location.href = `hammerspoon://toggleItem?id=${id}`;
        } else if (target.matches('.run-button')) {
            window.location.href = `hammerspoon://runItem?id=${id}`;
        } else if (target.matches('.edit-button')) {
            window.location.href = `hammerspoon://editItem?id=${id}`;
        } else if (target.matches('.delete-button')) {
            if (confirm('Are you sure you want to delete this item?')) {
                window.location.href = `hammerspoon://deleteItem?id=${id}`;
            }
        } else {
            window.location.href = `hammerspoon://selectItem?id=${id}`;
        }
    });

    // --- Drag-to-reorder (delegated; HTML5 drag events bubble to the container) ---
    let dragSourceId = null;

    const clearDropMarkers = () => {
        treeContainer.querySelectorAll('.tree-item').forEach((el) => {
            el.classList.remove('drop-before', 'drop-after', 'drop-inside');
        });
    };

    // Decide where a drop lands relative to a row: inside a folder/sequence when
    // hovering its middle band, otherwise before/after by cursor vertical position.
    const dropPosition = (row, event) => {
        const isContainer = row.dataset.type === 'folder'
            || row.dataset.type === 'sequence'
            || row.dataset.type === 'trigger';
        const rect = row.getBoundingClientRect();
        const offset = event.clientY - rect.top;
        if (isContainer && offset > rect.height * 0.25 && offset < rect.height * 0.75) {
            return 'inside';
        }
        return offset < rect.height / 2 ? 'before' : 'after';
    };

    treeContainer.addEventListener('dragstart', (event) => {
        const row = event.target.closest('.tree-item');
        if (!row) return;
        dragSourceId = row.dataset.id;
        event.dataTransfer.effectAllowed = 'move';
        event.dataTransfer.setData('text/plain', dragSourceId);
    });

    treeContainer.addEventListener('dragover', (event) => {
        const row = event.target.closest('.tree-item');
        if (!row || !dragSourceId) return;
        event.preventDefault();
        event.dataTransfer.dropEffect = 'move';
        clearDropMarkers();
        row.classList.add('drop-' + dropPosition(row, event));
    });

    treeContainer.addEventListener('drop', (event) => {
        const row = event.target.closest('.tree-item');
        if (!row || !dragSourceId) return;
        event.preventDefault();
        const targetId = row.dataset.id;
        const position = dropPosition(row, event);
        clearDropMarkers();
        if (targetId !== dragSourceId) {
            window.location.href =
                `hammerspoon://moveItem?source=${dragSourceId}&target=${targetId}&position=${position}`;
        }
        dragSourceId = null;
    });

    treeContainer.addEventListener('dragend', () => {
        clearDropMarkers();
        dragSourceId = null;
    });

    // --- Resizable divider between the tree and properties panels ---
    // Sets tree-container's width (a style attribute), which survives the
    // innerHTML re-renders that refresh performs on the tree.
    const divider = document.getElementById('divider');
    if (divider) {
        let resizing = false;
        divider.addEventListener('mousedown', (event) => {
            resizing = true;
            divider.classList.add('dragging');
            document.body.style.cursor = 'col-resize';
            event.preventDefault();
        });
        document.addEventListener('mousemove', (event) => {
            if (!resizing) return;
            const min = 150;
            const max = window.innerWidth - 200;
            let width = event.clientX;
            if (width < min) width = min;
            if (width > max) width = max;
            treeContainer.style.width = width + 'px';
        });
        document.addEventListener('mouseup', () => {
            if (!resizing) return;
            resizing = false;
            divider.classList.remove('dragging');
            document.body.style.cursor = '';
        });
    }

    // Use event delegation for properties panel actions
    propertiesPanel.addEventListener('click', (event) => {
        const target = event.target;

        if (target.matches('#save-button')) {
            const id = target.dataset.id;
            const name = document.getElementById('name').value;
            const data = { id, name };
            const eventNameInput = document.getElementById('eventName');
            if (eventNameInput) data.eventName = eventNameInput.value;
            window.location.href = `hammerspoon://saveProperties?${encodeURIComponent(JSON.stringify(data))}`;
        } else if (target.matches('#cancel-button')) {
            window.location.href = 'hammerspoon://cancelEdit';
        }
    });
});
