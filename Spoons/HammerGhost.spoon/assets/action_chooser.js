// Action chooser page script. Lua (handleActionChooserURL) calls populateActions
// via evaluateJavaScript, so it must be global (not closure-local). Inlined at end
// of <body>, so the DOM is parsed when this runs.

const actionList = document.getElementById('action-list');

window.populateActions = function(actions) {
    actionList.innerHTML = '';
    if (!actions || actions.length === 0) {
        // No action nodes exist yet -- the chooser only lists actions already in
        // the tree, so say so instead of showing a blank box you can't act on.
        const empty = document.createElement('div');
        empty.className = 'empty-state';
        empty.textContent = 'No actions yet — create an action first, then add it to the sequence.';
        actionList.appendChild(empty);
        return;
    }
    actions.forEach(action => {
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

// Back out of the chooser without picking (button or Escape) -- without this the
// chooser is a dead end when opened from the sequence editor's "Add Action".
function cancelChooser() {
    window.location.href = 'hammerspoon://cancelActionChooser';
}
document.getElementById('cancel-chooser').addEventListener('click', cancelChooser);
document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') cancelChooser();
});

// Request the list of actions.
window.location.href = 'hammerspoon://getActions';
