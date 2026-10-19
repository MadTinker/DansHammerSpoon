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

log "Starting scrcpy for $DEVICE_TYPE device: $DEVICE_ID"

# The USB event fires before adb sees the phone; wait up to 15s for it.
for _ in $(seq 30); do
    [ "$("$ADB" ${DEVICE_ID:+-s "$DEVICE_ID"} get-state 2>/dev/null)" = "device" ] && break
    sleep 0.5
done
log "adb state: $("$ADB" ${DEVICE_ID:+-s "$DEVICE_ID"} get-state 2>&1)"

case "$DEVICE_TYPE" in
    "samsung")
        if [ ! -z "$DEVICE_ID" ]; then
            /opt/homebrew/bin/scrcpy -s "$DEVICE_ID" -S --stay-awake >> "$LOG_FILE" 2>&1 &
        else
            /opt/homebrew/bin/scrcpy --stay-awake --always-on-top -S >> "$LOG_FILE" 2>&1 &
        fi
        ;;
    "google")
        /opt/homebrew/bin/scrcpy --stay-awake --window-title=scrcpy --always-on-top -S >> "$LOG_FILE" 2>&1 &
        ;;
    *)
        log "Unknown device type: $DEVICE_TYPE"
        ;;
esac

# Store the PID of the background process
echo $! > "$LOGS_DIR/scrcpy.pid"
log "Started scrcpy with PID: $!"
