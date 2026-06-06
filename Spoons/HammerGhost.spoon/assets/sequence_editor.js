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

// Build one step row. data-index is the FLAT array index -- edit/remove/toggle/
// drag all key off it, so it must match the steps[] position no matter how the
// row gets nested for gate visualization.
function buildStepRow(step, index) {
    const el = document.createElement('div');
    el.className = 'sequence-step';
    if (step.enabled === false) el.classList.add('disabled');
    el.dataset.index = index;
    el.draggable = true; // drag to reorder
    const label = (step.type === 'action')
        ? `Action: ${step.data.name}`
        : `Condition: ${step.data.type}`;
    const toggleLabel = step.enabled === false ? 'Off' : 'On';
    el.innerHTML = `
        <span class="step-label">${label}</span>
        <span class="step-actions">
            <button class="toggle-step" title="Enable/disable this step">${toggleLabel}</button>
            <button class="edit-step">Edit</button>
            <button class="remove-step">Remove</button>
        </span>
    `;
    return el;
}

// Render steps with gate visualization: an ENABLED condition opens a group, and
// the actions that follow nest under it until the next enabled condition. This
// uses the SAME `enabled === false` skip the executor uses (init.lua sequence
// loop), so a disabled condition does NOT form a group -- its following actions
// stay in whatever gate is currently active, exactly as they'll run. Keeping the
// two skip rules identical means the picture can't diverge from the behavior.
function renderSteps() {
    stepsContainer.innerHTML = '';
    let currentGroup = null; // .gate-actions of the most recent ENABLED condition
    steps.forEach((step, index) => {
        const row = buildStepRow(step, index);
        const disabled = step.enabled === false;
        if (step.type === 'condition' && !disabled) {
            const group = document.createElement('div');
            group.className = 'gate-group';
            row.classList.add('gate-header');
            const actions = document.createElement('div');
            actions.className = 'gate-actions';
            group.appendChild(row);
            group.appendChild(actions);
            stepsContainer.appendChild(group);
            currentGroup = actions;
        } else {
            // Enabled actions, disabled actions, and disabled conditions all sit
            // in whatever gate is active now (nested under an enabled condition's
            // group, or top-level when no gate is open).
            (currentGroup || stepsContainer).appendChild(row);
        }
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
    } else if (event.target.matches('.toggle-step')) {
        // Mute/unmute a step without removing it. Flip: disabled -> enabled,
        // anything else -> disabled. The executor skips enabled === false.
        const index = Number(event.target.closest('.sequence-step').dataset.index);
        const step = steps[index];
        if (!step) return;
        step.enabled = (step.enabled === false);
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
        // Replace is wholesale, but the incoming step (rebuilt by the condition
        // editor) carries no step-level metadata -- carry the enabled flag across
        // so editing a toggled-off step doesn't silently re-enable it.
        const prev = steps[editingStepIndex];
        if (prev && prev.enabled !== undefined) step.enabled = prev.enabled;
        steps[editingStepIndex] = step;
    } else {
        steps.push(step);
    }
    editingStepIndex = null;
    renderSteps();
};

// Request the current sequence's data.
window.location.href = 'hammerspoon://getSequenceData';
