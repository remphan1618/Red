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

# Copy VNC startup script - prioritizing filebrowser version
if [ -f "/src/vnc_startup_jupyterlab_filebrowser.sh" ]; then
    mkdir -p /dockerstartup
    cp /src/vnc_startup_jupyterlab_filebrowser.sh /dockerstartup/vnc_startup.sh
    chmod +x /dockerstartup/vnc_startup.sh
    echo "✅ Copied VNC filebrowser startup script to /dockerstartup/vnc_startup.sh"
elif [ -f "/src/vnc_startup_jupyterlab.sh" ]; then
    mkdir -p /dockerstartup
    cp /src/vnc_startup_jupyterlab.sh /dockerstartup/vnc_startup.sh
    chmod +x /dockerstartup/vnc_startup.sh
    echo "✅ Copied VNC startup script to /dockerstartup/vnc_startup.sh"
else
    echo "⚠️ Could not find VNC startup script. Supervisor may fail to start VNC."
fi

# Create VNC password
if [ ! -f "/root/.vnc/passwd" ] && command -v vncpasswd &> /dev/null; then
    echo "Creating VNC password..."
    echo "vncpasswd123" | vncpasswd -f > /root/.vnc/passwd
    chmod 600 /root/.vnc/passwd
    echo "✅ VNC password created"
fi

# Clone repository - FORCE CLEAN CLONE EVERY TIME
section "Cloning Repository"
echo "FORCE CLONING VisoMaster repository..."
REPO_DIR="/VisoMaster"
GIT_URL="https://github.com/remphan1618/VisoMaster.git"

# Backup important user data if needed
if [ -d "$REPO_DIR" ]; then
    echo "Backing up any existing user data..."
    mkdir -p /tmp/visomaster_backup
    
    # List of important directories to backup
    for dir in "models" "Images" "Videos" "Output"; do
        if [ -d "$REPO_DIR/$dir" ] && [ "$(ls -A "$REPO_DIR/$dir" 2>/dev/null)" ]; then
            echo "Backing up $dir directory..."
            mkdir -p "/tmp/visomaster_backup/$dir"
            cp -r "$REPO_DIR/$dir"/* "/tmp/visomaster_backup/$dir/" || echo "Warning: Some files in $dir could not be backed up"
        fi
    done
    
    # Remove the old directory completely
    echo "Removing old VisoMaster directory..."
    rm -rf "$REPO_DIR"
fi

# Clone a fresh copy
echo "Cloning fresh repository..."
git clone "$GIT_URL" "$REPO_DIR" || handle_error "Failed to clone repository"

# Check if clone was successful
if [ ! -f "$REPO_DIR/main.py" ]; then
    echo "⚠️ Repository cloned but main.py not found! Checking repository contents:"
    ls -la "$REPO_DIR"
    echo "⚠️ The VisoMaster repository seems to be empty or missing key files. Please check repository URL and access."
else
    echo "✅ Repository cloned successfully with main.py present"
fi

# Restore backed up data if it exists
if [ -d "/tmp/visomaster_backup" ]; then
    echo "Restoring user data..."
    
    # Create necessary directories
    mkdir -p "$REPO_DIR/models" "$REPO_DIR/Images" "$REPO_DIR/Videos" "$REPO_DIR/Output"
    
    # Restore each directory
    for dir in "models" "Images" "Videos" "Output"; do
        if [ -d "/tmp/visomaster_backup/$dir" ] && [ "$(ls -A "/tmp/visomaster_backup/$dir" 2>/dev/null)" ]; then
            echo "Restoring $dir directory..."
            cp -r "/tmp/visomaster_backup/$dir"/* "$REPO_DIR/$dir/" || echo "Warning: Some files in $dir could not be restored"
        fi
    done
    
    # Clean up backup
    rm -rf /tmp/visomaster_backup
    echo "✅ User data restored successfully"
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
EOF
source /etc/profile.d/VisoMaster_env.sh
echo "✅ Environment variables set"

# Ensure all files have the correct permissions
section "Setting permissions"
chown -R root:root /VisoMaster
chmod -R 755 /VisoMaster
echo "✅ Permissions set"

# Start supervisor if it's installed
section "Starting supervisor"
if command -v supervisord &> /dev/null; then
    echo "Supervisor is installed, checking if it's already running..."
    if pgrep supervisord > /dev/null; then
        echo "Supervisor is already running. Skipping startup."
    else
        echo "Starting supervisor..."
        
        # Make sure VNC script is properly set up before starting supervisor
        if [ -f "/src/vnc_startup_jupyterlab_filebrowser.sh" ]; then
            echo "Copying VNC filebrowser script to /dockerstartup/"
            mkdir -p /dockerstartup
            cp /src/vnc_startup_jupyterlab_filebrowser.sh /dockerstartup/vnc_startup.sh
            chmod +x /dockerstartup/vnc_startup.sh
            echo "✅ VNC script copied successfully"
        elif [ -f "/src/vnc_startup_jupyterlab.sh" ]; then
            echo "Copying VNC script to /dockerstartup/"
            mkdir -p /dockerstartup
            cp /src/vnc_startup_jupyterlab.sh /dockerstartup/vnc_startup.sh
            chmod +x /dockerstartup/vnc_startup.sh
            echo "✅ VNC script copied successfully"
        else
            echo "⚠️ Could not find VNC startup script. Supervisor may fail to start VNC."
        fi
        
        # Fix SSH configuration
        echo "Setting up SSH properly..."
        mkdir -p /run/sshd
        mkdir -p /var/run/sshd
        if ! [ -f "/etc/ssh/ssh_host_rsa_key" ]; then
            ssh-keygen -A
        fi
        chmod 600 /etc/ssh/ssh_host_*_key
        chmod 644 /etc/ssh/ssh_host_*.pub
        grep -q "^UsePAM no" /etc/ssh/sshd_config || echo "UsePAM no" >> /etc/ssh/sshd_config
        echo "✅ SSH configuration fixed"
        
        if [ -f "/etc/supervisor/conf.d/supervisord.conf" ]; then
            supervisord -c /etc/supervisor/conf.d/supervisord.conf
            echo "✅ Supervisor started with config: /etc/supervisor/conf.d/supervisord.conf"
        else
            echo "❌ Supervisor config not found at /etc/supervisor/conf.d/supervisord.conf"
            echo "Checking for supervisor config in alternate locations..."
            if [ -f "/src/supervisord.conf" ]; then
                # Copy config to expected location
                mkdir -p /etc/supervisor/conf.d
                cp /src/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
                supervisord -c /etc/supervisor/conf.d/supervisord.conf
                echo "✅ Copied config from /src/supervisord.conf and started supervisor"
            else
                echo "❌ Could not find supervisor config. Services will not start automatically."
            fi
        fi
    fi
else
    echo "❌ Supervisor not installed. Consider adding it to the Dockerfile."
fi

# Create necessary directories at the end
section "Creating directories"
mkdir -p /VisoMaster/{Images,Videos,Output,models} || handle_error "Failed to create directories"
echo "✅ Directories created successfully at the end of provisioning"

# Show contents of VisoMaster directory for debugging
section "VisoMaster Directory Contents"
echo "Contents of /VisoMaster:"
ls -la /VisoMaster
echo ""

if [ -f "/VisoMaster/main.py" ]; then
    echo "✅ main.py found in the repository"
else
    echo "⚠️ main.py NOT found in the repository - visomaster service will fail to start"
fi

# Script complete
section "Provisioning complete"
echo "VisoMaster environment has been successfully provisioned."
echo "Completed at: $(date)"
echo ""
echo "You can now use the following:"
echo "- Repository: /VisoMaster"
echo "- Images directory: /VisoMaster/Images"
echo "- Videos directory: /VisoMaster/Videos"
echo "- Output directory: /VisoMaster/Output"
echo "- Models directory: /VisoMaster/models"
echo ""
echo "Log file available at: $LOG_FILE"
echo "==============================================="
# Note: Model downloading has been moved to a dedicated supervisord program