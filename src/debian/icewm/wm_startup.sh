#!/usr/bin/env bash
### Modified to prevent immediate exits on errors
set +e

echo -e "\n------------------ startup of IceWM window manager ------------------"

# Wait for X server to be available
for i in {1..10}; do
    if xset -q >/dev/null 2>&1; then
        echo "X server is ready"
        break
    fi
    echo "Waiting for X server to be available... ($i/10)"
    sleep 1
done

### disable screensaver and power management
xset -dpms || echo "Failed to disable DPMS"
xset s noblank || echo "Failed to set screen blank"
xset s off || echo "Failed to turn off screen saver"

# Start icewm with proper error handling
echo "Starting icewm-session"
icewm-session > $HOME/wm.log 2>&1 &

# Give it a moment to start
sleep 2
cat $HOME/wm.log