document.addEventListener('DOMContentLoaded', () => {
    const actionList = document.getElementById('action-list');

    function populateActions(actions) {
        actionList.innerHTML = '';
        actions.forEach(action => {
            const actionElement = document.createElement('div');
            actionElement.className = 'action-item';
            actionElement.dataset.id = action.id;
            actionElement.textContent = action.name;
            actionList.appendChild(actionElement);
        });
    }

    actionList.addEventListener('click', (event) => {
        if (event.target.matches('.action-item')) {
            const id = event.target.dataset.id;
            const name = event.target.textContent;
            const action = { id, name };
            window.location.href = `hammerspoon://actionSelected?${encodeURIComponent(JSON.stringify(action))}`;
        }
    });

    // Request the list of actions
    window.location.href = 'hammerspoon://getActions';
});
