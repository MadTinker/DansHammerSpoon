-- ProjectManager.lua - Project management utilities
-- Using singleton pattern to avoid multiple initializations
local HyperLogger = require('HyperLogger')
local log = HyperLogger.new()
-- Check if module is already initialized
if _G.ProjectManager then
    log:d('Returning existing ProjectManager module')
    return _G.ProjectManager
end

log:i('Initializing project management system')

local FileManager = require('FileManager')
local ProjectManager = {
    -- Store active project information
    activeProject = nil,
    projects = {},
    projectsFilePath = hs.configdir .. "/data/projects.json",

    -- UI state tracking
    uiState = {
        projectChooser = nil,
        projectWebView = nil,
        actionsChooser = nil,
        isVisible = false
    }
}

-- Load saved projects from file
function ProjectManager.loadProjects()
    log:d('Loading projects from file')
    if hs.fs.attributes(ProjectManager.projectsFilePath) then
        local success, data = pcall(function()
            local file = io.open(ProjectManager.projectsFilePath, "r")
            local content = file:read("*all")
            file:close()
            return hs.json.decode(content)
        end)

        if success and data then
            ProjectManager.projects = data.projects or {}
            if data.activeProject then
                ProjectManager.activeProject = data.activeProject
            end
            log:i('Loaded ' .. #ProjectManager.projects .. ' projects from file')
            return true
        else
            log:w('Failed to load projects from file: ' .. (data or "unknown error"))
        end
    else
        log:i('Projects file does not exist yet')
    end
    return false
end

-- Import projects from FileManager
function ProjectManager.importFromFileManager()
    log:d('Importing projects from FileManager')
    local importedCount = 0

    local fileManagerProjects = FileManager.getProjectsList()
    if not fileManagerProjects or #fileManagerProjects == 0 then
        log:w('No projects found in FileManager to import')
        return 0
    end

    for _, project in ipairs(fileManagerProjects) do
        -- Check if project with same name already exists
        local exists = false
        for _, existingProject in ipairs(ProjectManager.projects) do
            if existingProject.name == project.name then
                exists = true
                break
            end
        end

        if not exists then
            -- Create a new project from FileManager project data
            ProjectManager.addProject(project.name, project.path, "Imported from FileManager")
            importedCount = importedCount + 1
        end
    end

    if importedCount > 0 then
        log:i('Imported ' .. importedCount .. ' projects from FileManager')
        hs.alert.show("Imported " .. importedCount .. " projects from FileManager")
    else
        log:i('No new projects imported from FileManager')
    end

    return importedCount
end

-- Export active project to FileManager (for future integration)
function ProjectManager.exportActiveToFileManager()
    log:d('Exporting active project to FileManager')

    local project = ProjectManager.getActiveProject()
    if not project then
        log:w('No active project to export')
        hs.alert.show("No active project to export to FileManager")
        return false
    end

    -- This is a placeholder for future integration
    -- FileManager doesn't currently have a function to add projects
    -- But this prepares for future integration
    log:i('Exported active project to FileManager: ' .. project.name)
    hs.alert.show("Active project exported to FileManager: " .. project.name)

    return true
end
-- Save projects to file
function ProjectManager.saveProjects()
    log:d('Saving projects to file')
    local data = {
        projects = ProjectManager.projects,
        activeProject = ProjectManager.activeProject
    }

    local success, err = pcall(function()
        local file = io.open(ProjectManager.projectsFilePath, "w")
        local content = hs.json.encode(data)
        file:write(content)
        file:close()
    end)

    if success then
        log:i('Saved ' .. #ProjectManager.projects .. ' projects to file')
        return true
    else
        log:e('Failed to save projects to file: ' .. err)
        return false
    end
end

-- Add a new project
function ProjectManager.addProject(name, path, description)
    log:d('Adding new project: ' .. name)
    -- Generate a unique ID for the project
    local id = hs.host.uuid()

    local project = {
        id = id,
        name = name,
        path = path,
        description = description or "",
        created = os.time(),
        lastModified = os.time()
    }

    table.insert(ProjectManager.projects, project)
    ProjectManager.saveProjects()
    log:i('Added new project: ' .. name)
    return project
end

-- Set active project
function ProjectManager.setActiveProject(projectId)
    log:d('Setting active project: ' .. projectId)
    for _, project in ipairs(ProjectManager.projects) do
        if project.id == projectId then
            ProjectManager.activeProject = projectId
            ProjectManager.saveProjects()
            log:i('Active project set to: ' .. project.name)
            return true
        end
    end

    log:w('Project not found with ID: ' .. projectId)
    return false
end

-- Get active project details
function ProjectManager.getActiveProject()
    if not ProjectManager.activeProject then
        log:d('No active project set')
        return nil
    end

    for _, project in ipairs(ProjectManager.projects) do
        if project.id == ProjectManager.activeProject then
            return project
        end
    end

    log:w('Active project ID set but project not found: ' .. ProjectManager.activeProject)
    return nil
end

-- Remove a project
function ProjectManager.removeProject(projectId)
    log:d('Removing project: ' .. projectId)
    for i, project in ipairs(ProjectManager.projects) do
        if project.id == projectId then
            table.remove(ProjectManager.projects, i)

            -- If we removed the active project, clear it
            if ProjectManager.activeProject == projectId then
                ProjectManager.activeProject = nil
            end

            ProjectManager.saveProjects()
            log:i('Removed project: ' .. project.name)
            return true
        end
    end

    log:w('Project not found for removal: ' .. projectId)
    return false
end

-- Update project details
function ProjectManager.updateProject(projectId, updates)
    log:d('Updating project: ' .. projectId)
    for i, project in ipairs(ProjectManager.projects) do
        if project.id == projectId then
            -- Update fields with new values
            for k, v in pairs(updates) do
                project[k] = v
            end

            project.lastModified = os.time()
            ProjectManager.saveProjects()
            log:i('Updated project: ' .. project.name)
            return true
        end
    end

    log:w('Project not found for update: ' .. projectId)
    return false
end

-- Hide any open UI elements
function ProjectManager.hideUI()
    log:d('Hiding ProjectManager UI elements')

    -- Hide project chooser if open
    if ProjectManager.uiState.projectChooser then
        ProjectManager.uiState.projectChooser:hide()
    end

    -- Hide webview if open
    if ProjectManager.uiState.projectWebView then
        ProjectManager.uiState.projectWebView:hide()
        -- Don't delete webview here, just hide it
    end

    -- Hide actions chooser if open
    if ProjectManager.uiState.actionsChooser then
        ProjectManager.uiState.actionsChooser:hide()
    end

    ProjectManager.uiState.isVisible = false
    log:i('ProjectManager UI hidden')
end

-- Reset UI state by closing and clearing all UI elements
function ProjectManager.resetUI()
    log:d('Resetting ProjectManager UI state')

    -- Close and clear project chooser
    if ProjectManager.uiState.projectChooser then
        ProjectManager.uiState.projectChooser:delete()
        ProjectManager.uiState.projectChooser = nil
    end

    -- Close and clear webview
    if ProjectManager.uiState.projectWebView then
        ProjectManager.uiState.projectWebView:delete()
        ProjectManager.uiState.projectWebView = nil
    end

    -- Close and clear actions chooser
    if ProjectManager.uiState.actionsChooser then
        ProjectManager.uiState.actionsChooser:delete()
        ProjectManager.uiState.actionsChooser = nil
    end

    ProjectManager.uiState.isVisible = false
    log:i('ProjectManager UI reset')
    hs.alert.show("Project Manager UI reset")
end

-- Toggle project manager UI (show/hide)
function ProjectManager.toggleProjectManager()
    log:d('Toggling project manager UI')

    if ProjectManager.uiState.isVisible then
        ProjectManager.hideUI()
        log:i('Project manager UI hidden')
    else
        ProjectManager.showProjectManager()
        log:i('Project manager UI shown')
    end
end
-- Show project management UI
function ProjectManager.showProjectManager()
    log:d('Showing project manager UI')

    -- If UI is already visible, hide it first to prevent multiple instances
    if ProjectManager.uiState.isVisible then
        ProjectManager.hideUI()
    end
    local choices = {}

    -- Add option to create new project
    table.insert(choices, {
        text = "➕ Create New Project",
        subText = "Add a new project to manage",
        image = hs.image.imageFromName("NSAddTemplate"),
        id = "new"
    })

    -- Add option to import from FileManager
    table.insert(choices, {
        text = "📥 Import from FileManager",
        subText = "Import projects from FileManager's list",
        image = hs.image.imageFromName("NSDownloadTemplate"),
        id = "import"
    })
    -- Add all projects
    for _, project in ipairs(ProjectManager.projects) do
        local isActive = project.id == ProjectManager.activeProject
        table.insert(choices, {
            text = (isActive and "✅ " or "") .. project.name,
            subText = project.description .. " - " .. project.path,
            path = project.path,
            id = project.id,
            image = hs.image.imageFromName(isActive and "NSAdvanced" or "NSBookmark")
        })
    end

    -- Create new chooser or reuse existing one
    if not ProjectManager.uiState.projectChooser then
        ProjectManager.uiState.projectChooser = hs.chooser.new(function(selection)
            if not selection then
                ProjectManager.uiState.isVisible = false
                return
            end

            if selection.id == "new" then
                ProjectManager.showNewProjectDialog()
            elseif selection.id == "import" then
                ProjectManager.importFromFileManager()
                -- Refresh the project list
                ProjectManager.showProjectManager()
            else
                ProjectManager.showProjectActions(selection.id)
            end
        end)
    end

    local chooser = ProjectManager.uiState.projectChooser
    chooser:searchSubText(true)
    chooser:choices(choices)
    chooser:placeholderText("Select or create a project")
    chooser:show()
    ProjectManager.uiState.isVisible = true
end

-- Dialog to create a new project
function ProjectManager.showNewProjectDialog()
    log:d('Showing new project dialog')

    -- Hide project chooser while editing
    if ProjectManager.uiState.projectChooser then
        ProjectManager.uiState.projectChooser:hide()
    end
    -- Create a simple dialog for project creation
    local rect = hs.geometry.rect(100, 100, 600, 300)
    -- Delete existing webview if it exists
    if ProjectManager.uiState.projectWebView then
        ProjectManager.uiState.projectWebView:delete()
    end
    local webView = hs.webview.new(rect)
    ProjectManager.uiState.projectWebView = webView

    local html = [[
    <!DOCTYPE html>
    <html>
    <head>
        <style>
            body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; margin: 20px; }
            h1 { font-size: 18px; margin-bottom: 20px; }
            label { display: block; margin-bottom: 5px; font-weight: bold; }
            input, textarea { width: 100%; padding: 8px; margin-bottom: 15px; border-radius: 4px; border: 1px solid #ccc; }
            textarea { height: 80px; resize: vertical; }
            .buttons { display: flex; justify-content: flex-end; gap: 10px; }
            button { padding: 8px 16px; border-radius: 4px; cursor: pointer; }
            .cancel { background: #f1f1f1; border: 1px solid #ccc; }
            .save { background: #0075ff; color: white; border: none; }
        </style>
    </head>
    <body>
        <h1>Create New Project</h1>
        <form id="projectForm">
            <label for="name">Project Name:</label>
            <input type="text" id="name" name="name" required>

            <label for="path">Project Path:</label>
            <input type="text" id="path" name="path" required>

            <label for="description">Description:</label>
            <textarea id="description" name="description"></textarea>

            <div class="buttons">
                <button type="button" class="cancel" onclick="cancelForm()">Cancel</button>
                <button type="button" class="save" onclick="submitForm()">Save Project</button>
            </div>
        </form>

        <script>
            function cancelForm() {
                window.location = 'hammerspoon://projectManager/cancel';
            }

            function submitForm() {
                const name = document.getElementById('name').value;
                const path = document.getElementById('path').value;
                const description = document.getElementById('description').value;

                if (!name || !path) {
                    alert('Name and path are required!');
                    return;
                }

                window.location = `hammerspoon://projectManager/create?name=${encodeURIComponent(name)}&path=${encodeURIComponent(path)}&description=${encodeURIComponent(description)}`;
            }

            document.getElementById('path').addEventListener('dblclick', function() {
                window.location = 'hammerspoon://projectManager/browse';
            });
        </script>
    </body>
    </html>
    ]]

    webView:html(html)
    webView:allowNewWindows(false)
    webView:allowTextEntry(true)
    webView:windowTitle("Create New Project")
    webView:bringToFront(true)
    webView:show()

    webView:setCallback(function(webview, message)
        local action = message.urlParts.host
        local params = message.urlParts.queryItems

        if action == "cancel" then
            webview:delete()
            ProjectManager.uiState.projectWebView = nil
            ProjectManager.uiState.isVisible = false
        elseif action == "create" then
            if params.name and params.path then
                local project = ProjectManager.addProject(params.name, params.path, params.description)
                if project then
                    hs.alert.show("Project created: " .. params.name)
                    ProjectManager.setActiveProject(project.id)
                else
                    hs.alert.show("Failed to create project")
                end
            end
            webview:delete()
            ProjectManager.uiState.projectWebView = nil
            ProjectManager.uiState.isVisible = false
        elseif action == "browse" then
            -- Show file picker dialog for project path
            hs.dialog.chooseFileOrFolder(function(path)
                if path then
                    webview:evaluateJavaScript('document.getElementById("path").value = "' .. path .. '"')
                end
            end, {
                allowDirectories = true,
                allowFiles = false,
                title = "Select Project Directory"
            })
        end
    end)
end

-- Show actions for a specific project
function ProjectManager.showProjectActions(projectId)
    log:d('Showing project actions for: ' .. projectId)

    -- Hide project chooser while showing actions
    if ProjectManager.uiState.projectChooser then
        ProjectManager.uiState.projectChooser:hide()
    end
    local project = nil
    for _, p in ipairs(ProjectManager.projects) do
        if p.id == projectId then
            project = p
            break
        end
    end

    if not project then
        log:e('Project not found for actions: ' .. projectId)
        hs.alert.show("Project not found")
        ProjectManager.uiState.isVisible = false
        return
    end

    local isActive = projectId == ProjectManager.activeProject

    local actions = {
        {
            text = isActive and "✓ Currently Active" or "Set as Active Project",
            subText = "Make this the current active project",
            image = hs.image.imageFromName("NSStatusAvailable"),
            action = "activate"
        },
        {
            text = "Edit Project Details",
            subText = "Modify project information",
            image = hs.image.imageFromName("NSEditTemplate"),
            action = "edit"
        },
        {
            text = "Open Project Directory",
            subText = "Open " .. project.path .. " in Finder",
            image = hs.image.imageFromName("NSFolder"),
            action = "open"
        },
        {
            text = "Open in Editor",
            subText = "Open project in default code editor",
            image = hs.image.imageFromName("NSApplicationIcon"),
            action = "editor"
        },
        {
            text = "Open Terminal Here",
            subText = "Open terminal in project directory",
            image = hs.image.imageFromName("NSTerminal"),
            action = "terminal"
        },
        {
            text = "Export to FileManager",
            subText = "Export this project to FileManager (future integration)",
            image = hs.image.imageFromName("NSShareTemplate"),
            action = "export"
        },
        {
            text = "Delete Project",
            subText = "Remove this project from your list",
            image = hs.image.imageFromName("NSTrashFull"),
            action = "delete"
        }
    }

    -- Delete existing actions chooser if it exists
    if ProjectManager.uiState.actionsChooser then
        ProjectManager.uiState.actionsChooser:delete()
    end

    ProjectManager.uiState.actionsChooser = hs.chooser.new(function(selection)
        if not selection then
            ProjectManager.uiState.isVisible = false
            return
        end
        if selection.action == "activate" then
            if not isActive then
                ProjectManager.setActiveProject(projectId)
                hs.alert.show("Active project set to: " .. project.name)
            end
        elseif selection.action == "edit" then
            ProjectManager.showEditProjectDialog(project)
        elseif selection.action == "open" then
            hs.execute("open '" .. project.path .. "'")
            ProjectManager.uiState.isVisible = false
        elseif selection.action == "editor" then
            hs.execute("open -a 'Code' '" .. project.path .. "'")
            ProjectManager.uiState.isVisible = false
        elseif selection.action == "terminal" then
            hs.execute("open -a 'Terminal' '" .. project.path .. "'")
            ProjectManager.uiState.isVisible = false
        elseif selection.action == "export" then
            -- Set as active project first if not already active
            if not isActive then
                ProjectManager.setActiveProject(projectId)
            end
            ProjectManager.exportActiveToFileManager()
        elseif selection.action == "delete" then
            local button, _ = hs.dialog.blockAlert(
                "Delete Project",
                "Are you sure you want to delete the project '" .. project.name .. "'?",
                "Delete",
                "Cancel",
                "NSCriticalAlertStyle"
            )

            if button == "Delete" then
                if ProjectManager.removeProject(projectId) then
                    hs.alert.show("Project removed: " .. project.name)
                else
                    hs.alert.show("Failed to remove project")
                end
            end
        end
    end)

    local chooser = ProjectManager.uiState.actionsChooser
    chooser:searchSubText(true)
    chooser:choices(actions)
    chooser:placeholderText("Actions for: " .. project.name)
    chooser:show()
end

-- Edit project dialog
function ProjectManager.showEditProjectDialog(project)
    log:d('Showing edit project dialog for: ' .. project.id)

    -- Delete existing webview if it exists
    if ProjectManager.uiState.projectWebView then
        ProjectManager.uiState.projectWebView:delete()
    end
    local rect = hs.geometry.rect(100, 100, 600, 300)
    local webView = hs.webview.new(rect)
    ProjectManager.uiState.projectWebView = webView

    local html = string.format([[
    <!DOCTYPE html>
    <html>
    <head>
        <style>
            body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; margin: 20px; }
            h1 { font-size: 18px; margin-bottom: 20px; }
            label { display: block; margin-bottom: 5px; font-weight: bold; }
            input, textarea { width: 100%%; padding: 8px; margin-bottom: 15px; border-radius: 4px; border: 1px solid #ccc; }
            textarea { height: 80px; resize: vertical; }
            .buttons { display: flex; justify-content: flex-end; gap: 10px; }
            button { padding: 8px 16px; border-radius: 4px; cursor: pointer; }
            .cancel { background: #f1f1f1; border: 1px solid #ccc; }
            .save { background: #0075ff; color: white; border: none; }
        </style>
    </head>
    <body>
        <h1>Edit Project</h1>
        <form id="projectForm">
            <label for="name">Project Name:</label>
            <input type="text" id="name" name="name" required value="%s">

            <label for="path">Project Path:</label>
            <input type="text" id="path" name="path" required value="%s">

            <label for="description">Description:</label>
            <textarea id="description" name="description">%s</textarea>

            <div class="buttons">
                <button type="button" class="cancel" onclick="cancelForm()">Cancel</button>
                <button type="button" class="save" onclick="submitForm()">Update Project</button>
            </div>
        </form>

        <script>
            function cancelForm() {
                window.location = 'hammerspoon://projectManager/cancel';
            }

            function submitForm() {
                const name = document.getElementById('name').value;
                const path = document.getElementById('path').value;
                const description = document.getElementById('description').value;

                if (!name || !path) {
                    alert('Name and path are required!');
                    return;
                }

                window.location = `hammerspoon://projectManager/update?id=%s&name=${encodeURIComponent(name)}&path=${encodeURIComponent(path)}&description=${encodeURIComponent(description)}`;
            }

            document.getElementById('path').addEventListener('dblclick', function() {
                window.location = 'hammerspoon://projectManager/browse';
            });
        </script>
    </body>
    </html>
    ]],
        project.name,
        project.path,
        project.description,
        project.id
    )

    webView:html(html)
    webView:allowNewWindows(false)
    webView:allowTextEntry(true)
    webView:windowTitle("Edit Project")
    webView:bringToFront(true)
    webView:show()

    webView:setCallback(function(webview, message)
        local action = message.urlParts.host
        local params = message.urlParts.queryItems

        if action == "cancel" then
            webview:delete()
            ProjectManager.uiState.projectWebView = nil
            ProjectManager.uiState.isVisible = false
        elseif action == "update" then
            if params.id and params.name and params.path then
                local updates = {
                    name = params.name,
                    path = params.path,
                    description = params.description or ""
                }

                if ProjectManager.updateProject(params.id, updates) then
                    hs.alert.show("Project updated: " .. params.name)
                else
                    hs.alert.show("Failed to update project")
                end
            end
            webview:delete()
            ProjectManager.uiState.projectWebView = nil
            ProjectManager.uiState.isVisible = false
        elseif action == "browse" then
            hs.dialog.chooseFileOrFolder(function(path)
                if path then
                    webview:evaluateJavaScript('document.getElementById("path").value = "' .. path .. '"')
                end
            end, {
                allowDirectories = true,
                allowFiles = false,
                title = "Select Project Directory"
            })
        end
    end)
end

-- Show active project info
function ProjectManager.showActiveProjectInfo()
    local project = ProjectManager.getActiveProject()

    if not project then
        hs.alert.show("No active project selected")
        return
    end

    local message = string.format("Active Project: %s\nPath: %s\n%s",
        project.name,
        project.path,
        project.description and project.description ~= "" and "\nDescription: " .. project.description or ""
    )

    hs.alert.show(message, 3)
end

-- Initialize the module
function ProjectManager.init()
    log:d('Initializing ProjectManager module')
    -- Load saved projects from file
    local loaded = ProjectManager.loadProjects()

    -- If no saved projects or first run, import from FileManager
    if not loaded or (#ProjectManager.projects == 0) then
        log:i('No saved projects found, importing from FileManager')
        ProjectManager.importFromFileManager()
    end
    return ProjectManager
end

-- Save in global environment for module reuse
_G.ProjectManager = ProjectManager.init()
return _G.ProjectManager
