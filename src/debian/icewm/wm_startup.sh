#!/usr/bin/env bash
### Modified to prevent immediate exits on errors
set +e

echo -e "\n------------------ startup of IceWM window manager ------------------"

# Make sure the DISPLAY variable is explicitly set
export DISPLAY=:1

# Wait for X server to be fully available
for i in {1..20}; do
    if xhost + >/dev/null 2>&1; then
        echo "X server is ready on display $DISPLAY"
        break
    fi
    echo "Waiting for X server to be available on display $DISPLAY... ($i/20)"
    sleep 1
done

# Ensure we're not running multiple window managers
pkill -f icewm >/dev/null 2>&1 || true
pkill -f icewmbg >/dev/null 2>&1 || true
sleep 2

### disable screensaver and power management (with error handling)
DISPLAY=$DISPLAY xset -dpms || echo "Failed to disable DPMS"
DISPLAY=$DISPLAY xset s noblank || echo "Failed to set screen blank"
DISPLAY=$DISPLAY xset s off || echo "Failed to turn off screen saver"

# Start icewm with explicit display setting
echo "Starting icewm-session with DISPLAY=$DISPLAY"
DISPLAY=$DISPLAY icewm-session > $HOME/wm.log 2>&1 &

# Give it a moment to start
sleep 2
cat $HOME/wm.log