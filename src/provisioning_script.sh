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

# Ensure SSH is properly configured
mkdir -p /var/run/sshd
chmod 0755 /var/run/sshd
ssh-keygen -A
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
echo "UsePAM no" >> /etc/ssh/sshd_config
echo "✅ SSH configuration fixed" | tee -a $LOG_FILE

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

# Ensure window manager startup script exists
mkdir -p /workspace
if [ -f "/src/debian/icewm/wm_startup.sh" ]; then
    cp /src/debian/icewm/wm_startup.sh /workspace/wm_startup.sh
    chmod +x /workspace/wm_startup.sh
    echo "✅ Window manager startup script copied" | tee -a $LOG_FILE
else
    # Create a simple window manager script if not found
    cat > /workspace/wm_startup.sh << 'EOL'
#!/bin/bash
exec openbox-session
EOL
    chmod +x /workspace/wm_startup.sh
    echo "✅ Created basic window manager startup script" | tee -a $LOG_FILE
fi

# Set up X11 authentication
touch /root/.Xauthority
xauth generate :1 . trusted 2>/dev/null || echo "Failed to generate X authentication"
echo "✅ X11 authentication set up" | tee -a $LOG_FILE

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

# Install Python dependencies directly (no virtual environment)
section "Installing Python dependencies"
if [ -f "$REPO_DIR/requirements.txt" ]; then
    echo "Installing project requirements..." | tee -a $LOG_FILE
    # Fix dependency issues first
    apt-get update
    apt-get install -y -f
    apt-get autoremove -y
    
    # Install GUI dependencies first
    apt-get install -y --no-install-recommends \
        libgl1-mesa-glx \
        libegl1 \
        libxkbcommon-x11-0 \
        libglib2.0-0 \
        libdbus-1-3 \
        libxcb-icccm4 \
        libxcb-image0 \
        libxcb-keysyms1 \
        libxcb-randr0 \
        libxcb-render-util0 \
        libxcb-xinerama0 \
        libxcb-shape0 | tee -a $LOG_FILE
    
    # Install CUDA requirements if available
    if [ -f "/VisoMaster/requirements_cu124.txt" ]; then
        echo "Installing CUDA 12.4 requirements..." | tee -a $LOG_FILE
        pip install -r "/VisoMaster/requirements_cu124.txt" --no-cache-dir | tee -a $LOG_FILE
    fi
    
    # Install main requirements
    pip install -r "$REPO_DIR/requirements.txt" --no-cache-dir | tee -a $LOG_FILE
    
    # Always install critical packages
    echo "Installing critical packages..." | tee -a $LOG_FILE
    pip install PySide6 tqdm jupyter jupyterlab --upgrade --no-cache-dir | tee -a $LOG_FILE
    
    echo "✅ Python dependencies installed" | tee -a $LOG_FILE
else
    echo "⚠️ requirements.txt not found" | tee -a $LOG_FILE
fi

# Install additional tools
section "Installing additional tools"
apt-get update | tee -a $LOG_FILE
apt-get install -y -f vim htop wget curl rsync tmux | tee -a $LOG_FILE
echo "✅ Additional tools installed" | tee -a $LOG_FILE

# Set environment variables
section "Setting environment variables"
{
    echo 'export PYTHONPATH="$PYTHONPATH:/VisoMaster"'
    echo 'export PATH="$PATH:/VisoMaster/bin"'
    echo 'export DISPLAY=:1'
    echo 'export XAUTHORITY=/root/.Xauthority'
} >> /etc/profile.d/visomaster.sh

# Also add to .bashrc for non-login shells
{
    echo 'export PYTHONPATH="$PYTHONPATH:/VisoMaster"'
    echo 'export PATH="$PATH:/VisoMaster/bin"'
    echo 'export DISPLAY=:1'
    echo 'export XAUTHORITY=/root/.Xauthority'
    echo 'touch ~/.Xauthority'
    echo 'xauth generate :1 . trusted 2>/dev/null || echo "Failed to generate X authentication"'
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

echo "===============================================" | tee -a $LOG_FILE
echo "Provisioning completed successfully: $(date)" | tee -a $LOG_FILE
echo "===============================================" | tee -a $LOG_FILE
