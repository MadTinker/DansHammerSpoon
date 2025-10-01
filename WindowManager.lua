-- WindowManager.lua - Window management utilities
-- Using singleton pattern to avoid multiple initializations
local __FILE__ = 'WindowManager.lua'
local HyperLogger = require('HyperLogger')
local log = HyperLogger.new()
-- Check if the module is already initialized
if _G.WindowManager then
    return _G.WindowManager
end
log:d('Initializing window management system', __FILE__, 22)

hs.window.animationDuration = 0.0
local WindowManager = {
    -- State variables
    gap = 5,
    cols = 4,
    counter = 0,
    layoutCounter = 0,
    rowCounter = 0,
    colCounter = 0,
    moveStep = 150,

    lastWindowPosition = {},
    lastWindowPositions = {},

    -- Current state tracking
    currentWindow = nil,
    currentScreen = nil,
    currentFrame = nil,

    -- Layout state
    row = 0,
    sectionWidth = 0,
    sectionHeight = 0,

    -- Multi-window layout management
    savedLayouts = {},

    -- Toggle layout state tracking
    rightLayoutState = { isSmall = true },
    leftLayoutState = { isSmall = true },
    fullLayoutState = { currentState = 0 } -- 0: fullScreen, 1: nearlyFull, 2: trueFull
}

-- Layouts
local miniLayouts = {
    { -- Layout 1
        x = function(max) return max.x + (max.w * 0.72) end,
        y = function(max) return max.y + (max.h * 0.01) + 25 end,
        w = function(max) return max.w * 0.26 end,
        h = function(max) return max.h * 0.97 end
    },
    { -- Layout 2
        x = function(max) return max.x + (max.w * 0.76) end,
        y = function(max) return max.y + (max.h * 0.01) - 25 end,
        w = function(max) return max.w * 0.24 end,
        h = function(max) return max.h * 0.97 end
    },
    { -- Layout 3
        x = function(max) return max.x + (max.w * 0.7) end,
        y = function(max) return max.y + (max.h * 0.01) - 30 end,
        w = function(max) return max.w * 0.5 end,
        h = function(max) return max.h * 0.9 end
    },
    { -- Layout 4
        x = function(max) return max.x + (max.w * 0.5) end,
        y = function(max) return max.y + (max.h * 0.01) end,
        w = function(max) return max.w * 0.5 end,
        h = function(max) return max.h * 0.9 end
    }
}

local standardLayouts = {
    fullScreen = { -- Full screen
        x = function(max) return max.x + 35 end,
        y = function(max) return max.y + 35 end,
        w = function(max) return max.w - 70 end,
        h = function(max) return max.h - 70 end
    },
    trueFull = { -- 100% centered
        x = function(max) return max.x end,
        y = function(max) return max.y end,
        w = function(max) return max.w end,
        h = function(max) return max.h end
    },
    nearlyFull = { -- 90% centered
        x = function(max) return max.x + (max.w * 0.05) end,
        y = function(max) return max.y + (max.h * 0.05) end,
        w = function(max) return max.w - (max.w * 0.1) end,
        h = function(max) return max.h - (max.h * 0.1) end
    },
    sevenByFive = { -- 70% centered
        x = function(max) return max.x + (max.w * 0.15) end,
        y = function(max) return max.y + (max.h * 0.15) end,
        w = function(max) return max.w - (max.w * 0.3) end,
        h = function(max) return max.h - (max.h * 0.3) end
    },
    leftHalf = { -- Left half
        x = function(max) return max.x end,
        y = function(max) return max.y end,
        w = function(max) return max.w / 2 end,
        h = function(max) return max.h end
    },
    rightHalf = { -- Right half
        x = function(max) return max.x + (max.w / 2) end,
        y = function(max) return max.y end,
        w = function(max) return max.w / 2 end,
        h = function(max) return max.h end
    },
    leftSmall = { -- Small left side
        x = function(max) return max.x end,
        y = function(max) return max.y + (max.h * 0.1) end,
        w = function(max) return max.w * 0.4 end,
        h = function(max) return max.h * 0.8 end
    },
    rightSmall = { -- Small right side
        x = function(max) return max.x + (max.w * 0.6) end,
        y = function(max) return max.y + (max.h * 0.1) end,
        w = function(max) return max.w * 0.4 end,
        h = function(max) return max.h * 0.8 end
    },
    topLeft = { -- Top left corner
        x = function(max) return max.x end,
        y = function(max) return max.y end,
        w = function(max) return max.w / 2 end,
        h = function(max) return max.h / 2 end
    },
    topRight = { -- Top right corner
        x = function(max) return max.x + (max.w / 2) end,
        y = function(max) return max.y end,
        w = function(max) return max.w / 2 end,
        h = function(max) return max.h / 2 end
    },
    bottomLeft = { -- Bottom left corner
        x = function(max) return max.x end,
        y = function(max) return max.y + (max.h / 2) end,
        w = function(max) return max.w / 2 end,
        h = function(max) return max.h / 2 end
    },
    bottomRight = { -- Bottom right corner
        x = function(max) return max.x + (max.w / 2) end,
        y = function(max) return max.y + (max.h / 2) end,
        w = function(max) return max.w / 2 end,
        h = function(max) return max.h / 2 end
    },
    leftWide = { -- 72% left side
        x = function(max) return max.x + 30 end,
        y = function(max) return max.y + (max.h * 0.01) end,
        w = function(max) return max.w * 0.72 - 30 end,
        h = function(max) return max.h * 0.98 end
    },
    rightNarrow = { -- 27% right side
        x = function(max) return max.x + (max.w * 0.73) end,
        y = function(max) return max.y + (max.h * 0.01) end,
        w = function(max) return max.w * 0.27 end,
        h = function(max) return max.h * 0.98 end
    },
    splitVertical = { -- Top half
        x = function(max) return max.x end,
        y = function(max) return max.y end,
        w = function(max) return max.w end,
        h = function(max) return max.h / 2 end
    },
    splitHorizontal = { -- Bottom half
        x = function(max) return max.x end,
        y = function(max) return max.y + (max.h / 2) end,
        w = function(max) return max.w end,
        h = function(max) return max.h / 2 end
    },
    centerScreen = { -- 80% centered
        x = function(max) return max.x + (max.w * 0.1) end,
        y = function(max) return max.y + (max.h * 0.1) end,
        w = function(max) return max.w - (max.w * 0.2) end,
        h = function(max) return max.h - (max.h * 0.2) end
    },
    bottomHalf = { -- Bottom half
        x = function(max) return max.x end,
        y = function(max) return max.y + (max.h / 2) end,
        w = function(max) return max.w end,
        h = function(max) return max.h / 2 end
    }
}

local function calculatePosition(counter, max, rows)
    WindowManager.row = math.floor(counter / WindowManager.cols)
    local col = counter % WindowManager.cols
    local x = max.x + (col * (max.w / WindowManager.cols + WindowManager.gap))
    local y = max.y + (WindowManager.row * (max.h / rows + WindowManager.gap))
    return x, y
end

-- Window Management Functions
function WindowManager.miniShuffle()
    local win = hs.window.focusedWindow()
    if not win then return end

    local screen = win:screen()
    local max = screen:frame()

    -- Get current layout based on counter
    local layout = miniLayouts[(WindowManager.counter % #miniLayouts) + 1]

    -- Create new frame using layout functions
    local newFrame = hs.geometry.rect(
        layout.x(max),
        layout.y(max),
        layout.w(max),
        layout.h(max)
    )

    -- Apply the frame using the robust helper
    WindowManager.setFrameInScreenWithRetry(win, newFrame)
    WindowManager.currentFrame = newFrame

    -- Increment counter
    WindowManager.counter = (WindowManager.counter + 1) % #miniLayouts
end

function WindowManager.halfShuffle(numRows, numCols)
    numRows = numRows or 3
    numCols = numCols or 2

    local win = hs.window.focusedWindow()
    if not win then return end

    local screen = win:screen()
    local max = screen:frame()

    local sectionWidth = max.w / numCols
    local sectionHeight = max.h / numRows

    local colCounter = WindowManager.colCounter
    local rowCounter = WindowManager.rowCounter

    -- Reverse the direction: start from bottom-right and go in reverse
    local x = max.x + ((numCols - 1 - colCounter) * sectionWidth)
    local y = max.y + ((numRows - 1 - rowCounter) * sectionHeight)

    -- Create a geometry object for the new frame
    local newFrame = hs.geometry.rect(x, y, sectionWidth, sectionHeight)
    log.i('Half shuffle w/ position (reversed): ', rowCounter, colCounter)

    -- Apply the frame using the robust helper
    WindowManager.setFrameInScreenWithRetry(win, newFrame)
    WindowManager.currentFrame = newFrame

    -- Update counters in reverse direction
    WindowManager.rowCounter = (WindowManager.rowCounter + 1) % numRows
    if WindowManager.rowCounter == 0 then
        WindowManager.colCounter = (WindowManager.colCounter + 1) % numCols
    end
end

function WindowManager.applyLayout(layoutName)
    local win = hs.window.focusedWindow()
    if not win then
        hs.alert.show('No focused window found')
        return
    end

    local layout = standardLayouts[layoutName]
    if not layout then
        hs.alert.show('Invalid layout name: ' .. layoutName)
        return
    end

    local screen = win:screen()
    local max = screen:frame()

    -- Calculate new frame using layout functions
    local newFrame = hs.geometry.rect(
        layout.x(max),
        layout.y(max),
        layout.w(max),
        layout.h(max)
    )

    -- Save original frame for logging
    local originalFrame = win:frame()

    -- Use our robust helper function to set the frame
    local success = WindowManager.setFrameInScreenWithRetry(win, newFrame)

    -- Log the result
    if success then
        log.i('Successfully applied layout:', layoutName)
    else
        log.w('Applied layout with potential issues:', layoutName)
    end

    log.d('Layout change details:', layoutName, 'from', hs.inspect(originalFrame), 'to', hs.inspect(newFrame))
end

function WindowManager.moveToScreen(direction, position)
    local win = hs.window.focusedWindow()
    local screen = win:screen()
    local nextScreen = (direction == "next") and screen:next() or screen:previous()
    local max = nextScreen:frame()

    -- Create a geometry object for the new frame
    local newFrame
    if position == "left" then
        newFrame = hs.geometry.rect(max.x, max.y, max.w / 2, max.h)
    else
        newFrame = hs.geometry.rect(max.x + (max.w / 2), max.y, max.w / 2, max.h / 2)
    end

    -- First move to screen
    win:moveToScreen(nextScreen)
    -- Then apply the frame using the robust helper
    hs.timer.doAfter(0.1, function()
        WindowManager.setFrameInScreenWithRetry(win, newFrame)
    end)
end

function WindowManager.moveWindow(direction)
    local win = hs.window.focusedWindow()
    if not win then return end

    local f = win:frame()

    local movements = {
        left = { x = -WindowManager.moveStep, y = 0 },
        right = { x = WindowManager.moveStep, y = 0 },
        up = { x = 0, y = -WindowManager.moveStep },
        down = { x = 0, y = WindowManager.moveStep }
    }

    local move = movements[direction]
    f.x = f.x + move.x
    f.y = f.y + move.y
    hs.window.animationDuration = 0.0
    win:setFrame(f, 0.0)
    -- WindowManager.currentFrame = f
end

function WindowManager.moveWindowMouseCenter()
    local win = hs.window.focusedWindow()
    if not win then return end

    local f = win:frame()
    local mouse = hs.mouse.absolutePosition()
    f.x = mouse.x - (f.w / 2)
    f.y = mouse.y - (f.h / 2)
    hs.window.animationDuration = 0.0
    win:setFrame(f, 0.0)
    -- WindowManager.currentFrame = f
end

function WindowManager.moveWindowMouseCorner()
    local win = hs.window.focusedWindow()
    if not win then return end

    local f = win:frame()
    local mouse = hs.mouse.absolutePosition()
    f.x = mouse.x
    f.y = mouse.y
    hs.window.animationDuration = 0.0
    win:setFrame(f, 0.0)
    --  WindowManager.currentFrame = f
end

-- Window Position Save/Restore
function WindowManager.saveWindowPosition()
    log.i('Saving window position')
    local win = hs.window.focusedWindow()
    if win then
        WindowManager.lastWindowPosition[win:id()] = win:frame()
        log.d('Saved position for window:', win:id(), hs.inspect(win:frame()))
        hs.alert.show("Window position saved")
    else
        log.w('No focused window to save position')
    end
end

-- Helper function to set window frame with verification and retry
function WindowManager.setFrameInScreenWithRetry(win, newFrame, retryCount)
    retryCount = retryCount or 3

    -- Ensure animations are always disabled for reliable positioning
    hs.window.animationDuration = 0

    -- Try to set the frame
    win:setFrame(newFrame, 0)
    hs.timer.usleep(300000)

    -- Verify the frame was set correctly by comparing with a small tolerance
    local resultFrame = win:frame()
    local frameCorrect =
        math.abs(resultFrame.x - newFrame.x) < 20 and
        math.abs(resultFrame.y - newFrame.y) < 20 and
        math.abs(resultFrame.w - newFrame.w) < 20 and
        math.abs(resultFrame.h - newFrame.h) < 20

    -- If frame wasn't applied correctly and we have retries left, try alternative methods
    if not frameCorrect and retryCount > 0 then
        log.w('Frame set attempt failed, trying alternative method. Attempts left:', retryCount)

        -- Try with workarounds method
        win:setFrameWithWorkarounds(newFrame)

        -- Add a small delay
        hs.timer.usleep(300000)

        -- Recursive call with one fewer retry
        return WindowManager.setFrameInScreenWithRetry(win, newFrame, retryCount - 1)
    end

    return frameCorrect
end
function WindowManager.restoreWindowPosition()
    log.i('Restoring window position')
    local win = hs.window.focusedWindow()
    if win and WindowManager.lastWindowPosition[win:id()] then
        log.d('Restoring position for window:', win:id(), hs.inspect(WindowManager.lastWindowPosition[win:id()]))
        WindowManager.setFrameInScreenWithRetry(win, WindowManager.lastWindowPosition[win:id()])
        hs.alert.show("Window position restored")
    else
        log.w('No saved position found for window:', win and win:id() or 'no window focused')
    end
end

function WindowManager.saveAllWindowPositions()
    local wins = hs.window.allWindows()
    for _, win in ipairs(wins) do
        WindowManager.lastWindowPositions[win:id()] = win:frame()
    end
    hs.alert.show("All window positions saved")
end

function WindowManager.restoreAllWindowPositions()
    local wins = hs.window.allWindows()
    for _, win in ipairs(wins) do
        local savedPosition = WindowManager.lastWindowPositions[win:id()]
        if savedPosition then
            win:setFrame(savedPosition, 0)
        end
    end
    hs.alert.show("All window positions restored")
end

function WindowManager.resetShuffleCounters()
    hs.alert.show("Shuffle counters reset")
    WindowManager.rowCounter = 0
    WindowManager.colCounter = 0
    WindowManager.counter = 0
    WindowManager.layoutCounter = 0
    WindowManager.row = 0
    WindowManager.currentWindow = nil
    WindowManager.currentScreen = nil
    WindowManager.currentFrame = nil
    WindowManager.sectionWidth = 0
    WindowManager.sectionHeight = 0
end
-- Toggle layout functions
function WindowManager.toggleRightLayout()
    WindowManager.rightLayoutState.isSmall = not WindowManager.rightLayoutState.isSmall
    if WindowManager.rightLayoutState.isSmall then
        WindowManager.applyLayout('rightSmall')
        log:d("Right Small Layout", __FILE__, 485)
    else
        WindowManager.applyLayout('rightHalf')
        log:d("Right Half Layout", __FILE__, 488)
    end
end

function WindowManager.toggleLeftLayout()
    WindowManager.leftLayoutState.isSmall = not WindowManager.leftLayoutState.isSmall
    if WindowManager.leftLayoutState.isSmall then
        WindowManager.applyLayout('leftSmall')
        log:d("Left Small Layout", __FILE__, 495)
    else
        WindowManager.applyLayout('leftHalf')
        log:d("Left Half Layout", __FILE__, 498)
    end
end

function WindowManager.toggleFullLayout()
    WindowManager.fullLayoutState.currentState = (WindowManager.fullLayoutState.currentState + 1) % 3
    if WindowManager.fullLayoutState.currentState == 0 then
        WindowManager.applyLayout('fullScreen')
        log:d("Full Screen Layout", __FILE__, 505)
    elseif WindowManager.fullLayoutState.currentState == 1 then
        WindowManager.applyLayout('nearlyFull')
        log:d("Nearly Full Layout", __FILE__, 508)
    else
        WindowManager.applyLayout('trueFull')
        log:d("True Full Layout", __FILE__, 511)
    end
end

function WindowManager.toggleNativeFullScreen()
    local win = hs.window.focusedWindow()
    if win then
        win:setFullScreen(not win:isFullScreen())
    end
end

-- Multi-window layout management
function WindowManager.saveCurrentLayout(layoutName)
    log.i('Saving multi-window layout:', layoutName)

    -- Get all visible windows
    local allVisibleWindows = hs.window.visibleWindows()
    local savedWindows = {}

    for _, win in ipairs(allVisibleWindows) do
        -- Only include standard, non-minimized windows
        if win:isStandard() and not win:isMinimized() then
            -- Get information about each window
            local app = win:application()
            local appName = app and app:name() or "Unknown"
            local windowTitle = win:title() or "Untitled Window"
            local frame = win:frame()
            local screen = win:screen():getUUID()

            -- Store window information
            table.insert(savedWindows, {
                appName = appName,
                appBundleID = app and app:bundleID() or nil,
                windowTitle = windowTitle,
                frame = frame,
                screenUUID = screen,
                windowID = win:id()
            })

            log.d('Saved window in layout:', appName, windowTitle, hs.inspect(frame))
        end
    end

    -- Save layout
    WindowManager.savedLayouts[layoutName] = {
        windows = savedWindows,
        timestamp = os.time(),
        description = "Layout saved on " .. os.date("%Y-%m-%d %H:%M:%S")
    }

    hs.alert.show(string.format("Saved layout '%s' with %d windows", layoutName, #savedWindows))
    return #savedWindows
end

-- Smart Window Panic - Auto-tile all windows intelligently
function WindowManager.windowPanic()
    log.i('🚨 Window Panic! Auto-tiling all windows...')

    -- Get all visible, standard windows
    local allWindows = {}
    for _, win in ipairs(hs.window.visibleWindows()) do
        if win:isStandard() and not win:isMinimized() then
            local app = win:application()
            local appName = app and app:name() or "Unknown"

            -- Assign priority based on app type and window characteristics
            local priority = WindowManager.getWindowPriority(win, appName)

            table.insert(allWindows, {
                window = win,
                appName = appName,
                title = win:title() or "Untitled",
                originalFrame = win:frame(),
                priority = priority,
                screen = win:screen()
            })
        end
    end

    if #allWindows == 0 then
        hs.alert.show("No windows to arrange!")
        return
    end

    log.d('Found windows to arrange:', #allWindows)

    -- Save current positions before panic mode
    WindowManager.saveAllWindowPositions()

    -- Group windows by screen
    local windowsByScreen = {}
    for _, winInfo in ipairs(allWindows) do
        local screenId = winInfo.screen:id()
        if not windowsByScreen[screenId] then
            windowsByScreen[screenId] = {
                screen = winInfo.screen,
                windows = {}
            }
        end
        table.insert(windowsByScreen[screenId].windows, winInfo)
    end

    -- Arrange windows on each screen
    local totalArranged = 0
    for screenId, screenInfo in pairs(windowsByScreen) do
        totalArranged = totalArranged + WindowManager.arrangeWindowsOnScreen(screenInfo.screen, screenInfo.windows)
    end

    hs.alert.show(string.format("🚨 Panic mode! Arranged %d windows across %d screens",
        totalArranged, hs.fnutils.count(windowsByScreen)))

    log.i('Window panic completed. Arranged windows:', totalArranged)
end

-- Determine window priority for smart arrangement
function WindowManager.getWindowPriority(win, appName)
    local frame = win:frame()
    local area = frame.w * frame.h

    -- High priority apps (need more space)
    local highPriorityApps = {
        ["Code"] = true,
        ["Xcode"] = true,
        ["IntelliJ IDEA"] = true,
        ["Sublime Text"] = true,
        ["Atom"] = true,
        ["Visual Studio Code"] = true,
        ["Terminal"] = true,
        ["iTerm2"] = true,
        ["Hyper"] = true,
        ["Finder"] = true,
        ["Safari"] = true,
        ["Chrome"] = true,
        ["Firefox"] = true,
        ["Cursor"] = true,
        ["Claude"] = true
    }

    -- Medium priority apps
    local mediumPriorityApps = {
        ["Slack"] = true,
        ["Discord"] = true,
        ["Messages"] = true,
        ["Mail"] = true,
        ["Calendar"] = true,
        ["Notes"] = true,
        ["Obsidian"] = true,
        ["Notion"] = true
    }

    -- Calculate priority score (higher = more important)
    local priority = 1 -- base priority

    if highPriorityApps[appName] then
        priority = priority + 3
    elseif mediumPriorityApps[appName] then
        priority = priority + 2
    end

    -- Larger windows get slight priority boost
    if area > 800000 then -- roughly 1000x800 or larger
        priority = priority + 1
    end

    -- Currently focused window gets priority
    local focusedWin = hs.window.focusedWindow()
    if focusedWin and win:id() == focusedWin:id() then
        priority = priority + 2
    end

    return priority
end

-- Arrange windows on a specific screen
function WindowManager.arrangeWindowsOnScreen(screen, windows)
    if #windows == 0 then return 0 end

    local screenFrame = screen:frame()
    local margin = 10 -- margin around edges and between windows
    local workArea = {
        x = screenFrame.x + margin,
        y = screenFrame.y + margin,
        w = screenFrame.w - (margin * 2),
        h = screenFrame.h - (margin * 2)
    }

    log.d('Arranging windows on screen:', screen:name(), 'Windows:', #windows)

    -- Sort windows by priority (highest first)
    table.sort(windows, function(a, b) return a.priority > b.priority end)

    -- Choose arrangement strategy based on number of windows
    local arrangement = WindowManager.calculateOptimalArrangement(#windows, workArea)

    -- Apply the arrangement
    for i, winInfo in ipairs(windows) do
        if i <= #arrangement then
            local targetFrame = arrangement[i]

            -- Create geometry object
            local newFrame = hs.geometry.rect(
                workArea.x + targetFrame.x,
                workArea.y + targetFrame.y,
                targetFrame.w,
                targetFrame.h
            )

            -- Apply the frame
            local success = WindowManager.setFrameInScreenWithRetry(winInfo.window, newFrame)

            if success then
                log.d('Arranged window:', winInfo.appName, winInfo.title, 'at position', i)
            else
                log.w('Failed to arrange window:', winInfo.appName, winInfo.title)
            end
        end
    end

    return math.min(#windows, #arrangement)
end

-- Calculate optimal window arrangement based on count and screen space
function WindowManager.calculateOptimalArrangement(windowCount, workArea)
    local arrangements = {}

    if windowCount == 1 then
        -- Single window - use 80% of screen, centered
        local w = workArea.w * 0.8
        local h = workArea.h * 0.8
        arrangements[1] = {
            x = (workArea.w - w) / 2,
            y = (workArea.h - h) / 2,
            w = w,
            h = h
        }
    elseif windowCount == 2 then
        -- Two windows - split vertically
        local w = (workArea.w - 10) / 2
        local h = workArea.h
        arrangements[1] = { x = 0, y = 0, w = w, h = h }
        arrangements[2] = { x = w + 10, y = 0, w = w, h = h }
    elseif windowCount == 3 then
        -- Three windows - main window left, two stacked right
        local mainW = workArea.w * 0.6
        local sideW = workArea.w * 0.4 - 10
        local sideH = (workArea.h - 10) / 2

        arrangements[1] = { x = 0, y = 0, w = mainW, h = workArea.h }
        arrangements[2] = { x = mainW + 10, y = 0, w = sideW, h = sideH }
        arrangements[3] = { x = mainW + 10, y = sideH + 10, w = sideW, h = sideH }
    elseif windowCount == 4 then
        -- Four windows - 2x2 grid
        local w = (workArea.w - 10) / 2
        local h = (workArea.h - 10) / 2

        arrangements[1] = { x = 0, y = 0, w = w, h = h }
        arrangements[2] = { x = w + 10, y = 0, w = w, h = h }
        arrangements[3] = { x = 0, y = h + 10, w = w, h = h }
        arrangements[4] = { x = w + 10, y = h + 10, w = w, h = h }
    elseif windowCount <= 6 then
        -- Up to 6 windows - 2x3 grid
        local w = (workArea.w - 20) / 3
        local h = (workArea.h - 10) / 2

        for i = 1, windowCount do
            local row = math.floor((i - 1) / 3)
            local col = (i - 1) % 3
            arrangements[i] = {
                x = col * (w + 10),
                y = row * (h + 10),
                w = w,
                h = h
            }
        end
    elseif windowCount <= 9 then
        -- Up to 9 windows - 3x3 grid
        local w = (workArea.w - 20) / 3
        local h = (workArea.h - 20) / 3

        for i = 1, windowCount do
            local row = math.floor((i - 1) / 3)
            local col = (i - 1) % 3
            arrangements[i] = {
                x = col * (w + 10),
                y = row * (h + 10),
                w = w,
                h = h
            }
        end
    else
        -- More than 9 windows - 4xN grid
        local cols = 4
        local rows = math.ceil(windowCount / cols)
        local w = (workArea.w - ((cols - 1) * 10)) / cols
        local h = (workArea.h - ((rows - 1) * 10)) / rows

        for i = 1, windowCount do
            local row = math.floor((i - 1) / cols)
            local col = (i - 1) % cols
            arrangements[i] = {
                x = col * (w + 10),
                y = row * (h + 10),
                w = w,
                h = h
            }
        end
    end

    return arrangements
end

-- Restore from panic mode
function WindowManager.restoreFromPanic()
    log.i('Restoring windows from panic mode')
    WindowManager.restoreAllWindowPositions()
end
function WindowManager.restoreLayout(layoutName)
    log.i('Restoring layout:', layoutName)

    local layout = WindowManager.savedLayouts[layoutName]
    if not layout then
        hs.alert.show(string.format("No layout found with name '%s'", layoutName))
        return 0
    end

    local restoredCount = 0

    -- Get screens by UUID
    local screens = {}
    for _, screen in ipairs(hs.screen.allScreens()) do
        screens[screen:getUUID()] = screen
    end

    -- First focus all apps that need to be part of this layout
    -- This gives apps time to launch before trying to position windows
    for _, winInfo in ipairs(layout.windows) do
        if winInfo.appBundleID then
            hs.application.launchOrFocusByBundleID(winInfo.appBundleID)
        end
    end

    -- Wait a moment for apps to launch
    hs.timer.doAfter(0.5, function()
        -- Now try to restore each window
        for _, winInfo in ipairs(layout.windows) do
            -- Find the window - first try direct ID matching
            local win = hs.window.get(winInfo.windowID)

            -- If window not found by ID, try to find by app and title
            if not win and winInfo.appBundleID then
                local app = hs.application.get(winInfo.appBundleID)
                if app then
                    -- Try to find by title
                    for _, appWindow in ipairs(app:allWindows()) do
                        if appWindow:title() == winInfo.windowTitle then
                            win = appWindow
                            break
                        end
                    end

                    -- If still not found, just use the first window of the app
                    if not win and #app:allWindows() > 0 then
                        win = app:allWindows()[1]
                    end
                end
            end

            -- If we found a window to work with, set its position
            if win then
                local screen = screens[winInfo.screenUUID] or win:screen()
                local newFrame = hs.geometry.rect(winInfo.frame)

                -- Move to correct screen first if needed
                if screen and screen:id() ~= win:screen():id() then
                    win:moveToScreen(screen)
                end

                -- Apply the frame
                local success = WindowManager.setFrameInScreenWithRetry(win, newFrame)
                if success then
                    restoredCount = restoredCount + 1
                    log.d('Restored window position:', winInfo.appName, winInfo.windowTitle)
                else
                    log.w('Failed to restore window position:', winInfo.appName, winInfo.windowTitle)
                end
            else
                log.w('Could not find window to restore:', winInfo.appName, winInfo.windowTitle)
            end
        end

        hs.alert.show(string.format("Restored %d/%d windows from layout '%s'",
            restoredCount, #layout.windows, layoutName))
    end)

    return true
end

function WindowManager.listSavedLayouts()
    log.i('Listing all saved layouts')

    local layouts = {}
    for name, layout in pairs(WindowManager.savedLayouts) do
        table.insert(layouts, {
            name = name,
            windowCount = #layout.windows,
            timestamp = layout.timestamp,
            description = layout.description
        })
    end

    -- Sort by timestamp, most recent first
    table.sort(layouts, function(a, b) return a.timestamp > b.timestamp end)

    return layouts
end

function WindowManager.deleteLayout(layoutName)
    if WindowManager.savedLayouts[layoutName] then
        WindowManager.savedLayouts[layoutName] = nil
        hs.alert.show(string.format("Deleted layout '%s'", layoutName))
        return true
    else
        hs.alert.show(string.format("No layout found with name '%s'", layoutName))
        return false
    end
end

WindowManager.windowAlphas = {}

function WindowManager:setAlpha(level, win)
    win = win or hs.window.focusedWindow()
    if not win then
        log:w("No focused window found to set alpha", __FILE__)
        return
    end

    level = math.max(0, math.min(1, level)) -- Clamp between 0 and 1

    win:setAlpha(level)
    self.windowAlphas[win:id()] = level
    log:i(string.format("Window '%s' alpha set to %.2f", win:title(), level), __FILE__)
end

function WindowManager:changeAlpha(direction, amount)
    local win = hs.window.focusedWindow()
    if not win then
        log:w("No focused window found to change alpha", __FILE__)
        return
    end

    amount = amount or 0.1
    local currentAlpha = self.windowAlphas[win:id()] or 1.0 -- Default to 1.0 if not tracked

    local newAlpha
    if direction == "increase" then
        newAlpha = math.min(1.0, currentAlpha + amount)
    elseif direction == "decrease" then
        newAlpha = math.max(0.0, currentAlpha - amount)
    else
        log:w("Invalid direction for changeAlpha: " .. tostring(direction), __FILE__)
        return
    end

    self:setAlpha(newAlpha, win)
end

-- Save in global environment for module reuse
_G.WindowManager = WindowManager
return WindowManager
