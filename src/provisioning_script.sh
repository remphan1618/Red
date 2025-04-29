#!/bin/bash
# VNC provisioning script for VisoMaster
# This script will be run by the provisioning system to prepare the environment

echo "==============================================="
echo "Starting VisoMaster Provisioning: $(date)"
echo "==============================================="

LOG_FILE="/logs/provisioning_script.log"
mkdir -p /logs

# Function to log section headers
section() {
    echo -e "\n===============================================" | tee -a $LOG_FILE
    echo "SECTION: $1 - $(date)" | tee -a $LOG_FILE
    echo "===============================================" | tee -a $LOG_FILE
}

# Install SSH server
section "Installing SSH server"
if dpkg -l | grep -q openssh-server; then
    echo "✅ SSH server already installed" | tee -a $LOG_FILE
else
    apt-get update && apt-get install -y openssh-server | tee -a $LOG_FILE
    echo "✅ SSH server installed" | tee -a $LOG_FILE
fi

# Set up VNC environment
section "Setting up VNC environment"
if [ -f "/src/vnc_startup_jupyterlab_filebrowser.sh" ]; then
    mkdir -p /dockerstartup
    cp /src/vnc_startup_jupyterlab_filebrowser.sh /dockerstartup/vnc_startup.sh
    chmod +x /dockerstartup/vnc_startup.sh
    echo "✅ Copied VNC filebrowser startup script to /dockerstartup/vnc_startup.sh" | tee -a $LOG_FILE
else
    echo "⚠️ VNC startup script not found" | tee -a $LOG_FILE
fi

# Clone or update repository
section "Cloning/Updating repository"
REPO_DIR="/VisoMaster"
GIT_URL="https://github.com/remphan1618/VisoMaster.git"

if [ -d "$REPO_DIR" ] && [ -d "$REPO_DIR/.git" ]; then
    echo "Repository already exists, updating..." | tee -a $LOG_FILE
    cd "$REPO_DIR"
    git pull | tee -a $LOG_FILE
    echo "✅ Repository updated" | tee -a $LOG_FILE
else
    echo "Attempting to clone VisoMaster repository..." | tee -a $LOG_FILE
    git clone "$GIT_URL" "$REPO_DIR" | tee -a $LOG_FILE
    echo "✅ Repository cloned successfully" | tee -a $LOG_FILE
fi

# Install Python dependencies
section "Installing Python dependencies"
if [ -f "$REPO_DIR/requirements.txt" ]; then
    source /opt/venv/bin/activate
    echo "Virtual environment activated" | tee -a $LOG_FILE

    # Install CUDA requirements
    if [ -f "/requirements_124.txt" ]; then
        echo "Installing CUDA 12.4 requirements..." | tee -a $LOG_FILE
        pip install -r /requirements_124.txt | tee -a $LOG_FILE
    fi

    # Install main requirements
    echo "Installing project requirements..." | tee -a $LOG_FILE
    pip install -r "$REPO_DIR/requirements.txt" | tee -a $LOG_FILE
    
    # Install critical missing packages - ensure these are always installed
    echo "Installing essential packages..." | tee -a $LOG_FILE
    pip install tqdm PySide6 | tee -a $LOG_FILE
    
    echo "✅ Python dependencies installed" | tee -a $LOG_FILE
else
    echo "⚠️ requirements.txt not found" | tee -a $LOG_FILE
fi

# Install additional tools
section "Installing additional tools"
apt-get update | tee -a $LOG_FILE
apt-get install -y vim htop wget curl rsync tmux | tee -a $LOG_FILE
echo "✅ Additional tools installed" | tee -a $LOG_FILE

# Set environment variables
section "Setting environment variables"
{
    echo 'export PYTHONPATH="$PYTHONPATH:/VisoMaster"'
    echo 'export PATH="$PATH:/VisoMaster/bin"'
} >> /etc/profile.d/visomaster.sh

# Also add to .bashrc for non-login shells
{
    echo 'export PYTHONPATH="$PYTHONPATH:/VisoMaster"'
    echo 'export PATH="$PATH:/VisoMaster/bin"'
} >> /root/.bashrc

echo "✅ Environment variables set" | tee -a $LOG_FILE

# Set permissions
section "Setting permissions"
chmod -R 755 "$REPO_DIR" 2>/dev/null || true
echo "✅ Permissions set" | tee -a $LOG_FILE

# Start supervisor
section "Starting supervisor"
if command -v supervisord &> /dev/null; then
    echo "Supervisor is installed, checking if it's already running..." | tee -a $LOG_FILE
    if ! pgrep -x "supervisord" > /dev/null; then
        echo "Starting supervisor..." | tee -a $LOG_FILE
        
        # Copy VNC startup script
        if [ -f "/src/vnc_startup_jupyterlab_filebrowser.sh" ]; then
            mkdir -p /dockerstartup
            cp /src/vnc_startup_jupyterlab_filebrowser.sh /dockerstartup/vnc_startup.sh
            chmod +x /dockerstartup/vnc_startup.sh
            echo "✅ VNC script copied successfully" | tee -a $LOG_FILE
        fi
        
        # Set up SSH properly
        mkdir -p /var/run/sshd || true
        echo "Setting up SSH properly..." | tee -a $LOG_FILE
        echo "✅ SSH configuration fixed" | tee -a $LOG_FILE
        
        # Start supervisor
        supervisord -c /etc/supervisor/conf.d/supervisord.conf | tee -a $LOG_FILE
    else
        echo "✅ Supervisor is already running" | tee -a $LOG_FILE
    fi
else
    echo "⚠️ Supervisor is not installed" | tee -a $LOG_FILE
    apt-get update && apt-get install -y supervisor | tee -a $LOG_FILE
    echo "✅ Supervisor installed" | tee -a $LOG_FILE
    supervisord -c /etc/supervisor/conf.d/supervisord.conf | tee -a $LOG_FILE
fi

# Note: Model downloading is now done ONLY in vast_ai_provisioning_script.sh as the final step

echo "===============================================" | tee -a $LOG_FILE
echo "Provisioning completed successfully: $(date)" | tee -a $LOG_FILE
echo "===============================================" | tee -a $LOG_FILE
