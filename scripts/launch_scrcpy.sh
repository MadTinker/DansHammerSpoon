#!/bin/zsh
# ~/.hammerspoon/scripts/launch_scrcpy.sh

DEVICE_TYPE=$1
DEVICE_ID=$2

# Create logs directory if it doesn't exist
LOGS_DIR="$HOME/.hammerspoon/logs"
mkdir -p "$LOGS_DIR"

LOG_FILE="$LOGS_DIR/scrcpy.log"

# Function to log messages with timestamp
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Set ADB environment variable explicitly
export ADB="/opt/homebrew/bin/adb"
# Hammerspoon's environment is bare; the lab toolkit (pixel-up, adb-grants) needs adb on PATH.
LAB_BIN="$HOME/lab/madness_interactive/bin"
export PATH="/opt/homebrew/bin:$LAB_BIN:$PATH"

# One run at a time: pixel-up's `adb tcpip` restarts adbd, the phone re-enumerates,
# and the USB watcher fires again while this run is still going.
LOCK="$LOGS_DIR/launch_scrcpy.lock"
if ! mkdir "$LOCK" 2>/dev/null; then
    log "Another launch is running, skipping ($DEVICE_TYPE)"
    exit 0
fi
trap 'rmdir "$LOCK"' EXIT

log "Starting scrcpy for $DEVICE_TYPE device: $DEVICE_ID"

# The USB event fires before adb sees the phone; wait up to 15s for it.
# -d = the USB device, so a wireless adb connection (adb-wifi) does not clash.
if [ -n "$DEVICE_ID" ]; then SEL="-s $DEVICE_ID"; else SEL="-d"; fi
for _ in $(seq 30); do
    [ "$("$ADB" $SEL get-state 2>/dev/null)" = "device" ] && break
    sleep 0.5
done
STATE=$("$ADB" $SEL get-state 2>&1)
log "adb state: $STATE"
if [ "$STATE" != "device" ]; then
    log "No usable phone, not launching scrcpy"
    exit 0
fi

# Pixel: redo whatever a reboot undid (tcpip 5555, eaws tunnel, grants, always-on VPN).
# Runs before scrcpy because its adb restart would kill a running mirror.
if [ "$DEVICE_TYPE" = "google" ] && [ -x "$LAB_BIN/pixel-up" ]; then
    "$LAB_BIN/pixel-up" -q >> "$LOG_FILE" 2>&1
    log "pixel-up done"
fi

if pgrep -x scrcpy >/dev/null; then
    log "scrcpy already running, not starting another"
    exit 0
fi

# adb is "device" a moment before it's usable after a restart (plug-in, tcpip,
# adb usb). Wait until the phone answers twice in a row, a second apart.
adb_settled() {
    for _ in $(seq 20); do
        if "$ADB" $SEL shell true 2>/dev/null; then
            sleep 1
            "$ADB" $SEL shell true 2>/dev/null && return 0
        fi
        sleep 1
    done
    return 1
}

start_scrcpy() {
    case "$DEVICE_TYPE" in
        "samsung")
            if [ ! -z "$DEVICE_ID" ]; then
                /opt/homebrew/bin/scrcpy -s "$DEVICE_ID" -S --stay-awake >> "$LOG_FILE" 2>&1 &
            else
                /opt/homebrew/bin/scrcpy -d --stay-awake --always-on-top -S >> "$LOG_FILE" 2>&1 &
            fi
            ;;
        "google")
            /opt/homebrew/bin/scrcpy -d --stay-awake --window-title=scrcpy --always-on-top -S >> "$LOG_FILE" 2>&1 &
            ;;
        *)
            log "Unknown device type: $DEVICE_TYPE"
            return 1
            ;;
    esac
    PID=$!
}

# Up to 3 tries: scrcpy dies at once ("Server connection failed") if adb is
# still settling.
PID=
for attempt in 1 2 3; do
    adb_settled || { log "phone never settled, giving up"; exit 0; }
    start_scrcpy || exit 0
    sleep 4
    kill -0 $PID 2>/dev/null && break
    log "scrcpy exited early (attempt $attempt)"
    PID=
done
[ -n "$PID" ] || { log "scrcpy failed 3 times"; exit 0; }

# Store the PID of the background process
echo $PID > "$LOGS_DIR/scrcpy.pid"
log "Started scrcpy with PID: $PID"
