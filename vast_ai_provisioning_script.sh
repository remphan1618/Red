#!/bin/bash
#
# Vast.ai Provisioning Script for VisoMaster
# 
# This script is designed to be used with the PROVISIONING_SCRIPT environment variable
# in vast.ai. It performs first-boot initialization of the environment.

# Set up logging
LOG_DIR="/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/provisioning_script.log"
exec > >(tee -a "$LOG_FILE") 2> >(tee -a "$LOG_FILE" >&2)

echo "==============================================="
echo "Starting VisoMaster Provisioning: $(date)"
echo "==============================================="

# Force clean clone on startup
FORCE_CLONE=true

# Function to handle errors
handle_error() {
    echo "ERROR: $1" >&2
    echo "See $LOG_FILE for details"
    # Don't exit on errors anymore - allow script to continue
    echo "Continuing execution despite the error..."
}

# Function to log section start
section() {
    echo ""
    echo "==============================================="
    echo "SECTION: $1 - $(date)"
    echo "==============================================="
}

# Set up VNC configuration - CHECK DESTINATION FIRST, NOT SOURCE!
section "Setting up VNC environment"
mkdir -p /dockerstartup /root/.vnc

# First check if the VNC startup script exists at the destination
if [ -f "/dockerstartup/vnc_startup.sh" ]; then
    echo "✅ Using existing VNC startup script at /dockerstartup/vnc_startup.sh"
    chmod +x /dockerstartup/vnc_startup.sh
else
    echo "Creating VNC startup script..."
    # Check if we have a custom VNC startup script in the src directory
    if [ -f "/src/vnc_startup_jupyterlab_filebrowser.sh" ]; then
        echo "Using custom VNC startup script from /src directory"
        cp /src/vnc_startup_jupyterlab_filebrowser.sh /dockerstartup/vnc_startup.sh
        chmod +x /dockerstartup/vnc_startup.sh
        echo "✅ Copied VNC startup script from /src directory"
    else
        # Create a simple VNC startup script
        cat > /dockerstartup/vnc_startup.sh << 'EOL'
#!/bin/bash
# VNC server startup script for VisoMaster

# Store VNC password
mkdir -p ~/.vnc
echo "vncpasswd123" | vncpasswd -f > ~/.vnc/passwd
chmod 600 ~/.vnc/passwd

# Set DISPLAY variable
export DISPLAY=:1

# Start VNC server
vncserver :1 -geometry 1920x1080 -depth 24 -localhost no -SecurityTypes None --I-KNOW-THIS-IS-INSECURE

# Start window manager
if [ -f "/workspace/wm_startup.sh" ]; then
    bash /workspace/wm_startup.sh &
elif command -v icewm-session >/dev/null; then
    icewm-session &
elif command -v openbox >/dev/null; then
    openbox &
fi

# Keep the script running
echo "VNC server started on display :1"
tail -f /dev/null
EOL
        chmod +x /dockerstartup/vnc_startup.sh
        echo "✅ Created VNC startup script"
    fi
fi

# Create window manager startup script - CHECK DESTINATION FIRST!
mkdir -p /workspace
if [ -f "/workspace/wm_startup.sh" ]; then
    echo "✅ Using existing window manager script at /workspace/wm_startup.sh"
    chmod +x /workspace/wm_startup.sh
else
    echo "Creating window manager startup script..."
    cat > /workspace/wm_startup.sh << 'EOL'
#!/bin/bash
# Simple window manager startup script

# Set display
export DISPLAY=:1

# Set up X authentication
touch ~/.Xauthority
xauth generate :1 . trusted

# Start window manager
if command -v icewm-session >/dev/null; then
    icewm-session &
elif command -v openbox >/dev/null; then
    openbox &
fi

# Done
echo "Window manager started on display :1"
EOL
    chmod +x /workspace/wm_startup.sh
    echo "✅ Created window manager startup script"
fi

# Create VNC password
if [ ! -f "/root/.vnc/passwd" ] && command -v vncpasswd &> /dev/null; then
    echo "Creating VNC password..."
    mkdir -p /root/.vnc
    echo "vncpasswd123" | vncpasswd -f > /root/.vnc/passwd
    chmod 600 /root/.vnc/passwd
    echo "✅ VNC password created"
fi

# FORCE CLONE REPOSITORY SECTION
section "Cloning Repository"

# Always remove and re-clone the repository
if [ -d "/VisoMaster" ]; then
    echo "Backing up important user files..."
    mkdir -p /tmp/visomaster_backup
    for dir in "models" "Images" "Videos" "Output"; do
        if [ -d "/VisoMaster/$dir" ] && [ "$(ls -A "/VisoMaster/$dir" 2>/dev/null)" ]; then
            mkdir -p "/tmp/visomaster_backup/$dir"
            cp -r "/VisoMaster/$dir"/* "/tmp/visomaster_backup/$dir/" 2>/dev/null || echo "Warning: Could not backup all files in $dir"
        fi
    done
    echo "✅ User data backed up"
    
    echo "Removing existing repository..."
    rm -rf /VisoMaster
fi

echo "Cloning fresh repository..."
git clone https://github.com/remphan1618/VisoMaster.git /VisoMaster || handle_error "Failed to clone repository"

# Verify main.py exists
if [ -f "/VisoMaster/main.py" ]; then
    echo "✅ Repository cloned successfully with main.py found"
else
    echo "⚠️ main.py not found in repository. Creating placeholder..."
    # Create a placeholder main.py
    cat > /VisoMaster/main.py << 'EOL'
#!/usr/bin/env python3
print("VisoMaster placeholder script")
print("The actual main.py was not found in the repository.")
print("Please check the repository structure.")

# Keep the script running
import time
while True:
    print("Placeholder script running...")
    time.sleep(60)
EOL
    chmod +x /VisoMaster/main.py
fi

# Restore user data
if [ -d "/tmp/visomaster_backup" ]; then
    echo "Restoring user data..."
    mkdir -p /VisoMaster/models /VisoMaster/Images /VisoMaster/Videos /VisoMaster/Output
    for dir in "models" "Images" "Videos" "Output"; do
        if [ -d "/tmp/visomaster_backup/$dir" ]; then
            cp -r "/tmp/visomaster_backup/$dir"/* "/VisoMaster/$dir/" 2>/dev/null || echo "Warning: Could not restore all files in $dir"
        fi
    done
    rm -rf /tmp/visomaster_backup
    echo "✅ User data restored"
fi

# Install Python dependencies
section "Installing Python dependencies"
if [ -f "/VisoMaster/requirements_cu124.txt" ]; then
    echo "Installing CUDA 12.4 requirements..."
    pip install -r "/VisoMaster/requirements_cu124.txt" || handle_error "Failed to install requirements"
elif [ -f "/VisoMaster/requirements.txt" ]; then
    echo "Installing requirements..."
    pip install -r "/VisoMaster/requirements.txt" || handle_error "Failed to install requirements"
fi

# Always install critical packages
pip install PySide6 jupyter jupyterlab numpy tqdm || handle_error "Failed to install critical packages"
echo "✅ Python dependencies installed"

# Set environment variables
section "Setting environment variables"
cat > /etc/profile.d/VisoMaster_env.sh << EOF
export VISOMASTER_HOME="/VisoMaster"
export PATH="\$PATH:\$VISOMASTER_HOME/bin"
export PYTHONPATH="\$PYTHONPATH:\$VISOMASTER_HOME"
export DISPLAY=":1"
export XAUTHORITY="/root/.Xauthority"
EOF

# Also add to .bashrc for immediate effect
cat >> /root/.bashrc << EOF
export VISOMASTER_HOME="/VisoMaster"
export PATH="\$PATH:\$VISOMASTER_HOME/bin"
export PYTHONPATH="\$PYTHONPATH:\$VISOMASTER_HOME"
export DISPLAY=":1"
export XAUTHORITY="/root/.Xauthority"
EOF

source /etc/profile.d/VisoMaster_env.sh
echo "✅ Environment variables set"

# Set up X11 authentication
section "Setting up X11 Authentication" 
touch /root/.Xauthority
chmod 600 /root/.Xauthority
echo "✅ X11 authentication setup"

# Create required directories
section "Creating directories"
mkdir -p /VisoMaster/{Images,Videos,Output,models} 
echo "✅ Directories created"

# Print repository contents for verification
section "Repository verification"
if [ -d "/VisoMaster" ]; then
    echo "Contents of /VisoMaster:"
    ls -la /VisoMaster/
    if [ -f "/VisoMaster/main.py" ]; then
        echo "✅ main.py is present"
    else
        echo "❌ main.py is missing"
    fi
else
    echo "❌ /VisoMaster directory is missing"
fi

# Create a combined startup script that will be called by Docker CMD
section "Creating integrated startup script"
cat > /dockerstartup/integrated_startup.sh << 'EOL'
#!/bin/bash
# VisoMaster integrated startup script

# Function to log messages with timestamps
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a /logs/startup.log
}

# Setup environment (will only run if needed)
setup_environment() {
  log "Setting up environment..."
  mkdir -p /workspace 
  
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
EOL

chmod +x /dockerstartup/integrated_startup.sh
echo "✅ Integrated startup script created"

# Create a simple systemd service file to start the integrated script at boot
cat > /etc/systemd/system/visomaster.service << EOF
[Unit]
Description=VisoMaster Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=/bin/bash /dockerstartup/integrated_startup.sh
Restart=on-failure
RestartSec=5
StandardOutput=append:/logs/visomaster_service.log
StandardError=append:/logs/visomaster_service_err.log

[Install]
WantedBy=multi-user.target
EOF

# Enable the service to start at boot
systemctl enable visomaster.service || echo "NOTE: Could not enable systemd service (normal if not using systemd)"

# Update the Docker CMD entry point to use our script (this will be used if not using systemd)
echo '#!/bin/bash
exec /bin/bash /dockerstartup/integrated_startup.sh
' > /dockerstartup/cmd_entrypoint.sh
chmod +x /dockerstartup/cmd_entrypoint.sh

# Modify the Dockerfile CMD directive if it exists
if [ -f "/Dockerfile" ]; then
    sed -i 's|^CMD.*|CMD ["/bin/bash", "/dockerstartup/integrated_startup.sh"]|g' /Dockerfile
    echo "✅ Updated Dockerfile CMD to use integrated script"
fi

# Script complete
section "Provisioning complete"
echo "VisoMaster environment has been successfully provisioned."
echo "Completed at: $(date)"
echo "Log file available at: $LOG_FILE"
echo "==============================================="

# Start the integrated script directly if requested
if [ "$1" = "--start" ]; then
    echo "Starting integrated services directly..."
    exec /bin/bash /dockerstartup/integrated_startup.sh
fi