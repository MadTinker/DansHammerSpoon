// Condition editor page script. Driven from Lua (handleConditionEditorURL /
// openConditionEditor) via global entry points:
//   populateConditionTypes(types) - fill the Type dropdown
//   populateEditor(condition)     - load an existing condition for editing
//   resetEditor()                 - clear the form for a fresh add
// Inlined at end of <body>; functions live on `window` so evaluateJavaScript can
// reach them (closure-local versions were invisible to Lua -> empty dropdown).

window.HG = window.HG || {};
HG.surface = 'condition'; // picker write-back targets this webview (HG.setParamValue)

let conditionTypesMap = {};
let pendingCondition = null;

const conditionForm = document.getElementById('condition-form');
const conditionTypeSelect = document.getElementById('condition-type');
const conditionParametersDiv = document.getElementById('condition-parameters');

// Render parameter inputs for the selected condition type. `values` (optional)
// pre-fills inputs when editing. Delegates to the shared HG renderer so the popup
// and the inline properties panel build identical widgets.
function renderParameters(values) {
    const def = conditionTypesMap[conditionTypeSelect.value];
    HG.renderParams(conditionParametersDiv, def && def.parameters, values);
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
    const params = HG.collectParams(conditionParametersDiv);
    const conditionData = { id, type, params };
    window.location.href = `hammerspoon://saveCondition?${encodeURIComponent(JSON.stringify(conditionData))}`;
});

document.getElementById('cancel-condition').addEventListener('click', () => {
    window.location.href = 'hammerspoon://cancelConditionEditor';
});

// Escape cancels the editor, matching standard dialog behavior.
document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') window.location.href = 'hammerspoon://cancelConditionEditor';
});

// Ask the Lua side for the registered condition types.
window.location.href = 'hammerspoon://getConditionTypes';
