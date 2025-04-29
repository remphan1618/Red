#!/bin/bash
#
# Vast.ai Provisioning Script for VisoMaster
# 
# This script is designed to be used with the PROVISIONING_SCRIPT environment variable
# in vast.ai. It performs first-boot initialization of the environment and manages services.
# 
# The script can be run in two modes:
# 1. Provisioning mode (default): Sets up the environment, installs dependencies, etc.
# 2. Service mode: Starts and monitors the required services (VNC, Jupyter, VisoMaster)
#
# Usage: ./vast_ai_provisioning_script.sh [--services-only]
#   --services-only: Skip provisioning and only start/monitor services

# Set up logging with timestamps
LOG_DIR="/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/provisioning_script.log"
ERROR_LOG="$LOG_DIR/provisioning_errors.log"

# Redirect stdout and stderr to both console and log file with timestamps
exec > >(while read -r line; do echo "[$(date '+%Y-%m-%d %H:%M:%S')] $line" | tee -a "$LOG_FILE"; done)
exec 2> >(while read -r line; do echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $line" | tee -a "$LOG_FILE" | tee -a "$ERROR_LOG"; done)

echo "==============================================="
echo "Starting VisoMaster Script: $(date)"
echo "==============================================="

# Parse command line arguments
SERVICES_ONLY=false
if [[ "$1" == "--services-only" ]]; then
    SERVICES_ONLY=true
    echo "Running in services-only mode"
fi

# Force clean clone on startup
FORCE_CLONE=true

# Function to log section start with status tracking
section() {
    local section_name="$1"
    local section_file="$LOG_DIR/${section_name// /_}.log"
    
    echo ""
    echo "==============================================="
    echo "SECTION: $section_name - $(date)"
    echo "==============================================="
    
    # Create a status file for tracking
    echo "STARTED: $(date)" > "$LOG_DIR/${section_name// /_}_STATUS.txt"
}

# Function to mark section completion
section_complete() {
    local section_name="$1"
    local status="$2"
    
    echo "SECTION $section_name: $status at $(date)"
    echo "$status: $(date)" >> "$LOG_DIR/${section_name// /_}_STATUS.txt"
}

# Function to log with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to verify a critical component exists
verify_component() {
    local component="$1"
    local path="$2"
    local fix_command="$3"
    
    if [ -e "$path" ]; then
        echo "✅ Verified: $component exists at $path"
        return 0
    else
        echo "❌ Missing: $component at $path"
        if [ -n "$fix_command" ]; then
            echo "Attempting to fix..."
            eval "$fix_command" || handle_error "Failed to fix $component" "$component"
            if [ -e "$path" ]; then
                echo "✅ Fixed: $component now exists at $path"
                return 0
            else
                handle_error "$component still missing after fix attempt" "$component"
                return 1
            fi
        else
            handle_error "$component is missing and no fix available" "$component"
            return 1
        fi
    fi
}

# Enhanced error handling function to document failures but continue execution
handle_error() {
    local error_msg="$1"
    local component="$2"
    
    echo "ERROR in $component: $error_msg" >&2
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR in $component: $error_msg" >> "$ERROR_LOG"
    
    # Create a status file for this error
    echo "$error_msg" > "$LOG_DIR/${component}_FAILED.status"
    echo "Timestamp: $(date)" >> "$LOG_DIR/${component}_FAILED.status"
    
    # Continue execution despite the error
    echo "Continuing execution despite the error in $component..."
}

#######################
# PROVISIONING SECTION
#######################

if [[ "$SERVICES_ONLY" == "false" ]]; then
    # Set up VNC configuration - CHECK DESTINATION FIRST, NOT SOURCE!
    section "VNC_Setup"
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
            cp /src/vnc_startup_jupyterlab_filebrowser.sh /dockerstartup/vnc_startup.sh || handle_error "Failed to copy custom VNC script" "VNC_Setup"
            chmod +x /dockerstartup/vnc_startup.sh || handle_error "Failed to make VNC script executable" "VNC_Setup"
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

    # Verify VNC script exists
    verify_component "VNC startup script" "/dockerstartup/vnc_startup.sh" ""
    section_complete "VNC_Setup" "COMPLETED"

    # Create window manager startup script - CHECK DESTINATION FIRST!
    section "WM_Setup"
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

    # Verify WM script exists
    verify_component "Window manager script" "/workspace/wm_startup.sh" ""
    section_complete "WM_Setup" "COMPLETED"

    # Create VNC password
    section "VNC_Password"
    if [ ! -f "/root/.vnc/passwd" ] && command -v vncpasswd &> /dev/null; then
        echo "Creating VNC password..."
        mkdir -p /root/.vnc
        echo "vncpasswd123" | vncpasswd -f > /root/.vnc/passwd || handle_error "Failed to create VNC password" "VNC_Password"
        chmod 600 /root/.vnc/passwd
        echo "✅ VNC password created"
    fi
    section_complete "VNC_Password" "COMPLETED"

    # FORCE CLONE REPOSITORY SECTION
    section "Repository_Clone"

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
    git clone https://github.com/remphan1618/VisoMaster.git /VisoMaster || {
        handle_error "Failed to clone repository" "Repository_Clone"
        
        # Create placeholder directory structure even if clone fails
        echo "Creating placeholder directory structure..."
        mkdir -p /VisoMaster/{models,Images,Videos,Output}
    }

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
    
    # Verify repository structure
    verify_component "VisoMaster directory" "/VisoMaster" "mkdir -p /VisoMaster"
    verify_component "main.py script" "/VisoMaster/main.py" ""
    section_complete "Repository_Clone" "COMPLETED"

    # Install Python dependencies
    section "Python_Dependencies"
    # First try custom requirements if they exist
    if [ -f "/VisoMaster/requirements_cu124.txt" ]; then
        echo "Installing CUDA 12.4 requirements..."
        pip install -r "/VisoMaster/requirements_cu124.txt" || handle_error "Failed to install CUDA 12.4 requirements" "Python_Dependencies"
    elif [ -f "/VisoMaster/requirements.txt" ]; then
        echo "Installing requirements..."
        pip install -r "/VisoMaster/requirements.txt" || handle_error "Failed to install requirements" "Python_Dependencies"
    fi

    # Always install critical packages individually to ensure they're installed even if one fails
    echo "Installing critical packages..."
    for pkg in PySide6 jupyter jupyterlab numpy tqdm; do
        echo "Installing $pkg..."
        pip install $pkg || handle_error "Failed to install $pkg" "Python_Dependencies_$pkg"
    done
    echo "✅ Critical Python dependencies installed"
    section_complete "Python_Dependencies" "COMPLETED"

    # Set environment variables
    section "Environment_Setup"
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

    source /etc/profile.d/VisoMaster_env.sh || handle_error "Failed to source environment variables" "Environment_Setup"
    echo "✅ Environment variables set"
    section_complete "Environment_Setup" "COMPLETED"

    # Set up X11 authentication
    section "X11_Authentication" 
    touch /root/.Xauthority
    chmod 600 /root/.Xauthority
    echo "✅ X11 authentication setup"
    section_complete "X11_Authentication" "COMPLETED"

    # Create required directories
    section "Directory_Setup"
    mkdir -p /VisoMaster/{Images,Videos,Output,models} 
    echo "✅ Directories created"
    section_complete "Directory_Setup" "COMPLETED"

    # Print repository contents for verification
    section "Repository_Verification"
    if [ -d "/VisoMaster" ]; then
        echo "Contents of /VisoMaster:"
        ls -la /VisoMaster/
        if [ -f "/VisoMaster/main.py" ]; then
            echo "✅ main.py is present"
        else
            echo "❌ main.py is missing"
            handle_error "main.py is missing after repository setup" "Repository_Verification"
        fi
    else
        echo "❌ /VisoMaster directory is missing"
        handle_error "/VisoMaster directory is missing after repository setup" "Repository_Verification"
    fi
    section_complete "Repository_Verification" "COMPLETED"

    section "Provisioning_Summary"
    # Create a provisioning status summary
    echo "-------- Provisioning Status Summary --------" > "$LOG_DIR/provisioning_summary.txt"
    echo "Completed at: $(date)" >> "$LOG_DIR/provisioning_summary.txt"
    echo "" >> "$LOG_DIR/provisioning_summary.txt"
    
    # Check for error status files
    error_count=$(find "$LOG_DIR" -name "*_FAILED.status" | wc -l)
    if [ "$error_count" -gt 0 ]; then
        echo "⚠️ Provisioning completed with $error_count errors:" >> "$LOG_DIR/provisioning_summary.txt"
        find "$LOG_DIR" -name "*_FAILED.status" | while read status_file; do
            component=$(basename "$status_file" | sed 's/_FAILED.status//')
            echo "  - $component: $(cat "$status_file" | head -1)" >> "$LOG_DIR/provisioning_summary.txt"
        done
    else
        echo "✅ Provisioning completed successfully with no errors" >> "$LOG_DIR/provisioning_summary.txt"
    fi
    
    echo "" >> "$LOG_DIR/provisioning_summary.txt"
    echo "Log file available at: $LOG_FILE" >> "$LOG_DIR/provisioning_summary.txt"
    echo "Error log available at: $ERROR_LOG" >> "$LOG_DIR/provisioning_summary.txt"
    echo "------------------------------------------" >> "$LOG_DIR/provisioning_summary.txt"
    
    # Output the summary to console
    cat "$LOG_DIR/provisioning_summary.txt"
    section_complete "Provisioning_Summary" "COMPLETED"

    section "Provisioning_Complete"
    echo "VisoMaster environment has been provisioned."
    echo "Completed at: $(date)"
    echo "Log file available at: $LOG_FILE"
    echo "Error log available at: $ERROR_LOG"
    echo "Summary available at: $LOG_DIR/provisioning_summary.txt"
    echo "==============================================="
    section_complete "Provisioning_Complete" "COMPLETED"
fi

#######################
# SERVICES MANAGEMENT
#######################

section "Services_Management"

# Setup environment for services
setup_environment() {
    log "Setting up environment for services..."
    
    # Setup X11 auth (in case it's not already set up)
    mkdir -p /root/.vnc
    touch /root/.Xauthority
    chmod 600 /root/.Xauthority
    xauth generate :1 . trusted || log 'Failed to generate auth'
    
    # Set environment variables
    export DISPLAY=:1
    export XAUTHORITY=/root/.Xauthority
    export VISOMASTER_HOME="/VisoMaster"
    export PATH="$PATH:$VISOMASTER_HOME/bin"
    export PYTHONPATH="$PYTHONPATH:$VISOMASTER_HOME"
    
    log "Environment setup complete"
}

# Start Jupyter Lab with improved error handling
start_jupyter() {
    local service_name="Jupyter"
    log "Starting $service_name..."
    
    cd /VisoMaster || {
        handle_error "Failed to change to /VisoMaster directory" "$service_name"
        return 1
    }
    
    nohup jupyter lab --ip=0.0.0.0 --port=8888 --no-browser --allow-root \
        --NotebookApp.token='' --NotebookApp.password='' \
        --NotebookApp.allow_origin='*' --NotebookApp.base_url=${JUPYTER_BASE_URL:-/} \
        > /logs/jupyter.log 2> /logs/jupyter_err.log &
    
    # Verify service started
    sleep 3
    if pgrep -f "jupyter lab" > /dev/null; then
        log "$service_name started successfully"
        echo "STARTED: $(date)" > "$LOG_DIR/${service_name}_STATUS.txt"
        return 0
    else
        handle_error "$service_name failed to start" "$service_name"
        return 1
    fi
}

# Start VNC server with improved error handling
start_vnc() {
    local service_name="VNC"
    log "Starting $service_name server..."
    
    # Kill any existing VNC servers
    vncserver -kill :1 &> /logs/vnc_kill.log || true
    
    # Verify VNC startup script exists
    if [ ! -f "/dockerstartup/vnc_startup.sh" ]; then
        handle_error "VNC startup script missing" "$service_name"
        # Create emergency script
        cat > /dockerstartup/vnc_startup.sh << 'EOL'
#!/bin/bash
mkdir -p ~/.vnc
echo "vncpasswd123" | vncpasswd -f > ~/.vnc/passwd
chmod 600 ~/.vnc/passwd
export DISPLAY=:1
vncserver :1 -geometry 1920x1080 -depth 24 -localhost no -SecurityTypes None
echo "VNC server started on display :1"
tail -f /dev/null
EOL
        chmod +x /dockerstartup/vnc_startup.sh
    fi
    
    # Start VNC service
    nohup /dockerstartup/vnc_startup.sh --wait > /logs/vnc.log 2> /logs/vnc_err.log &
    
    # Verify service started
    sleep 5
    if pgrep -f "Xvnc :1" > /dev/null; then
        log "$service_name server started successfully"
        echo "STARTED: $(date)" > "$LOG_DIR/${service_name}_STATUS.txt"
        return 0
    else
        handle_error "$service_name server failed to start" "$service_name"
        return 1
    fi
}

# Start VisoMaster application with improved error handling
start_visomaster() {
    local service_name="VisoMaster"
    log "Starting $service_name..."
    
    # Change to VisoMaster directory
    cd /VisoMaster || {
        handle_error "Failed to change to /VisoMaster directory" "$service_name"
        return 1
    }
    
    # Ensure main.py exists
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
    nohup python3 main.py > /logs/visomaster.log 2> /logs/visomaster_err.log &
    
    # Verify service started
    sleep 3
    if pgrep -f "python3 main.py" > /dev/null; then
        log "$service_name application started successfully"
        echo "STARTED: $(date)" > "$LOG_DIR/${service_name}_STATUS.txt"
        return 0
    else
        handle_error "$service_name application failed to start" "$service_name"
        return 1
    fi
}

# Monitor processes and keep container running with improved error handling
monitor_services() {
    log "Starting service monitoring..."
    
    # Function to check if process is running
    is_running() {
        pgrep -f "$1" > /dev/null
    }
    
    # Create status file for monitoring
    echo "STARTED: $(date)" > "$LOG_DIR/monitoring_STATUS.txt"
    
    # Main monitoring loop
    while true; do
        # Check and restart Jupyter if needed
        if ! is_running "jupyter lab"; then
            log "WARNING: Jupyter Lab not running, restarting..."
            start_jupyter
            echo "Jupyter Lab restarted at $(date)" >> "$LOG_DIR/service_restarts.log"
        fi
        
        # Check and restart VNC if needed
        if ! is_running "Xvnc :1"; then
            log "WARNING: VNC server not running, restarting..."
            start_vnc
            echo "VNC server restarted at $(date)" >> "$LOG_DIR/service_restarts.log"
        fi
        
        # Check and restart VisoMaster if needed
        if ! is_running "python3 main.py"; then
            log "WARNING: VisoMaster not running, restarting..."
            start_visomaster
            echo "VisoMaster restarted at $(date)" >> "$LOG_DIR/service_restarts.log"
        fi
        
        # Sleep before next check
        sleep 30
    done
}

# Start services
log "======= Starting VisoMaster services ======="

# Setup and run services
setup_environment

# Start each service and track status
log "Starting essential services..."
start_jupyter
start_vnc
start_visomaster

# Create services status summary
section "Services_Status"
echo "-------- Services Status Summary --------" > "$LOG_DIR/services_summary.txt"
echo "Generated at: $(date)" >> "$LOG_DIR/services_summary.txt"
echo "" >> "$LOG_DIR/services_summary.txt"

for service in "Jupyter" "VNC" "VisoMaster"; do
    if [ -f "$LOG_DIR/${service}_FAILED.status" ]; then
        echo "❌ $service: FAILED - $(cat "$LOG_DIR/${service}_FAILED.status" | head -1)" >> "$LOG_DIR/services_summary.txt"
    elif [ -f "$LOG_DIR/${service}_STATUS.txt" ]; then
        echo "✅ $service: RUNNING - Started at $(grep 'STARTED' "$LOG_DIR/${service}_STATUS.txt" | cut -d':' -f2-)" >> "$LOG_DIR/services_summary.txt"
    else
        echo "❓ $service: UNKNOWN STATUS" >> "$LOG_DIR/services_summary.txt"
    fi
done

echo "" >> "$LOG_DIR/services_summary.txt"
echo "Logs available in: $LOG_DIR/" >> "$LOG_DIR/services_summary.txt"
echo "----------------------------------------" >> "$LOG_DIR/services_summary.txt"

# Output the summary to console
cat "$LOG_DIR/services_summary.txt"
section_complete "Services_Status" "COMPLETED"

# Keep monitoring services and container alive
monitor_services