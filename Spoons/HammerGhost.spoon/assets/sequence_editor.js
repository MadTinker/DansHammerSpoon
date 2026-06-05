// Sequence editor page script. Lua (handleSequenceEditorURL) drives it via two
// global entry points:
//   populateEditor(sequence)  - load the sequence's existing steps
//   addStepToSequence(step)   - add a step from the pickers, or replace the step
//                               currently being edited (see editingStepIndex)
// Inlined at end of <body>, so the DOM is parsed when this runs. Functions live on
// `window` so evaluateJavaScript can reach them.

const stepsContainer = document.getElementById('sequence-steps');
let steps = [];
// When a step is being edited (not added), this holds its index so the result
// coming back via addStepToSequence REPLACES it instead of appending. null = add
// mode. Every entry point sets it explicitly (Add buttons -> null, condition Edit
// -> index) so a cancelled edit can't leave a stale index that clobbers the next
// append. Action-step edits leave it null: they save to the referenced tree node,
// not back through addStepToSequence.
let editingStepIndex = null;

function renderSteps() {
    stepsContainer.innerHTML = '';
    steps.forEach((step, index) => {
        const stepElement = document.createElement('div');
        stepElement.className = 'sequence-step';
        stepElement.dataset.index = index;
        stepElement.draggable = true; // drag to reorder
        if (step.type === 'action') {
            stepElement.innerHTML = `
                <span>Action: ${step.data.name}</span>
                <button class="edit-step">Edit</button>
                <button class="remove-step">Remove</button>
            `;
        } else if (step.type === 'condition') {
            stepElement.innerHTML = `
                <span>Condition: ${step.data.type}</span>
                <button class="edit-step">Edit</button>
                <button class="remove-step">Remove</button>
            `;
        }
        stepsContainer.appendChild(stepElement);
    });
}

document.getElementById('add-action-step').addEventListener('click', () => {
    editingStepIndex = null; // adding, not editing -> append the result
    window.location.href = 'hammerspoon://selectActionForSequence';
});

document.getElementById('add-condition-step').addEventListener('click', () => {
    editingStepIndex = null; // adding, not editing -> append the result
    window.location.href = 'hammerspoon://addConditionToSequence';
});

stepsContainer.addEventListener('click', (event) => {
    if (event.target.matches('.remove-step')) {
        const index = event.target.closest('.sequence-step').dataset.index;
        steps.splice(index, 1);
        renderSteps();
    } else if (event.target.matches('.edit-step')) {
        const index = Number(event.target.closest('.sequence-step').dataset.index);
        const step = steps[index];
        if (!step) return;
        if (step.type === 'condition') {
            // Condition params live inline in step.data; reopen the condition
            // editor prefilled, and replace THIS step when it comes back.
            editingStepIndex = index;
            window.location.href =
                `hammerspoon://editConditionStep?${encodeURIComponent(JSON.stringify(step.data))}`;
        } else if (step.type === 'action') {
            // Action steps only reference a tree node (data.id); its params live
            // on that node. Edit the node directly (Lua opens the action editor on
            // it). It saves back to the node, not here, so we stay in add mode.
            editingStepIndex = null;
            window.location.href =
                `hammerspoon://editActionStep?${encodeURIComponent(JSON.stringify({ id: step.data.id }))}`;
        }
    }
});

// Drag a step onto another to reorder (order is the run order, so this matters
// for the condition gate). Indexes are read off data-index, which renderSteps
// keeps in sync after every change.
let dragIndex = null;
stepsContainer.addEventListener('dragstart', (event) => {
    const el = event.target.closest('.sequence-step');
    if (!el) return;
    dragIndex = Number(el.dataset.index);
    event.dataTransfer.effectAllowed = 'move';
});
stepsContainer.addEventListener('dragover', (event) => {
    if (dragIndex === null) return;
    event.preventDefault();
    event.dataTransfer.dropEffect = 'move';
});
stepsContainer.addEventListener('drop', (event) => {
    const el = event.target.closest('.sequence-step');
    if (dragIndex === null || !el) return;
    event.preventDefault();
    const dropIndex = Number(el.dataset.index);
    if (dropIndex !== dragIndex) {
        const [moved] = steps.splice(dragIndex, 1);
        steps.splice(dropIndex, 0, moved);
        renderSteps();
    }
    dragIndex = null;
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

// Lua -> JS: a step picked from the action/condition chooser. Replaces the step
// being edited (condition Edit set editingStepIndex), otherwise appends.
window.addStepToSequence = function(step) {
    if (editingStepIndex !== null && editingStepIndex >= 0 && editingStepIndex < steps.length) {
        steps[editingStepIndex] = step;
    } else {
        steps.push(step);
    }
    editingStepIndex = null;
    renderSteps();
};

// Request the current sequence's data.
window.location.href = 'hammerspoon://getSequenceData';
