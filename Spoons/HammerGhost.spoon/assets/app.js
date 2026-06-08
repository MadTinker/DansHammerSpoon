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
    const treeColumn = document.getElementById('tree-column');
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

    // Decide where a drop lands relative to a row: "inside" a container (folder or
    // trigger -- the types that RUN their children) when hovering its middle band,
    // otherwise before/after by cursor vertical position. A sequence is NOT a drop
    // container: it runs its steps, not its children, so an "inside" drop there would
    // make an inert child (same reason the context menu's Add is folder/trigger only).
    const dropPosition = (row, event) => {
        const isContainer = row.dataset.type === 'folder' || row.dataset.type === 'trigger';
        const rect = row.getBoundingClientRect();
        const offset = event.clientY - rect.top;
        if (isContainer && offset > rect.height * 0.25 && offset < rect.height * 0.75) {
            return 'inside';
        }
        return offset < rect.height / 2 ? 'before' : 'after';
    };

    // A node can't be dropped onto itself or into its own subtree -- that would orphan
    // it / make a cycle. moveItem rejects this server-side too (containsId), but
    // checking here lets us suppress the drop marker so an invalid target reads as a
    // visible "no" instead of a silent no-op when released.
    const isInvalidDropTarget = (targetRow) => {
        if (!dragSourceId) return true;
        const sourceRow = treeContainer.querySelector('.tree-item[data-id="' + dragSourceId + '"]');
        if (!sourceRow) return false;
        if (sourceRow === targetRow) return true;
        const kids = sourceRow.nextElementSibling;
        return !!(kids && kids.classList.contains('children') && kids.contains(targetRow));
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
        if (isInvalidDropTarget(row)) {
            // Skip preventDefault so the browser shows "no drop", and leave no marker.
            event.dataTransfer.dropEffect = 'none';
            clearDropMarkers();
            return;
        }
        event.preventDefault();
        event.dataTransfer.dropEffect = 'move';
        clearDropMarkers();
        row.classList.add('drop-' + dropPosition(row, event));
    });

    treeContainer.addEventListener('drop', (event) => {
        const row = event.target.closest('.tree-item');
        if (!row || !dragSourceId) return;
        event.preventDefault();
        clearDropMarkers();
        if (isInvalidDropTarget(row)) { dragSourceId = null; return; }
        const targetId = row.dataset.id;
        const position = dropPosition(row, event);
        window.location.href =
            `hammerspoon://moveItem?source=${dragSourceId}&target=${targetId}&position=${position}`;
        dragSourceId = null;
    });

    treeContainer.addEventListener('dragend', () => {
        clearDropMarkers();
        dragSourceId = null;
    });

    // --- Tree filter/search (harvested from the shelved tree_view.js) ---------
    // Filters the live, Lua-rendered tree in place. A row stays visible when it
    // matches, when an ancestor matches (a matched folder reveals its whole
    // subtree, via `force`), or when a descendant matches (a buried hit stays
    // reachable in context). Each .tree-item row is followed by a sibling
    // .children block, so we recurse one level at a time.
    // Known limit: collapsed folders don't render their children into the DOM, so
    // those rows aren't searchable here -- the default-expanded case is covered; a
    // Lua-side filter would be needed to reach collapsed branches.
    const treeSearch = document.getElementById('tree-search');
    const treeSearchClear = document.getElementById('tree-search-clear');
    let filterQuery = '';

    function applyTreeFilter(container, query, force) {
        let anyVisible = false;
        const rows = Array.prototype.filter.call(
            container.children, (el) => el.classList.contains('tree-item'));
        rows.forEach((row) => {
            const next = row.nextElementSibling;
            const kids = (next && next.classList.contains('children')) ? next : null;
            const nameEl = row.querySelector('.name');
            const nameMatch = !!(nameEl && nameEl.textContent.toLowerCase().includes(query));
            const childForce = force || nameMatch;
            const descVisible = kids ? applyTreeFilter(kids, query, childForce) : false;
            const visible = force || nameMatch || descVisible;
            row.classList.toggle('tree-hidden', !visible);
            if (kids) kids.classList.toggle('tree-hidden', !descVisible);
            if (visible) anyVisible = true;
        });
        return anyVisible;
    }

    function runTreeFilter() {
        if (!treeContainer) return;
        if (!filterQuery) {
            // Empty query: clear every hide flag so the full tree shows.
            treeContainer.querySelectorAll('.tree-hidden')
                .forEach((el) => el.classList.remove('tree-hidden'));
            return;
        }
        applyTreeFilter(treeContainer, filterQuery, false);
    }

    function setFilterQuery(value) {
        filterQuery = value.trim().toLowerCase();
        if (treeSearchClear) treeSearchClear.style.display = filterQuery ? 'block' : 'none';
        runTreeFilter();
    }

    if (treeSearch) {
        treeSearch.addEventListener('input', () => setFilterQuery(treeSearch.value));
        treeSearch.addEventListener('keydown', (event) => {
            if (event.key === 'Escape') { treeSearch.value = ''; setFilterQuery(''); }
        });
    }
    if (treeSearchClear) {
        treeSearchClear.addEventListener('click', () => {
            treeSearch.value = '';
            setFilterQuery('');
            treeSearch.focus();
        });
    }

    // Lua refreshes the tree by replacing #tree-container's innerHTML; re-apply the
    // active filter to the fresh rows so a search survives add/delete/toggle/move.
    if (window.MutationObserver) {
        new MutationObserver(() => { if (filterQuery) runTreeFilter(); })
            .observe(treeContainer, { childList: true });
    }

    // --- Right-click context menu (harvested from the shelved tree_view.js) ---
    // Right-click a row for the same operations as its inline buttons, plus
    // add-child for container rows. Every item maps to an existing ui.handleURL
    // route (runItem/editItem/toggleItem/toggleExpand/deleteItem/addChild), so the
    // menu is a faster path to actions that already work -- it adds no new behavior.
    const contextMenu = document.getElementById('tree-context-menu');

    const closeContextMenu = () => { if (contextMenu) contextMenu.classList.remove('open'); };

    // Build the menu's items for a given row, reading type/enabled/expanded state
    // straight off the DOM (the same attributes app.js's click delegation uses).
    function buildContextMenu(row) {
        const id = row.dataset.id;
        const type = row.dataset.type;
        // Only folders and triggers RUN their children (a folder via _runChildren,
        // a trigger via the event dispatcher), so only they can take an added child.
        // A sequence executes its `steps`, not its `children` -- a child added to a
        // sequence would render in the tree but never run, so it's excluded here.
        const isContainer = type === 'folder' || type === 'trigger';
        const isDisabled = row.classList.contains('disabled');
        // A real disclosure triangle (not the spacer) means the row has children;
        // ▾ = currently expanded, ▸ = collapsed.
        const disclosure = row.querySelector('.disclosure');
        const isExpanded = !!disclosure && disclosure.textContent.indexOf('▾') !== -1;

        const items = [
            { label: 'Run', href: `hammerspoon://runItem?id=${id}` },
            { label: 'Edit', href: `hammerspoon://editItem?id=${id}` },
            { label: isDisabled ? 'Enable' : 'Disable', href: `hammerspoon://toggleItem?id=${id}` },
        ];
        if (disclosure) {
            items.push({ label: isExpanded ? 'Collapse' : 'Expand',
                href: `hammerspoon://toggleExpand?id=${id}` });
        }
        if (isContainer) {
            items.push({ sep: true });
            ['folder', 'trigger', 'action', 'sequence'].forEach((t) => {
                items.push({
                    label: 'Add ' + t.charAt(0).toUpperCase() + t.slice(1),
                    href: `hammerspoon://addChild?id=${id}&type=${t}`,
                });
            });
        }
        items.push({ sep: true });
        items.push({ label: 'Delete', danger: true, confirm: true,
            href: `hammerspoon://deleteItem?id=${id}` });

        contextMenu.innerHTML = '';
        items.forEach((it) => {
            if (it.sep) {
                const sep = document.createElement('div');
                sep.className = 'menu-sep';
                contextMenu.appendChild(sep);
                return;
            }
            const el = document.createElement('div');
            el.className = 'menu-item' + (it.danger ? ' danger' : '');
            el.textContent = it.label; // textContent: labels are static, no injection
            el.addEventListener('click', () => {
                closeContextMenu();
                if (it.confirm && !confirm('Are you sure you want to delete this item?')) return;
                window.location.href = it.href;
            });
            contextMenu.appendChild(el);
        });
    }

    // Show at the cursor, then clamp so the menu never spills past the viewport.
    function openContextMenu(row, x, y) {
        if (!contextMenu) return;
        buildContextMenu(row);
        contextMenu.style.left = '0px';
        contextMenu.style.top = '0px';
        contextMenu.classList.add('open');
        const rect = contextMenu.getBoundingClientRect();
        const maxX = window.innerWidth - rect.width - 4;
        const maxY = window.innerHeight - rect.height - 4;
        contextMenu.style.left = Math.max(4, Math.min(x, maxX)) + 'px';
        contextMenu.style.top = Math.max(4, Math.min(y, maxY)) + 'px';
    }

    if (contextMenu) {
        treeContainer.addEventListener('contextmenu', (event) => {
            const row = event.target.closest('.tree-item');
            if (!row) return;
            event.preventDefault();
            openContextMenu(row, event.clientX, event.clientY);
        });
        // Dismiss on outside click, Escape, or scrolling the tree.
        document.addEventListener('click', (event) => {
            if (!contextMenu.contains(event.target)) closeContextMenu();
        });
        document.addEventListener('keydown', (event) => {
            if (event.key === 'Escape') closeContextMenu();
        });
        treeContainer.addEventListener('scroll', closeContextMenu, true);
    }

    // --- Resizable divider between the tree and properties panels ---
    // Sets #tree-column's width (a style attribute on the column wrapper, not the
    // re-rendered #tree-container), so the chosen width survives innerHTML refreshes.
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
            if (treeColumn) treeColumn.style.width = width + 'px';
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
            const autostartInput = document.getElementById('autostart');
            if (autostartInput) data.autostart = autostartInput.checked;
            window.location.href = `hammerspoon://saveProperties?${encodeURIComponent(JSON.stringify(data))}`;
        } else if (target.matches('#cancel-button')) {
            window.location.href = 'hammerspoon://cancelEdit';
        }
    });
});
