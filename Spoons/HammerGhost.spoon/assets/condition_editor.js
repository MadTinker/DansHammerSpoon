document.addEventListener('DOMContentLoaded', () => {
    const conditionForm = document.getElementById('condition-form');
    const conditionTypeSelect = document.getElementById('condition-type');
    const conditionParametersDiv = document.getElementById('condition-parameters');

    // Populate condition types
    function populateConditionTypes(conditionTypes) {
        for (const type in conditionTypes) {
            const option = document.createElement('option');
            option.value = type;
            option.textContent = conditionTypes[type].name;
            conditionTypeSelect.appendChild(option);
        }
        // Trigger change to load initial parameters
        conditionTypeSelect.dispatchEvent(new Event('change'));
    }

    // Display parameters for the selected condition type
    conditionTypeSelect.addEventListener('change', () => {
        const selectedType = conditionTypeSelect.value;
        const conditionTypes = getConditionTypes(); // This function will be defined in the main app
        const parameters = conditionTypes[selectedType].parameters;

        conditionParametersDiv.innerHTML = '';
        for (const paramName in parameters) {
            const param = parameters[paramName];
            const formGroup = document.createElement('div');
            formGroup.className = 'form-group';
            const label = document.createElement('label');
            label.textContent = paramName;

            let input;
            if (param.type === 'select') {
                input = document.createElement('select');
                param.options.forEach(opt => {
                    const option = document.createElement('option');
                    option.value = opt;
                    option.textContent = opt;
                    input.appendChild(option);
                });
            } else {
                input = document.createElement('input');
                input.type = param.type;
            }

            input.name = paramName;
            input.required = param.required;
            if (param.default) {
                input.value = param.default;
            }
            formGroup.appendChild(label);
            formGroup.appendChild(input);
            conditionParametersDiv.appendChild(formGroup);
        }
    });

    // Handle form submission
    conditionForm.addEventListener('submit', (event) => {
        event.preventDefault();
        const id = document.getElementById('condition-id').value;
        const type = conditionTypeSelect.value;
        const params = {};
        const inputs = conditionParametersDiv.querySelectorAll('input, select');
        inputs.forEach(input => {
            params[input.name] = input.value;
        });

        const conditionData = { id, type, params };
        window.location.href = `hammerspoon://saveCondition?${encodeURIComponent(JSON.stringify(conditionData))}`;
    });

    // Cancel editing
    document.getElementById('cancel-condition').addEventListener('click', () => {
        window.location.href = 'hammerspoon://cancelConditionEditor';
    });

    // Request condition types from the main app
    window.location.href = 'hammerspoon://getConditionTypes';
});
