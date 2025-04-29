# Red Project - Vast.ai Environment Documentation

## AI Assistant Context Section
This section is automatically updated by the health check script to provide AI assistants (Claude, Copilot, etc.) with current context about your setup.

### Current System Configuration
- **Last Updated**: $(date)
- **Base Image**: remphan/visomasterdockah:latest
- **Vast.ai Command**: 
```
vastai create instance <OFFER_ID> --image remphan/visomasterdockah:latest --env '-p 1111:1111 -p 6006:6006 -p 8080:8080 -p 8384:8384 -p 72299:72299 -p 5901:5901 -p 6901:6901 -p 8585:8585 -p 22:22 -p 8888:8888 -e OPEN_BUTTON_PORT=1111 -e OPEN_BUTTON_TOKEN=1 -e PORTAL_CONFIG="localhost:1111:11111:/:Instance Portal|localhost:8080:18080:/:Jupyter|localhost:8080:8080:/terminals/1:Jupyter Terminal|localhost:8384:18384:/:Syncthing|localhost:6006:16006:/:Tensorboard" -e JUPYTER_DIR=/ -e PROVISIONING_SCRIPT=https://raw.githubusercontent.com/remphan1618/Red/main/vast_ai_provisioning_script.sh VNC_PASSWORDLESS=true JUPYTER_DIR=/'
```

### Current On-Start Script
```bash
#!/bin/bash
if [ -n "$PROVISIONING_SCRIPT" ]; then
  curl -s -o /tmp/prov.sh "$PROVISIONING_SCRIPT" || wget -q -O /tmp/prov.sh "$PROVISIONING_SCRIPT"
  chmod +x /tmp/prov.sh && bash /tmp/prov.sh
fi
for s in /vast_ai_provisioning_script.sh /src/provisioning_script.sh /root/provisioning_script.sh; do
  if [ -f "$s" ]; then echo "Running: $s"; bash "$s"; fi
done
```

### Provisioning Scripts Status
- **/vast_ai_provisioning_script.sh**: $(if [ -f /vast_ai_provisioning_script.sh ]; then echo "Present"; else echo "Not found"; fi)
- **/src/provisioning_script.sh**: $(if [ -f /src/provisioning_script.sh ]; then echo "Present"; else echo "Not found"; fi)
- **/root/provisioning_script.sh**: $(if [ -f /root/provisioning_script.sh ]; then echo "Present"; else echo "Not found"; fi)

### Service Status Overview
```
$(supervisorctl status)
```

### Critical Files
- **Dockerfile**: Updated with CUDA 12.4.1 support
- **Requirements**: Primary requirements file at `/VisoMaster/requirements.txt`
- **VNC Startup**: Using `/dockerstartup/vnc_startup.sh` (filebrowser version)

---

## Overview
The **Red** project provides a containerized machine learning environment tailored for [Vast.ai](https://vast.ai/) GPU instances. Its core function is to automate setup and execution of **VisoMaster** (an ML project), along with supporting tools: **VNC** for remote GUI, **JupyterLab** for interactive development, and **SSH** for secure access. The environment is designed to be fully self-contained, with all services starting automatically upon container launch.

---

## Proactive Monitoring and AI Assistance

### Automated Health Check System

To prevent configuration drift and catch issues early, the Red project implements an automated health check system that works with AI assistants like Claude and GitHub Copilot:

#### Health Check Script
- **Location**: `/workspace/health_check.sh`
- **Purpose**: Collects system status, logs, and configuration information
- **Execution**: Runs every 6 hours via cron job
- **Output**: Generates `/workspace/system_status.md` with current system state

#### AI Assistant Integration
1. **Scheduled Review Sessions**:
   - Set calendar reminders for AI check-ins every 24-48 hours
   - Share the generated `system_status.md` with the AI assistant
   - Ask specific questions about system health and potential issues

2. **Continuous Improvement Process**:
   - AI identifies potential issues or inefficiencies
   - Recommendations are logged in `/workspace/improvement_log.md`
   - Changes are tracked with git commits referencing the AI recommendations

3. **Documentation Updates**:
   - This documentation file is automatically updated with each health check
   - Changes and problem resolutions are appended to the relevant sections
   - The "Last updated" timestamp is refreshed automatically

#### Sample Health Check Implementation

```bash
#!/bin/bash
# /workspace/health_check.sh - Automated system health check for Red project

# Create status file with timestamp
echo "# Red Project System Status - $(date)" > /workspace/system_status.md
echo "## Environment Information" >> /workspace/system_status.md
echo "\`\`\`" >> /workspace/system_status.md
env | grep -E 'CUDA|PYTHON|VNC|JUPYTER' >> /workspace/system_status.md
echo "\`\`\`" >> /workspace/system_status.md

# Check running services
echo "## Service Status" >> /workspace/system_status.md
echo "\`\`\`" >> /workspace/system_status.md
supervisorctl status >> /workspace/system_status.md
echo "\`\`\`" >> /workspace/system_status.md

# Check recent logs
echo "## Recent Log Entries" >> /workspace/system_status.md
echo "\`\`\`" >> /workspace/system_status.md
find /logs -type f -name "*.log" -exec sh -c 'echo "=== $1 ==="; tail -n 20 "$1"' _ {} \; >> /workspace/system_status.md
echo "\`\`\`" >> /workspace/system_status.md

# Update documentation timestamp
sed -i "s/Last updated:.*$/Last updated: $(date)/" /workspace/docs_vast-ai-environment.md
```

#### Cron Setup for Automated Checks
```bash
# Add to crontab
0 */6 * * * /bin/bash /workspace/health_check.sh
```

---

## System Architecture & Goals

### Core Philosophy
- **Full automation**: The `Dockerfile` must handle all setup—no manual steps post-launch.
- **Diagnostic notebooks** are for troubleshooting only (not for installation/configuration).
- **Provisioning scripts** and **service management** must require zero manual intervention.
- **Robust service recovery**: Services should automatically restart if they fail.

### Key Components

#### Docker Container
- **Base**: NVIDIA CUDA-enabled Ubuntu 20.04
- **Python env**: Python 3.10 with PySide6 and tqdm for ML applications
- **VNC**: NoVNC and TigerVNC for browser-based and native VNC client access
- **Auto-installs/configures** all software, including Firefox for VNC browsing
- **Window Manager**: IceWM for lightweight GUI within VNC

#### Provisioning System
- **Root script**: `/vast_ai_provisioning_script.sh` (invoked by Vast.ai)
- **Source script**: `/src/provisioning_script.sh` (used inside container)
  - Both must be fully automated and idempotent
  - Handles cloning VisoMaster repository
  - Installs necessary Python dependencies
  - Sets up environment variables

#### Service Management
- **Supervisor daemon** manages:
  - SSH server (currently has issues but not critical)
  - JupyterLab (running on port 8080/8081)
  - VNC server (port 5901 for direct VNC, 6901 for noVNC browser access)
  - Filebrowser (port 8585)
  - VisoMaster application

#### VisoMaster Application
- **Cloned from GitHub** during provisioning
- **Core ML application** for the environment
- **PySide6 dependency** required for UI functionality
- **tqdm dependency** required for model downloads

#### Diagnostic and Access Tools
- **Pre-installed** by Dockerfile
- **Centralized logging** in `/logs` and `/Logs` directories
- **Enhanced access security** with customizable VNC authentication settings

---

## Fixed Issues and Current Status

### Recently Fixed Issues

#### 1. NoVNC Installation Issues
- **Problem**: Docker build failed during NoVNC installation due to environment variable expansion issues
- **Solution**: Replaced environment variable references with hard-coded paths in Dockerfile
- **Status**: ✅ Fixed

#### 2. VNC Security Restrictions
- **Problem**: TigerVNC was refusing to run without authentication when exposed to all interfaces
- **Solution**: Added `--I-KNOW-THIS-IS-INSECURE` flag to VNC startup command
- **Status**: ✅ Fixed

#### 3. Missing Python Dependencies
- **Problem**: VisoMaster failing to start due to missing PySide6, model downloads failing due to missing tqdm
- **Solution**: Added explicit pip install commands in Dockerfile for both packages
- **Status**: ✅ Fixed

#### 4. VNC Service Stability
- **Problem**: VNC service was exiting after startup
- **Solution**: Added infinite loop to keep the service alive and prevent supervisor from restarting it
- **Status**: ✅ Fixed

### Current Challenges

#### 1. Window Manager Issues
- **Problem**: IceWM not connecting properly to X server
- **Current status**: 🔴 Unresolved
- **Diagnostic logs**: Window manager is unable to connect to display `:1`
- **Impact**: VNC connects but shows a blank/black screen

#### 2. SSH Service Failures
- **Problem**: SSH service fails with status 255
- **Current status**: 🟡 Not critical (as VNC and Jupyter provide access)
- **Diagnostic logs**: SSH service repeatedly exits and supervisor eventually gives up

#### 3. VisoMaster UI
- **Problem**: Although PySide6 is now installed, VisoMaster UI might still need adjustments for VNC environment
- **Current status**: 🟡 Partially resolved

---

## Complete Workflow: From Dockerfile to Running Application

### 1. Dockerfile Build Process
1. **Base image selection**: Starts with NVIDIA CUDA 11.8.0 base Ubuntu 20.04
2. **System setup**:
   - Sets environment variables for VNC
   - Creates logging directories
   - Installs Python 3.10 from deadsnakes PPA
   - Installs required system packages (VNC, window manager, tools)
3. **Python environment setup**:
   - Creates Python virtual environment
   - Installs Python dependencies like PySide6 and tqdm
4. **Service setup**:
   - Installs NoVNC for browser-based VNC access
   - Installs filebrowser for web file management
   - Installs Firefox for browser access within VNC
5. **Startup configuration**:
   - Sets up supervisor configuration
   - Prepares startup scripts
   - Creates proper environment for SSH and VNC
   - Exposes necessary ports

### 2. Container Startup Sequence
1. **Entry point execution**: `/bin/bash /root/startup.sh`
2. **Provisioning script run**: Checks for and executes provisioning script
   - Clones VisoMaster repository (if not already present)
   - Installs Python dependencies from requirements
   - Downloads ML models (using tqdm)
   - Sets up environment variables
3. **Service initialization**:
   - Supervisor daemon starts
   - Individual services (VNC, SSH, Jupyter) are launched by supervisor
   - Logs are directed to `/logs` directory

### 3. VNC Environment Setup
1. **TigerVNC server**: Starts with security disabled (as requested)
2. **Window manager**: IceWM attempts to start (currently failing)
3. **Application startup**:
   - JupyterLab starts on port 8080/8081
   - Filebrowser starts on port 8585
   - VisoMaster application starts

### 4. User Connection Options
1. **VNC access**:
   - Direct VNC client connection to port 5901
   - Browser-based noVNC access on port 6901
2. **JupyterLab access**:
   - Browser connection to port 8080/8081
3. **Filebrowser access**:
   - Browser connection to port 8585

---

## Current Troubleshooting Focus

The primary focus for troubleshooting is resolving the window manager connection issues:

```
xset: unable to open display ":1"
icewmbg: Can't open display: <none>. X must be running and $DISPLAY set.
IceWM: Can't open display: <none>. X must be running and $DISPLAY set.
```

This suggests issues with how the X server is being initialized or how the DISPLAY variable is being passed to the window manager process.

---

## Best Practices for Dockerfile Development

- **Complete Automation:** No manual steps after launch
- **Robust Error Handling:** Handle all edge cases, log every operation
- **Service Management:** Complete supervisor setup, correct startup order, health checks
- **Environment Consistency:** Pin dependency versions, verify tools
- **Security:** Sensible defaults, firewalls, secure credentials

---

## Monitoring & Debugging

- **Logs:** All services now log to `/logs` directory
- **Important logs to check:**
  - `wm_startup.log`: For window manager issues
  - `vnc.log`: For VNC server status
  - `visomaster.log`: For VisoMaster application issues
  - `supervisord.log`: For service startup/shutdown events
  - `no_vnc_startup.log`: For NoVNC web interface issues

---

## Setting Up New Instances

1. **Choose correct Docker image** (pre-configured, no extra steps)
2. **Set environment variables:**
   - `PROVISIONING_SCRIPT`: URL to provisioning script (optional)
   - `VNC_RESOLUTION`: Display resolution (optional, default 1280x1024)
   - `VNC_PW`: VNC password (optional, currently disabled for open access)
3. **Access the instance:**
   - VNC client to `[instance-ip]:5901`
   - Browser to `http://[instance-ip]:6901` for NoVNC
   - Browser to `http://[instance-ip]:8080` or `8081` for JupyterLab
   - Browser to `http://[instance-ip]:8585` for filebrowser

---

## Additional Resources

- [Docker documentation](https://docs.docker.com/)
- [Vast.ai documentation](https://vast.ai/docs/)
- [Supervisor documentation](http://supervisord.org/)
- [JupyterLab documentation](https://jupyterlab.readthedocs.io/)
- [TigerVNC documentation](https://tigervnc.org/)
- [NoVNC documentation](https://novnc.com/info.html)

---

*Document created: April 29, 2025*  
*Last updated: April 29, 2025*