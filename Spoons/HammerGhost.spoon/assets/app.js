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

        if (target.matches('.toggle-button')) {
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
