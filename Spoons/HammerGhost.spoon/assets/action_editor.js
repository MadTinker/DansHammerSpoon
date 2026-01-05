document.addEventListener('DOMContentLoaded', () => {
    const actionForm = document.getElementById('action-form');
    const actionTypeSelect = document.getElementById('action-type');
    const actionParametersDiv = document.getElementById('action-parameters');

    // Populate action types
    function populateActionTypes(actionTypes) {
        for (const type in actionTypes) {
            const option = document.createElement('option');
            option.value = type;
            option.textContent = actionTypes[type].name;
            actionTypeSelect.appendChild(option);
        }
    }

    // Display parameters for the selected action type
    actionTypeSelect.addEventListener('change', () => {
        const selectedType = actionTypeSelect.value;
        const actionTypes = getActionTypes(); // This function will be defined in the main app
        const parameters = actionTypes[selectedType].parameters;

        actionParametersDiv.innerHTML = '';
        for (const paramName in parameters) {
            const param = parameters[paramName];
            const formGroup = document.createElement('div');
            formGroup.className = 'form-group';
            const label = document.createElement('label');
            label.textContent = paramName;
            const input = document.createElement('input');
            input.type = param.type;
            input.name = paramName;
            input.required = param.required;
            if (param.default) {
                input.value = param.default;
            }
            formGroup.appendChild(label);
            formGroup.appendChild(input);
            actionParametersDiv.appendChild(formGroup);
        }
    });

    // Handle form submission
    actionForm.addEventListener('submit', (event) => {
        event.preventDefault();
        const id = document.getElementById('action-id').value;
        const name = document.getElementById('action-name').value;
        const type = actionTypeSelect.value;
        const params = {};
        const inputs = actionParametersDiv.querySelectorAll('input');
        inputs.forEach(input => {
            params[input.name] = input.value;
        });

        const actionData = { id, name, type, params };
        window.location.href = `hammerspoon://saveAction?${encodeURIComponent(JSON.stringify(actionData))}`;
    });

    // Cancel editing
    document.getElementById('cancel-action').addEventListener('click', () => {
        window.location.href = 'hammerspoon://cancelActionEditor';
    });

    // Request action types from the main app
    window.location.href = 'hammerspoon://getActionTypes';
});
