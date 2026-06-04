-- Spoons/HammerGhost.spoon/plugins/system_actions.lua
--
-- EventGhost-parity system control actions: audio, brightness, power/session,
-- speech, and sound playback. Mirrors EventGhost's "System" plugin group.
-- Params arrive templated as strings (see action_system.tmpl); numeric ones are
-- coerced with tonumber and guarded. Output/power devices are guarded for nil --
-- a headless or display-less machine returns nil from the default-device APIs.

-- Retained so a speaker/sound isn't garbage-collected mid-playback (hs.speech /
-- hs.sound objects stop if nothing holds a reference while they're playing).
local speaker
local lastSound

return function(action_system)
    -- Set absolute output volume (0-100). hs.audiodevice volume is the same scale.
    action_system.registerActionType("setVolume", {
        name = "Set Volume",
        parameters = {
            level = { type = "text", required = false, default = "50" }
        },
        handler = function(params)
            local d = hs.audiodevice.defaultOutputDevice()
            if d then d:setVolume(tonumber(params.level) or 50) end
        end
    })

    -- Nudge output volume by a relative delta (+/-). Reads current level first;
    -- volume() can be nil on devices without a level control, so default to 0.
    action_system.registerActionType("changeVolume", {
        name = "Change Volume",
        parameters = {
            delta = { type = "text", required = false, default = "5" }
        },
        handler = function(params)
            local d = hs.audiodevice.defaultOutputDevice()
            if d then d:setVolume((d:volume() or 0) + (tonumber(params.delta) or 0)) end
        end
    })

    -- Flip the default output device's mute state.
    action_system.registerActionType("toggleMute", {
        name = "Toggle Mute",
        parameters = {},
        handler = function()
            local d = hs.audiodevice.defaultOutputDevice()
            if d then d:setMuted(not d:muted()) end
        end
    })

    -- Set display brightness (0-100) on the main display.
    action_system.registerActionType("setBrightness", {
        name = "Set Brightness",
        parameters = {
            level = { type = "text", required = false, default = "50" }
        },
        handler = function(params)
            hs.brightness.set(tonumber(params.level) or 50)
        end
    })

    -- Lock the screen immediately (session lock, not sleep).
    action_system.registerActionType("lockScreen", {
        name = "Lock Screen",
        parameters = {},
        handler = function()
            hs.caffeinate.lockScreen()
        end
    })

    -- Start the screensaver.
    action_system.registerActionType("startScreensaver", {
        name = "Start Screensaver",
        parameters = {},
        handler = function()
            hs.caffeinate.startScreensaver()
        end
    })

    -- Sleep the displays only (NOT the whole system). Non-blocking via hs.task --
    -- pmset is shelled out async so the event loop never stalls.
    action_system.registerActionType("sleepDisplays", {
        name = "Sleep Displays",
        parameters = {},
        handler = function()
            hs.task.new("/usr/bin/pmset", nil, { "displaysleepnow" }):start()
        end
    })

    -- Speak text aloud via the system TTS voice. Empty text is a no-op. The
    -- speaker is retained at module scope so it isn't GC'd before it finishes.
    action_system.registerActionType("speak", {
        name = "Speak Text",
        parameters = {
            text = { type = "text", required = false, default = "" }
        },
        handler = function(params)
            if params.text and params.text ~= "" then
                speaker = hs.speech.new()
                if speaker then speaker:speak(params.text) end
            end
        end
    })

    -- Play a named system sound (e.g. Glass, Ping, Sosumi). Unknown name -> no-op.
    -- Retained so the sound isn't collected mid-play.
    action_system.registerActionType("playSound", {
        name = "Play Sound",
        parameters = {
            name = { type = "text", required = false, default = "Glass" }
        },
        handler = function(params)
            local s = hs.sound.getByName(params.name)
            if s then
                lastSound = s
                s:play()
            end
        end
    })
end
