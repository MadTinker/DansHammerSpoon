# Feature: Cursor with GitHub Desktop Integration

## Branch: feature/cursor-with-github

### Summary
Implemented a new feature that allows users to open projects in both Cursor IDE and GitHub Desktop simultaneously with a single keyboard shortcut (_hyper+g). The feature ensures that GitHub Desktop gets the project path update while final focus remains on Cursor IDE.

#### Update: Window Path Extraction
- Added code to extract project paths from window titles by matching with known projects
- This enables GitHub Desktop integration even when selecting existing Cursor windows
- Implemented conditional handling to only update GitHub Desktop when valid paths are available

### Files Modified
- **AppManager.lua**: Added new functions for the integrated application launching
  - `launchCursorWithGitHubDesktop()` - Main implementation
  - `open_cursor_with_github()` - Helper function for hotkey binding

- **hotkeys.lua**: Added new hotkey binding
  - `_hyper+g` - Open Cursor with GitHub Desktop

- **README.md**: Updated with information about the new feature
  - Added to Recent Updates section

- **implementation_notes.md**: Created documentation for the feature
  - Detailed implementation approach
  - Design considerations
  - Potential future enhancements

### Testing
The feature was implemented based on the existing pattern for GitHub Desktop project selection. Manual testing should be performed to ensure:

1. Project selection menu appears correctly
2. Selected projects open in both applications
3. Final focus lands on Cursor
4. Custom paths in the search field work correctly

### Next Steps
1. Merge the feature branch into main
2. Collect user feedback
3. Consider implementing the enhancements listed in implementation_notes.md 
