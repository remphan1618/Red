#!/usr/bin/env bash
### Modified to prevent immediate exits on errors
set +e

echo -e "\n------------------ startup of IceWM window manager ------------------"

# Kill any existing window manager processes
pkill -f icewm || true
pkill -f icewmbg || true
sleep 1

### disable screensaver and power management
xset -dpms &
xset s noblank &
xset s off &

# Start IceWM with replace option to ensure it replaces any existing window manager
/usr/bin/icewm-session --replace > $HOME/wm.log &
sleep 1
cat $HOME/wm.log