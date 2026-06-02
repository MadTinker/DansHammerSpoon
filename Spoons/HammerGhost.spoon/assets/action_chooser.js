// Action chooser page script. Lua (handleActionChooserURL) calls populateActions
// via evaluateJavaScript, so it must be global (not closure-local). Inlined at end
// of <body>, so the DOM is parsed when this runs.

const actionList = document.getElementById('action-list');

window.populateActions = function(actions) {
    actionList.innerHTML = '';
    (actions || []).forEach(action => {
        const actionElement = document.createElement('div');
        actionElement.className = 'action-item';
        actionElement.dataset.id = action.id;
        actionElement.textContent = action.name;
        actionList.appendChild(actionElement);
    });
};

actionList.addEventListener('click', (event) => {
    if (event.target.matches('.action-item')) {
        const id = event.target.dataset.id;
        const name = event.target.textContent;
        const action = { id, name };
        window.location.href = `hammerspoon://actionSelected?${encodeURIComponent(JSON.stringify(action))}`;
    }
});

// Request the list of actions.
window.location.href = 'hammerspoon://getActions';
