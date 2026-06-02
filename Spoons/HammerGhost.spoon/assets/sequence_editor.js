// Sequence editor page script. Lua (handleSequenceEditorURL) drives it via two
// global entry points:
//   populateEditor(sequence)  - load the sequence's existing steps
//   addStepToSequence(step)   - append a step chosen via the action/condition pickers
// Inlined at end of <body>, so the DOM is parsed when this runs. Functions live on
// `window` so evaluateJavaScript can reach them.

const stepsContainer = document.getElementById('sequence-steps');
let steps = [];

function renderSteps() {
    stepsContainer.innerHTML = '';
    steps.forEach((step, index) => {
        const stepElement = document.createElement('div');
        stepElement.className = 'sequence-step';
        stepElement.dataset.index = index;
        if (step.type === 'action') {
            stepElement.innerHTML = `
                <span>Action: ${step.data.name}</span>
                <button class="remove-step">Remove</button>
            `;
        } else if (step.type === 'condition') {
            stepElement.innerHTML = `
                <span>Condition: ${step.data.type}</span>
                <button class="remove-step">Remove</button>
            `;
        }
        stepsContainer.appendChild(stepElement);
    });
}

document.getElementById('add-action-step').addEventListener('click', () => {
    window.location.href = 'hammerspoon://selectActionForSequence';
});

document.getElementById('add-condition-step').addEventListener('click', () => {
    window.location.href = 'hammerspoon://addConditionToSequence';
});

stepsContainer.addEventListener('click', (event) => {
    if (event.target.matches('.remove-step')) {
        const index = event.target.closest('.sequence-step').dataset.index;
        steps.splice(index, 1);
        renderSteps();
    }
});

document.getElementById('save-sequence').addEventListener('click', () => {
    const sequenceData = { steps };
    window.location.href = `hammerspoon://saveSequence?${encodeURIComponent(JSON.stringify(sequenceData))}`;
});

document.getElementById('cancel-sequence').addEventListener('click', () => {
    window.location.href = 'hammerspoon://cancelSequenceEditor';
});

// Lua -> JS: load an existing sequence's steps for editing.
window.populateEditor = function(sequence) {
    steps = (sequence && sequence.steps) || [];
    renderSteps();
};

// Lua -> JS: append a step picked from the action/condition chooser.
window.addStepToSequence = function(step) {
    steps.push(step);
    renderSteps();
};

// Request the current sequence's data.
window.location.href = 'hammerspoon://getSequenceData';
