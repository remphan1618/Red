#!/usr/bin/env bash
### Modified to prevent immediate exits on errors
set +e

echo -e "\n------------------ startup of IceWM window manager ------------------"

# Make sure the DISPLAY variable is properly set and configured
export DISPLAY=:1
export XAUTHORITY=/root/.Xauthority

# Disable access control to allow connections to the X server
xhost + 2>/dev/null || true

# Wait for X server to be fully available (up to 30 seconds)
for i in {1..30}; do
    if xdpyinfo >/dev/null 2>&1; then
        echo "X server is ready on display $DISPLAY"
        break
    fi
    echo "Waiting for X server to be available on display $DISPLAY... ($i/30)"
    sleep 1
done

# Clear any stale window manager processes
pkill -f icewm 2>/dev/null || true
pkill -f icewmbg 2>/dev/null || true
sleep 2

# Explicitly check if X server is working and disable screen saver settings
if xdpyinfo >/dev/null 2>&1; then
    DISPLAY=$DISPLAY xset -dpms || echo "Failed to disable DPMS"
    DISPLAY=$DISPLAY xset s noblank || echo "Failed to set screen blank"
    DISPLAY=$DISPLAY xset s off || echo "Failed to turn off screen saver"
else
    echo "ERROR: X server is still not available after waiting"
fi

# Start icewm with proper error handling and debug output
echo "Starting icewm-session with DISPLAY=$DISPLAY"
DISPLAY=$DISPLAY icewm-session > $HOME/wm.log 2>&1 &
ICEWM_PID=$!
echo "IceWM started with PID $ICEWM_PID"

# Give it a moment to start
sleep 2
echo "Window manager log:"
cat $HOME/wm.log