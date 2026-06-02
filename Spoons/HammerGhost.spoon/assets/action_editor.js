// Action editor page script. The Lua side (handleActionEditorURL / openActionEditor)
// drives this through three entry points that MUST be reachable from
// evaluateJavaScript's global scope, so they hang off `window`:
//   populateActionTypes(types) - fill the Type dropdown
//   populateEditor(action)     - load an existing action for editing
//   resetEditor()              - clear the form for a fresh "add"
// This script is inlined at end of <body>, so the DOM is already parsed when it
// runs; no DOMContentLoaded wrapper (that also kept these functions closure-local
// and invisible to Lua, which is why the dropdown was always empty).

let actionTypesMap = {};
// An edit can arrive before the action-types round-trip returns (the page asks
// for types on load; Lua may call populateEditor immediately after show()).
// Stash the action and apply it once the types land.
let pendingAction = null;

const actionForm = document.getElementById('action-form');
const actionTypeSelect = document.getElementById('action-type');
const actionParametersDiv = document.getElementById('action-parameters');

// Render parameter inputs for the selected action type. `values` (optional)
// pre-fills inputs when editing an existing action.
function renderParameters(values) {
    const def = actionTypesMap[actionTypeSelect.value];
    actionParametersDiv.innerHTML = '';
    if (!def || !def.parameters) return;
    for (const paramName in def.parameters) {
        const param = def.parameters[paramName];
        const formGroup = document.createElement('div');
        formGroup.className = 'form-group';
        const label = document.createElement('label');
        label.textContent = paramName;
        const input = document.createElement('input');
        input.type = param.type || 'text';
        input.name = paramName;
        input.required = !!param.required;
        if (values && values[paramName] !== undefined) {
            input.value = values[paramName];
        } else if (param.default !== undefined) {
            input.value = param.default;
        }
        formGroup.appendChild(label);
        formGroup.appendChild(input);
        actionParametersDiv.appendChild(formGroup);
    }
}

function applyAction(action) {
    document.getElementById('action-id').value = action.id || '';
    document.getElementById('action-name').value = action.name || '';
    if (action.actionType) {
        actionTypeSelect.value = action.actionType;
    }
    renderParameters(action.params || {});
}

actionTypeSelect.addEventListener('change', () => renderParameters());

window.populateActionTypes = function(actionTypes) {
    actionTypesMap = actionTypes || {};
    actionTypeSelect.innerHTML = '';
    for (const type in actionTypesMap) {
        const option = document.createElement('option');
        option.value = type;
        option.textContent = actionTypesMap[type].name;
        actionTypeSelect.appendChild(option);
    }
    if (pendingAction) {
        applyAction(pendingAction);
        pendingAction = null;
    } else {
        renderParameters();
    }
};

window.populateEditor = function(action) {
    if (Object.keys(actionTypesMap).length > 0) {
        applyAction(action);
    } else {
        pendingAction = action; // applied when populateActionTypes lands
    }
};

window.resetEditor = function() {
    pendingAction = null;
    document.getElementById('action-id').value = '';
    document.getElementById('action-name').value = '';
    if (actionTypeSelect.options.length > 0) {
        actionTypeSelect.selectedIndex = 0;
    }
    renderParameters();
};

actionForm.addEventListener('submit', (event) => {
    event.preventDefault();
    const id = document.getElementById('action-id').value;
    const name = document.getElementById('action-name').value;
    const type = actionTypeSelect.value;
    const params = {};
    actionParametersDiv.querySelectorAll('input').forEach(input => {
        params[input.name] = input.value;
    });
    const actionData = { id, name, type, params };
    window.location.href = `hammerspoon://saveAction?${encodeURIComponent(JSON.stringify(actionData))}`;
});

document.getElementById('cancel-action').addEventListener('click', () => {
    window.location.href = 'hammerspoon://cancelActionEditor';
});

// Ask the Lua side for the registered action types.
window.location.href = 'hammerspoon://getActionTypes';
