document.addEventListener('DOMContentLoaded', () => {
    const treeContainer = document.getElementById('tree-container');
    const propertiesPanel = document.getElementById('properties-panel');

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
        const isContainer = row.dataset.type === 'folder' || row.dataset.type === 'sequence';
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

    // Use event delegation for properties panel actions
    propertiesPanel.addEventListener('click', (event) => {
        const target = event.target;

        if (target.matches('#save-button')) {
            const id = target.dataset.id;
            const name = document.getElementById('name').value;
            const data = { id, name };
            window.location.href = `hammerspoon://saveProperties?${encodeURIComponent(JSON.stringify(data))}`;
        } else if (target.matches('#cancel-button')) {
            window.location.href = 'hammerspoon://cancelEdit';
        }
    });
});
