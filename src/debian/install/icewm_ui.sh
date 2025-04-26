#!/usr/bin/env bash
### every exit != 0 fails the script
set -e

echo "Install IceWM UI components"
apt-get update 
apt-get install -y --no-install-recommends \
    icewm \
    icewm-common \
    xinit \
    xterm \
    xdg-utils \
    menu

# Clean up to reduce image size
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "IceWM UI components installed successfully"