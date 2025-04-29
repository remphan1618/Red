#!/bin/bash
# Quick fix for X11 authentication issues with VNC
# Run this inside the Docker container to fix the blank VNC screen

echo "X11 Authentication Fix for VNC"
echo "============================"

# 1. Install missing Python packages
echo "Installing missing Python packages..."
pip install tqdm PySide6

# 2. Fix X11 authentication
echo "Setting up proper X11 authentication..."
export DISPLAY=:1

# Create proper .Xauthority file
touch ~/.Xauthority
xauth generate :1 . trusted

# Disable access control
xhost + || true

# 3. Verify X server is accessible
echo "Testing X server connectivity..."
xdpyinfo > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "✅ Success! X server is accessible"
else
    echo "❌ Failed to connect to X server"
fi

# 4. Restart window manager
echo "Restarting window manager..."
pkill -f icewm || true
pkill -f icewmbg || true
sleep 1
DISPLAY=:1 icewm-session &

# 5. Print connection information
echo ""
echo "VNC Connection Information:"
echo "--------------------------"
echo "VNC Port: 5901"
echo "NoVNC Port: 6901"
echo "Jupyter Port: 8081"
echo "Filebrowser Port: 8585"
echo ""
echo "To connect to VNC: use a VNC client to connect to [IP]:5901 without password"
echo "Or use a browser to connect to http://[IP]:6901"