#!/bin/bash
# Script to fix X11 authentication and VNC issues
# Run this inside the container after the VNC service starts

echo "==========================================="
echo "Starting X11/VNC Fix Script: $(date)"
echo "==========================================="

# 1. Fix X11 authentication
echo "Setting up X11 authentication..."
export DISPLAY=:1
touch ~/.Xauthority
xauth generate :1 . trusted
xhost + localhost
xhost +local:

# 2. Check if X server is accessible
echo "Testing X server access..."
if xdpyinfo >/dev/null 2>&1; then
    echo "✓ X server is accessible"
else
    echo "✗ X server is NOT accessible"
fi

# 3. Restart the window manager
echo "Restarting window manager..."
pkill -f icewm 2>/dev/null || true
pkill -f icewmbg 2>/dev/null || true
sleep 2
export DISPLAY=:1
icewm-session &
echo "✓ Window manager restarted"

# 4. Install missing Python packages
echo "Installing required Python packages..."
pip install tqdm PySide6 || python3 -m pip install tqdm PySide6
echo "✓ Python packages installed"

# 5. Check and restart services
echo "Checking service status..."
ps aux | grep -E 'vnc|icewm|jupyter|filebrowser'

# 6. Display connection information
echo "==========================================="
echo "VNC Connection Information:"
echo "- VNC port: 5901"
echo "- NoVNC port: 6901"
echo "- Jupyter port: 8080/8081" 
echo "- Filebrowser port: 8585"
echo "==========================================="