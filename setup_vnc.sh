#!/bin/bash

# Create Xauthority file if it doesn't exist
if [ ! -f "$HOME/.Xauthority" ]; then
    echo "Creating .Xauthority file"
    touch "$HOME/.Xauthority"
    xauth generate :1 . trusted
fi

# Ensure VNC directory and password file exist
mkdir -p "$HOME/.vnc"
if [ ! -f "$HOME/.vnc/passwd" ]; then
    echo "Creating VNC password"
    echo "vncpasswd123" | vncpasswd -f > "$HOME/.vnc/passwd"
    chmod 600 "$HOME/.vnc/passwd"
fi

# Start VNC server with proper configuration
vncserver :1 -depth 24 -geometry 1280x800 -localhost no

echo "VNC server started"
