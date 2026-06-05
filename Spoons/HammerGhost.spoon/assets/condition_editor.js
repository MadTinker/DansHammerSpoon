// Condition editor page script. Driven from Lua (handleConditionEditorURL /
// openConditionEditor) via global entry points:
//   populateConditionTypes(types) - fill the Type dropdown
//   populateEditor(condition)     - load an existing condition for editing
//   resetEditor()                 - clear the form for a fresh add
// Inlined at end of <body>; functions live on `window` so evaluateJavaScript can
// reach them (closure-local versions were invisible to Lua -> empty dropdown).

let conditionTypesMap = {};
let pendingCondition = null;

const conditionForm = document.getElementById('condition-form');
const conditionTypeSelect = document.getElementById('condition-type');
const conditionParametersDiv = document.getElementById('condition-parameters');

// Render parameter inputs for the selected condition type. `values` (optional)
// pre-fills inputs when editing.
function renderParameters(values) {
    const def = conditionTypesMap[conditionTypeSelect.value];
    conditionParametersDiv.innerHTML = '';
    if (!def || !def.parameters) return;
    for (const paramName in def.parameters) {
        const param = def.parameters[paramName];
        const formGroup = document.createElement('div');
        formGroup.className = 'form-group';
        const label = document.createElement('label');
        label.textContent = paramName;

        let input;
        if (param.type === 'select') {
            input = document.createElement('select');
            (param.options || []).forEach(opt => {
                const option = document.createElement('option');
                option.value = opt;
                option.textContent = opt;
                input.appendChild(option);
            });
        } else {
            input = document.createElement('input');
            input.type = param.type || 'text';
        }
        input.name = paramName;
        input.required = !!param.required;
        if (values && values[paramName] !== undefined) {
            input.value = values[paramName];
        } else if (param.default !== undefined) {
            input.value = param.default;
        }
        formGroup.appendChild(label);
        formGroup.appendChild(input);
        conditionParametersDiv.appendChild(formGroup);
    }
}

function applyCondition(condition) {
    document.getElementById('condition-id').value = condition.id || '';
    if (condition.conditionType) {
        conditionTypeSelect.value = condition.conditionType;
    }
    renderParameters(condition.params || {});
}

conditionTypeSelect.addEventListener('change', () => renderParameters());

window.populateConditionTypes = function(conditionTypes) {
    conditionTypesMap = conditionTypes || {};
    conditionTypeSelect.innerHTML = '';
    // Sort by display label so the list is scannable, not arbitrary order.
    Object.keys(conditionTypesMap)
        .map(type => [type, conditionTypesMap[type].name || type])
        .sort((a, b) => a[1].localeCompare(b[1]))
        .forEach(([type, label]) => {
            const option = document.createElement('option');
            option.value = type;
            option.textContent = label;
            conditionTypeSelect.appendChild(option);
        });
    if (pendingCondition) {
        applyCondition(pendingCondition);
        pendingCondition = null;
    } else {
        renderParameters();
    }
};

window.populateEditor = function(condition) {
    if (Object.keys(conditionTypesMap).length > 0) {
        applyCondition(condition);
    } else {
        pendingCondition = condition; // applied when populateConditionTypes lands
    }
};

window.resetEditor = function() {
    pendingCondition = null;
    document.getElementById('condition-id').value = '';
    if (conditionTypeSelect.options.length > 0) {
        conditionTypeSelect.selectedIndex = 0;
    }
    renderParameters();
};

conditionForm.addEventListener('submit', (event) => {
    event.preventDefault();
    const id = document.getElementById('condition-id').value;
    const type = conditionTypeSelect.value;
    const params = {};
    conditionParametersDiv.querySelectorAll('input, select').forEach(input => {
        params[input.name] = input.value;
    });
    const conditionData = { id, type, params };
    window.location.href = `hammerspoon://saveCondition?${encodeURIComponent(JSON.stringify(conditionData))}`;
});

document.getElementById('cancel-condition').addEventListener('click', () => {
    window.location.href = 'hammerspoon://cancelConditionEditor';
});

// Ask the Lua side for the registered condition types.
window.location.href = 'hammerspoon://getConditionTypes';
