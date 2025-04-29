#!/bin/bash
# VisoMaster startup script - replaces supervisor functionality
# This script manages all the services needed for VisoMaster to run

# Create logs directory
mkdir -p /logs

# Function to log messages with timestamps
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a /logs/startup.log
}

# Setup environment
setup_environment() {
  log "Setting up environment..."
  mkdir -p /workspace 
  
  # Copy window manager script if needed
  if [ -f '/src/debian/icewm/wm_startup.sh' ]; then 
    cp /src/debian/icewm/wm_startup.sh /workspace/
    chmod +x /workspace/wm_startup.sh
  fi
  
  # Setup X11 auth
  mkdir -p /root/.vnc
  touch /root/.Xauthority
  chmod 600 /root/.Xauthority
  xauth generate :1 . trusted || log 'Failed to generate auth'
  
  log "Environment setup complete"
}

# Start Jupyter Lab
start_jupyter() {
  log "Starting Jupyter Lab..."
  cd /VisoMaster
  nohup jupyter lab --ip=0.0.0.0 --port=8888 --no-browser --allow-root \
    --NotebookApp.token='' --NotebookApp.password='' \
    --NotebookApp.allow_origin='*' --NotebookApp.base_url=${JUPYTER_BASE_URL:-/} \
    > /logs/jupyter.log 2> /logs/jupyter_err.log &
  
  log "Jupyter Lab started"
}

# Start VNC server
start_vnc() {
  log "Starting VNC server..."
  
  # Kill any existing VNC servers
  vncserver -kill :1 &> /logs/vnc.log || true
  
  # Start VNC service
  nohup /dockerstartup/vnc_startup.sh --wait > /logs/vnc.log 2> /logs/vnc_err.log &
  
  log "VNC server started"
}

# Start VisoMaster application
start_visomaster() {
  log "Starting VisoMaster..."
  cd /VisoMaster
  
  # Create placeholder main.py if it doesn't exist
  if [ ! -f 'main.py' ]; then
    log "Creating placeholder main.py"
    cat > main.py << EOL
#!/usr/bin/env python3
print('VisoMaster placeholder script')
print('The actual main.py was not found in the repository.')
print('Please check the repository structure and update accordingly.')
while True:
    import time
    time.sleep(60)
EOL
    chmod +x main.py
  fi
  
  # List directory contents
  ls -la
  
  # Start application
  export DISPLAY=:1
  export XAUTHORITY=/root/.Xauthority
  nohup python3 main.py > /logs/visomaster.log 2> /logs/visomaster_err.log &
  
  log "VisoMaster application started"
}

# Monitor processes and keep container running
monitor_services() {
  log "Starting service monitoring..."
  
  # Function to check if process is running
  is_running() {
    pgrep -f "$1" > /dev/null
  }
  
  # Main monitoring loop
  while true; do
    # Check and restart Jupyter if needed
    if ! is_running "jupyter lab"; then
      log "WARNING: Jupyter Lab not running, restarting..."
      start_jupyter
    fi
    
    # Check and restart VNC if needed
    if ! is_running "vnc"; then
      log "WARNING: VNC server not running, restarting..."
      start_vnc
    fi
    
    # Check and restart VisoMaster if needed
    if ! is_running "python3 main.py"; then
      log "WARNING: VisoMaster not running, restarting..."
      start_visomaster
    fi
    
    # Sleep before next check
    sleep 30
  done
}

# Main execution
log "======= Starting VisoMaster services ======="

# Run setup and start services
setup_environment
start_jupyter
start_vnc
start_visomaster

# Keep checking services and container alive
monitor_services