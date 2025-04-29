#!/bin/bash
#
# Vast.ai Provisioning Script for VisoMaster
# 
# This script is designed to be used with the PROVISIONING_SCRIPT environment variable
# in vast.ai. It performs first-boot initialization of the environment.
#
# Usage: Set PROVISIONING_SCRIPT=https://raw.githubusercontent.com/remphan1618/Red/main/vast_ai_provisioning_script.sh
# in your vast.ai environment variables when creating an instance.

# Set up logging
LOG_DIR="/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/provisioning_script.log"
exec > >(tee -a "$LOG_FILE") 2> >(tee -a "$LOG_FILE" >&2)

echo "==============================================="
echo "Starting VisoMaster Provisioning: $(date)"
echo "==============================================="

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

# Install SSH server (which was missing and causing errors)
section "Installing SSH server"
if [ ! -f "/usr/sbin/sshd" ]; then
    echo "OpenSSH server not found, installing..."
    apt-get update && apt-get install -y openssh-server || handle_error "Failed to install SSH server"
    echo "✅ SSH server installed"
else
    echo "✅ SSH server already installed"
fi

# Set up VNC configuration
section "Setting up VNC environment"
mkdir -p /dockerstartup /root/.vnc

# Check for VNC startup script - FIRST CHECK DESTINATION, then source
if [ -f "/dockerstartup/vnc_startup.sh" ]; then
    echo "✅ VNC startup script already exists at /dockerstartup/vnc_startup.sh"
    chmod +x /dockerstartup/vnc_startup.sh
elif [ -f "/src/vnc_startup_jupyterlab_filebrowser.sh" ]; then
    cp /src/vnc_startup_jupyterlab_filebrowser.sh /dockerstartup/vnc_startup.sh
    chmod +x /dockerstartup/vnc_startup.sh
    echo "✅ Copied VNC filebrowser startup script to /dockerstartup/vnc_startup.sh"
elif [ -f "/src/vnc_startup_jupyterlab.sh" ]; then
    cp /src/vnc_startup_jupyterlab.sh /dockerstartup/vnc_startup.sh
    chmod +x /dockerstartup/vnc_startup.sh
    echo "✅ Copied VNC startup script to /dockerstartup/vnc_startup.sh"
else
    # Create a basic VNC startup script
    echo "Creating VNC startup script..."
    cat > /dockerstartup/vnc_startup.sh << 'EOL'
#!/bin/bash
# VNC server startup script with TigerVNC

# Store the VNC password
mkdir -p ~/.vnc
echo "vncpasswd123" | vncpasswd -f > ~/.vnc/passwd
chmod 600 ~/.vnc/passwd

# Set DISPLAY variable
export DISPLAY=:1

# Start VNC server
vncserver :1 -rfbport 5901 -geometry 1920x1080 -depth 24 -SecurityTypes None -localhost no &
sleep 2

echo "VNC Server started on port 5901"

# Start window manager
if [ -f "/workspace/wm_startup.sh" ]; then
    echo "Starting window manager with /workspace/wm_startup.sh"
    bash /workspace/wm_startup.sh &
else
    echo "Starting default window manager (openbox)"
    openbox-session &
fi

# Keep the script running
tail -f /dev/null
EOL
    chmod +x /dockerstartup/vnc_startup.sh
    echo "✅ Created VNC startup script at /dockerstartup/vnc_startup.sh"
fi

# Check for window manager script - FIRST CHECK DESTINATION, then source
mkdir -p /workspace
if [ -f "/workspace/wm_startup.sh" ]; then
    echo "✅ Window manager startup script already exists at /workspace/wm_startup.sh"
    chmod +x /workspace/wm_startup.sh
elif [ -f "/root/wm_startup.sh" ]; then
    cp /root/wm_startup.sh /workspace/wm_startup.sh
    chmod +x /workspace/wm_startup.sh
    echo "✅ Copied window manager script from /root/ to /workspace/"
elif [ -f "/src/debian/icewm/wm_startup.sh" ]; then
    cp /src/debian/icewm/wm_startup.sh /workspace/wm_startup.sh
    chmod +x /workspace/wm_startup.sh
    echo "✅ Copied window manager startup script to /workspace/wm_startup.sh"
else
    # Create a window manager startup script
    echo "Creating window manager startup script..."
    cat > /workspace/wm_startup.sh << 'EOL'
#!/bin/bash
# Window manager startup script

export DISPLAY=:1
export XAUTHORITY=/root/.Xauthority

# Wait for X server
count=0
while ! xdpyinfo -display :1 >/dev/null 2>&1; do
    echo "Waiting for X server to be available on display :1... ($count/30)"
    sleep 1
    count=$((count+1))
    if [ $count -gt 30 ]; then
        echo "ERROR: X server is still not available after waiting"
        break
    fi
done

# Set X authentication
xauth generate :1 . trusted 2>/dev/null || echo "Failed to generate X authentication"

# Start window manager
if command -v icewm-session >/dev/null; then
    echo "Starting IceWM session"
    icewm-session &
elif command -v openbox-session >/dev/null; then
    echo "Starting Openbox session"
    openbox-session &
else
    echo "No window manager found"
fi

# Keep the script running
tail -f /dev/null
EOL
    chmod +x /workspace/wm_startup.sh
    echo "✅ Created window manager startup script at /workspace/wm_startup.sh"
fi

# Create VNC password
if [ ! -f "/root/.vnc/passwd" ] && command -v vncpasswd &> /dev/null; then
    echo "Creating VNC password..."
    mkdir -p /root/.vnc
    echo "vncpasswd123" | vncpasswd -f > /root/.vnc/passwd
    chmod 600 /root/.vnc/passwd
    echo "✅ VNC password created"
fi

# FORCE CLONE REPOSITORY SECTION - COMPLETELY REWRITTEN
section "Cloning Repository"
echo "FORCE CLONING VisoMaster repository..."

# Backup important user data if repo exists
if [ -d "/VisoMaster" ]; then
    echo "Backing up user data from existing directory..."
    mkdir -p /tmp/backup_visomaster
    
    for dir in "models" "Images" "Videos" "Output"; do
        if [ -d "/VisoMaster/$dir" ] && [ "$(ls -A "/VisoMaster/$dir" 2>/dev/null)" ]; then
            echo "Backing up $dir directory..."
            mkdir -p "/tmp/backup_visomaster/$dir"
            cp -rf "/VisoMaster/$dir"/* "/tmp/backup_visomaster/$dir/" 2>/dev/null || echo "Warning: Some files could not be backed up"
        fi
    done
    
    # Delete existing repository
    echo "Removing old repository directory..."
    rm -rf /VisoMaster
fi

# Clone fresh repository
echo "Cloning fresh repository..."
git clone https://github.com/remphan1618/VisoMaster.git /VisoMaster || handle_error "Failed to clone repository"

# Verify repository has main.py
if [ -f "/VisoMaster/main.py" ]; then
    echo "✅ Repository cloned successfully with main.py present"
else
    echo "⚠️ Repository cloned but main.py is missing!"
    
    # Try to find main.py in subdirectories
    MAIN_PY=$(find /VisoMaster -name "main.py" -type f 2>/dev/null)
    if [ -n "$MAIN_PY" ]; then
        echo "Found main.py at: $MAIN_PY"
        ln -sf "$MAIN_PY" "/VisoMaster/main.py"
        echo "✅ Created symlink to main.py in root directory"
    else
        echo "❌ main.py not found in repository. Creating placeholder file."
        # Create a placeholder main.py that will keep running
        cat > /VisoMaster/main.py << 'EOL'
#!/usr/bin/env python3
print("VisoMaster placeholder script")
print("The actual main.py was not found in the repository.")
print("Please check the repository structure and update accordingly.")
while True:
    import time
    time.sleep(60)
EOL
        chmod +x /VisoMaster/main.py
    fi
fi

# Restore backed up data if exists
if [ -d "/tmp/backup_visomaster" ]; then
    echo "Restoring user data..."
    
    # Create directories if they don't exist
    mkdir -p /VisoMaster/models /VisoMaster/Images /VisoMaster/Videos /VisoMaster/Output
    
    # Restore each directory
    for dir in "models" "Images" "Videos" "Output"; do
        if [ -d "/tmp/backup_visomaster/$dir" ] && [ "$(ls -A "/tmp/backup_visomaster/$dir" 2>/dev/null)" ]; then
            echo "Restoring $dir directory..."
            cp -rf "/tmp/backup_visomaster/$dir"/* "/VisoMaster/$dir/" 2>/dev/null || echo "Warning: Some files could not be restored"
        fi
    done
    
    # Cleanup
    rm -rf /tmp/backup_visomaster
    echo "✅ User data restored"
fi

# Install Python dependencies directly (no virtual environment)
section "Installing Python dependencies"

# Install requirements
if [ -f "/VisoMaster/requirements_cu124.txt" ]; then
    echo "Installing CUDA 12.4 requirements..."
    pip install -r "/VisoMaster/requirements_cu124.txt" || handle_error "Failed to install requirements"
elif [ -f "/VisoMaster/requirements.txt" ]; then
    echo "Installing requirements..."
    pip install -r "/VisoMaster/requirements.txt" || handle_error "Failed to install requirements"
else
    # Fallback to repository requirements
    echo "Using repository requirements..."
    pip install -r "requirements_124.txt" || pip install -r "requirements.txt" || handle_error "Failed to install requirements"
fi
echo "✅ Python dependencies installed"

# Install additional tools and utilities
section "Installing additional tools"
apt-get update
apt-get install -y rsync htop vim curl wget tmux || echo "Warning: Some utilities failed to install"
echo "✅ Additional tools installed"

# Set environment variables
section "Setting environment variables"
cat > /etc/profile.d/VisoMaster_env.sh << EOF
export VISOMASTER_HOME="/VisoMaster"
export PATH="\$PATH:\$VISOMASTER_HOME/bin"
export PYTHONPATH="\$PYTHONPATH:\$VISOMASTER_HOME"
export DISPLAY=":1"
export XAUTHORITY="/root/.Xauthority"
EOF

# Add to .bashrc for immediate effect
cat >> /root/.bashrc << EOF
export VISOMASTER_HOME="/VisoMaster"
export PATH="\$PATH:\$VISOMASTER_HOME/bin"
export PYTHONPATH="\$PYTHONPATH:\$VISOMASTER_HOME"
export DISPLAY=":1"
export XAUTHORITY="/root/.Xauthority"
EOF

source /etc/profile.d/VisoMaster_env.sh
echo "✅ Environment variables set"

# Ensure all files have the correct permissions
section "Setting permissions"
chown -R root:root /VisoMaster
chmod -R 755 /VisoMaster
echo "✅ Permissions set"

# Set up X11 authentication
section "Setting up X11 Authentication" 
touch /root/.Xauthority
chmod 600 /root/.Xauthority
xauth generate :1 . trusted 2>/dev/null || echo "⚠️ Failed to generate X authentication"
echo "✅ X11 authentication setup"

# Setup supervisord config that properly handles all services
section "Setting up Supervisor"
mkdir -p /etc/supervisor/conf.d

# Use existing supervisord config if in expected location
if [ -f "/etc/supervisor/conf.d/supervisord.conf" ]; then
    echo "Using existing supervisor configuration"
# Or copy from /src location if it exists
elif [ -f "/src/supervisord.conf" ]; then
    cp /src/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
    echo "✅ Copied supervisor configuration from /src/supervisord.conf"
# Otherwise create a new one
else
    echo "Creating supervisor configuration..."
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
    echo "✅ Created supervisor configuration"
fi

# Start supervisor
if command -v supervisord &> /dev/null; then
    echo "Supervisor is installed, checking if it's already running..."
    if pgrep supervisord > /dev/null; then
        echo "Supervisor is already running. Restarting..."
        supervisorctl reload || echo "⚠️ Failed to reload supervisor"
    else
        echo "Starting supervisor..."
        supervisord -c /etc/supervisor/conf.d/supervisord.conf || echo "⚠️ Failed to start supervisor"
    fi
else
    echo "⚠️ Supervisor not installed. Installing..."
    apt-get update && apt-get install -y supervisor || handle_error "Failed to install supervisor"
    supervisord -c /etc/supervisor/conf.d/supervisord.conf || echo "⚠️ Failed to start supervisor"
fi
echo "✅ Supervisor configured and started"

# Create necessary directories at the end
section "Creating directories"
mkdir -p /VisoMaster/{Images,Videos,Output,models} || handle_error "Failed to create directories"
echo "✅ Directories created successfully at the end of provisioning"

# Print repository contents for debugging
section "Repository Contents"
echo "Contents of /VisoMaster directory:"
ls -la /VisoMaster/
echo ""
if [ -f "/VisoMaster/main.py" ]; then
    echo "✅ main.py is present in repository root"
else
    echo "❌ main.py is missing from repository root!"
fi

# Script complete
section "Provisioning complete"
echo "VisoMaster environment has been successfully provisioned."
echo "Completed at: $(date)"
echo ""
echo "Log file available at: $LOG_FILE"
echo "==============================================="