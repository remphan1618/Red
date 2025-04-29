#!/usr/bin/env bash
### Modified to prevent immediate exits on errors
set +e

echo -e "\n------------------ startup of IceWM window manager ------------------"

# Wait for X server to be available
for i in {1..20}; do
    if DISPLAY=$DISPLAY xset -q >/dev/null 2>&1; then
        echo "X server is ready on display $DISPLAY"
        break
    fi
    echo "Waiting for X server to be available on display $DISPLAY... ($i/20)"
    sleep 1
    # Try to ensure DISPLAY is set properly
    export DISPLAY=:1
done

# Kill any existing window manager processes to prevent conflicts
pkill -f icewm 2>/dev/null || true
pkill -f icewmbg 2>/dev/null || true
sleep 2

### disable screensaver and power management
DISPLAY=$DISPLAY xset -dpms || echo "Failed to disable DPMS"
DISPLAY=$DISPLAY xset s noblank || echo "Failed to set screen blank"
DISPLAY=$DISPLAY xset s off || echo "Failed to turn off screen saver"

# Start icewm with proper error handling
echo "Starting icewm-session"
DISPLAY=$DISPLAY icewm-session > $HOME/wm.log 2>&1 &

# Give it a moment to start
sleep 2
cat $HOME/wm.log