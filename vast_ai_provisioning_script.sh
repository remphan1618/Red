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
vncserver :1 -geometry 1920x1080 -depth 24 -localhost no

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

# Update supervisord configuration
section "Setting up Supervisor"
mkdir -p /etc/supervisor/conf.d

cat > /etc/supervisor/conf.d/supervisord.conf << 'EOL'
[supervisord]
nodaemon=true
user=root
logfile=/logs/supervisord.log
logfile_maxbytes=10MB
logfile_backups=3
pidfile=/tmp/supervisord.pid

[program:setup_environment]
command=/bin/bash -c "mkdir -p /workspace && touch /root/.Xauthority && chmod 600 /root/.Xauthority && xauth generate :1 . trusted || echo 'Failed to generate auth'"
autostart=true
autorestart=false
startretries=1
startsecs=0
priority=5
stdout_logfile=/logs/setup_env.log
stdout_logfile_maxbytes=10MB
stdout_logfile_backups=3
stderr_logfile=/logs/setup_env_err.log
stderr_logfile_maxbytes=10MB
stderr_logfile_backups=3
user=root

[program:jupyter]
command=jupyter lab --ip=0.0.0.0 --port=8888 --no-browser --allow-root --NotebookApp.token='' --NotebookApp.password='' --NotebookApp.allow_origin='*' --NotebookApp.base_url=${JUPYTER_BASE_URL:-/}
directory=/VisoMaster
autostart=true
autorestart=true
priority=20
stdout_logfile=/logs/jupyter.log
stdout_logfile_maxbytes=10MB
stdout_logfile_backups=3
stderr_logfile=/logs/jupyter_err.log
stderr_logfile_maxbytes=10MB
stderr_logfile_backups=3
user=root

[program:vnc]
command=/dockerstartup/vnc_startup.sh --wait
autostart=true
autorestart=true
priority=30
stdout_logfile=/logs/vnc.log
stdout_logfile_maxbytes=10MB
stdout_logfile_backups=3
stderr_logfile=/logs/vnc_err.log
stderr_logfile_maxbytes=10MB
stderr_logfile_backups=3
user=root

[program:visomaster]
command=/bin/bash -c "cd /VisoMaster && if [ ! -f 'main.py' ]; then echo 'Creating placeholder main.py'; cat > main.py << 'EOF'
#!/usr/bin/env python3
print('VisoMaster placeholder script')
print('The actual main.py was not found in the repository.')
print('Please check the repository structure and update accordingly.')
while True:
    import time
    time.sleep(60)
EOF
chmod +x main.py; fi && ls -la && python3 main.py"
autostart=true
autorestart=true
startretries=3
startsecs=5
directory=/VisoMaster
environment=DISPLAY=:1,XAUTHORITY=/root/.Xauthority
stdout_logfile=/logs/visomaster.log
stdout_logfile_maxbytes=10MB
stdout_logfile_backups=3
stderr_logfile=/logs/visomaster_err.log
stderr_logfile_maxbytes=10MB
stderr_logfile_backups=3
user=root
EOL

echo "✅ Supervisor configuration updated"

# Restart supervisor to apply changes
if pgrep supervisord > /dev/null; then
    echo "Restarting supervisor..."
    supervisorctl reload
else
    echo "Starting supervisor..."
    supervisord -c /etc/supervisor/conf.d/supervisord.conf
fi
echo "✅ Supervisor restarted"

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

# Script complete
section "Provisioning complete"
echo "VisoMaster environment has been successfully provisioned."
echo "Completed at: $(date)"
echo "Log file available at: $LOG_FILE"
echo "==============================================="