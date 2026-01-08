# DragonGrid Documentation

DragonGrid is a Hammerspoon module that provides a grid-based pointer control system inspired by Dragon NaturallySpeaking's MouseGrid feature. It allows you to move your mouse cursor with precision using keyboard controls, eliminating the need for physical mouse movement.

## Usage

### Basic Commands

- **Toggle DragonGrid**: Press `Cmd+Ctrl+Alt+X` to show/hide the DragonGrid
- **Window Mode**: Press `Cmd+Shift+Ctrl+Alt+X` to show DragonGrid only on the active window

### Navigation

When the DragonGrid is active, you can use the following keys:

1. **Grid Cell Selection**:
   - Press numbers `1-9` to select a grid cell (the grid is numbered 1-9 from top-left to bottom-right)
   - The grid will zoom in to your selected cell and show a new 3x3 grid within it
   - Press another number to make a final selection

2. **Actions**:51
   - `Return/Enter`: Confirm the position (Go)
   - `Escape`: Cancel and close the grid
   - `U`: Undo the last selection (go back one level)

3. **Mouse Actions**:
   - `Space`: Left-click at the current position
   - `Alt+Space`: Right-click at the current position
   - `Shift+Space`: Middle-click at the current position
   - `Ctrl+Space`: Double-click at the current position

4. **Drag and Drop**:
   - `Shift+M`: Mark the current position as the drag start point
   - Select another position
   - `D`: Drag from the marked position to the current position

5. **Mode Switching**:
   - `W`: Toggle between full-screen and window-specific modes

## Examples

### Precise Click

1. Press `Cmd+Ctrl+Alt+X` to show the DragonGrid
2. Press `5` to select the center cell
3. Press `1` to select the top-left of the center cell
4. Press `Space` to left-click at that position

### Drag Operation

1. Press `Cmd+Ctrl+Alt+X` to show the DragonGrid
2. Navigate to the starting point for your drag operation
3. Press `Shift+M` to mark that position
4. Navigate to the endpoint for your drag operation
5. Press `D` to perform the drag operation

## Configuration

You can customize DragonGrid in your Hammerspoon configuration:

```lua
-- Customize grid size (default is 3x3)
DragonGrid.setConfig({
    gridSize = 4,  -- Creates a 4x4 grid
    colors = {
        background = { red = 0, green = 0, blue = 0, alpha = 0.4 },
        cellBorder = { white = 1, alpha = 0.9 }
    }
})

-- Custom key bindings
hs.hotkey.bind({"cmd", "alt"}, "g", function() DragonGrid.toggleDragonGrid() end)
hs.hotkey.bind({"cmd", "alt", "shift"}, "g", function()
    windowMode = true
    DragonGrid.createDragonGrid()
end)
```

## Tips

- For maximum precision, make use of the two-level grid selection
- Use window mode for more accurate control over application UI elements
- The drag operation is useful for selecting text or moving items
- DragonGrid works well with mouse-unfriendly applications that require precise positioning
