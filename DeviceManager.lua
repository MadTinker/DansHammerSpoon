-- DeviceManager.lua - Device management utilities
-- Using singleton pattern to avoid multiple initializations

local HyperLogger = require('HyperLogger')
local log = HyperLogger.new()

-- Check if module is already initialized
if _G.DeviceManager then
    log:d('Returning existing DeviceManager module')
    return _G.DeviceManager
end

log:i('Initializing device management system')

local DeviceManager = {}

-- Configuration
local scripts_dir = os.getenv("HOME") .. "/.hammerspoon/scripts"

-- State
local usbWatcher = nil
local usbisEnabled = false

-- Phones re-enumerate several times on plug-in (charge -> MTP/ADB mode switch),
-- each firing an "added" event. Only launch scrcpy once per cooldown window.
local SCRCPY_COOLDOWN_SECONDS = 2
local lastScrcpyLaunch = 0

local function scrcpyOnCooldown()
    local now = hs.timer.secondsSinceEpoch()
    if now - lastScrcpyLaunch < SCRCPY_COOLDOWN_SECONDS then
        log:d('scrcpy launch suppressed (cooldown)')
        return true
    end
    lastScrcpyLaunch = now
    return false
end

-- USB Device Management
local function usbDeviceCallback(data)
    log:i('USB event detected:', hs.inspect(data))

    -- Guard against nil data
    if not data then
        log:e('Received nil data in USB callback')
        return
    end

    for key, value in pairs(data) do
        log:d(key .. ": " .. tostring(value))
    end

    if data["eventType"] == "added" then
        if data["vendorName"] == "SAMSUNG" and data["productName"] == "SAMSUNG_Android" then
            log:i('Samsung device connected:', data["productID"])
            local device_id = nil

            if data["productID"] == 26720 then
                device_id = "988a1b30573456354d"
                hs.alert.show("Samsung Android plugged in (Device 988a1b30573456354d)")
            elseif data["productID"] == 26732 then
                device_id = "R5CT602ZVTJ"
                hs.alert.show("Samsung Android plugged in (Device R5CT602ZVTJ)")
            end

            if device_id and scrcpyOnCooldown() then
                return
            end

            if device_id then
                local cmd = string.format("%s/launch_scrcpy.sh samsung &> /dev/null &", scripts_dir)
                log:d('Executing command:', cmd)
                local success, output, error = os.execute(cmd)
                if success then
                    log:i('Successfully launched scrcpy script')
                else
                    log:e('Error launching scrcpy script:', error)
                end
            else
                log:w('Unknown Samsung device ID:', data["productID"])
            end
        elseif data["vendorName"] == "Google" then
            log:i('Google device connected:', data["productName"])
            if scrcpyOnCooldown() then return end
            local cmd = string.format("nohup %s/launch_scrcpy.sh google &> /dev/null &", scripts_dir)
            log:d('Executing command:', cmd)
            local success, output, error = os.execute(cmd)
            if success then
                log:i('Successfully launched scrcpy script')
            else
                log:e('Error launching scrcpy script:', error)
            end
            hs.alert.show("Google " .. data["productName"] .. " plugged in")
        else
            log:i('Other device connected:', data["vendorName"])
            hs.alert.show(data["vendorName"] .. " device plugged in")
        end
    end
end

-- Create a USB watcher and set the callback
usbWatcher = hs.usb.watcher.new(usbDeviceCallback)

function DeviceManager.toggleUSBLogging()
    if usbisEnabled then
        usbWatcher:stop()
        usbisEnabled = false
    else
        usbWatcher:start()
        usbisEnabled = true
    end
    print("USB is now " .. (usbisEnabled and "enabled" or "disabled"))
end

-- Initialize USB watcher
DeviceManager.toggleUSBLogging()

-- Save in global environment for module reuse
_G.DeviceManager = DeviceManager
return DeviceManager
