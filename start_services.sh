#!/bin/bash
set -e

echo "Setting up environment..."

# Run the VNC setup script
bash ./setup_vnc.sh

# Check if VNC server is running
if ! pgrep -x "Xtigervnc" > /dev/null; then
    echo "ERROR: VNC server failed to start"
    exit 1
fi

echo "VNC server is running on port 5901"

# Start the WebSockets proxy with proper quoting and escaping
echo "Starting WebSockets proxy..."
python3 ./websocket_proxy.py --listen "0.0.0.0:6080" --target "localhost:5901"

# This line will only be reached if the proxy doesn't daemonize itself
echo "All services started successfully"
