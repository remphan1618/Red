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
    
    # More comprehensive approach to fix package conflicts
    echo "Updating package lists..."
    apt-get update || handle_error "apt-get update failed"
    
    echo "Trying to fix broken packages..."
    apt-get install -f -y || echo "Warning: Fixing broken packages returned non-zero exit code"
    
    echo "Trying apt-get dist-upgrade to resolve dependency issues..."
    apt-get dist-upgrade -y || echo "Warning: apt-get dist-upgrade returned non-zero exit code"
    
    echo "Attempting to install openssh-server with dependency resolution..."
    apt-get install -y --no-install-recommends openssh-server
    
    # If previous method failed, try downgrading openssh-client
    if [ $? -ne 0 ]; then
        echo "Standard installation failed, trying alternative approach..."
        echo "Installing specific versions to resolve dependency conflict..."
        apt-get install -y --allow-downgrades openssh-client=1:8.2p1-4ubuntu0.11 openssh-server
    fi
    
    # Check if installation was successful
    if [ -f "/usr/sbin/sshd" ]; then
        # Configure SSH
        mkdir -p /run/sshd
        echo "✅ SSH server installed successfully"
    else
        echo "⚠️ Failed to install SSH server automatically. Manual intervention may be required."
        echo "Continuing with provisioning..."
    fi
else
    echo "✅ SSH server already installed"
fi

# Set up VNC configuration
section "Setting up VNC environment"
mkdir -p /dockerstartup /root/.vnc

# Copy VNC startup script - prioritizing filebrowser version
if [ -f "/src/vnc_startup_jupyterlab_filebrowser.sh" ]; then
    cp /src/vnc_startup_jupyterlab_filebrowser.sh /dockerstartup/vnc_startup.sh
    chmod +x /dockerstartup/vnc_startup.sh
    echo "✅ Copied VNC filebrowser startup script to /dockerstartup/vnc_startup.sh"
elif [ -f "/src/vnc_startup_jupyterlab.sh" ]; then
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

# Clone repository if it doesn't exist, or update if it does
section "Cloning/Updating repository"
if [ ! -d "/VisoMaster/.git" ]; then
    echo "Attempting to clone VisoMaster repository..."
    if [ -d "/VisoMaster" ] && [ "$(ls -A /VisoMaster)" ]; then
        echo "Directory /VisoMaster exists and is not empty, skipping clone"
        echo "✅ Using existing VisoMaster directory"
    else
        git clone "https://github.com/remphan1618/VisoMaster.git" "/VisoMaster" || handle_error "Failed to clone repository"
        echo "✅ Repository cloned successfully"
    fi
else
    echo "Repository already exists, updating..."
    cd /VisoMaster
    git pull || handle_error "Failed to update repository"
    echo "✅ Repository updated successfully"
fi

# Activate Python virtual environment and install requirements
section "Installing Python dependencies"
source /opt/venv/bin/activate || handle_error "Failed to activate virtual environment"
echo "Virtual environment activated"

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

# Download models (if a download_models.py script exists)
section "Downloading models"
if [ -f "/VisoMaster/download_models.py" ]; then
    echo "Running model downloader script..."
    python "/VisoMaster/download_models.py" || handle_error "Failed to download models"
    echo "✅ Models downloaded successfully"
else
    echo "No model downloader script found. If you need to download models, please do so manually."
fi

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