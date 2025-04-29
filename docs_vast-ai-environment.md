# Red Project - Vast.ai Environment Documentation

## Overview
The **Red** project provides a containerized machine learning environment tailored for [Vast.ai](https://vast.ai/) GPU instances. Its core function is to automate setup and execution of **VisoMaster** (an ML project), along with supporting tools: **VNC** for remote GUI, **JupyterLab** for interactive development, and **SSH** for secure access.

---

## System Architecture & Goals

### Core Philosophy
- **Full automation**: The `Dockerfile` must handle all setup—no manual steps post-launch.
- **Diagnostic notebooks** are for troubleshooting only (not for installation/configuration).
- **Provisioning scripts** and **service management** must require zero manual intervention.

### Key Components

#### Docker Container
- **Base**: NVIDIA CUDA-enabled Ubuntu
- **Python env**: Correct version (Python 3.10 recommended)
- **VNC**: For graphical interface
- **Auto-installs/configures** all software

#### Provisioning System
- **Root script**: `/vast_ai_provisioning_script.sh` (invoked by Vast.ai)
- **Source script**: `/src/provisioning_script.sh` (used inside container)
  - Both must be fully automated and idempotent

#### Service Management
- **Supervisor daemon** manages:
  - SSH server
  - Jupyter notebook/lab
  - VNC server
  - WebSocket proxy (for browser access)
- All service setup is handled by the Dockerfile and provisioning scripts.

#### VisoMaster Application
- **Cloned from GitHub** during provisioning
- **Core ML application** for the environment
- **Handles conflicts** (existing directories) robustly

#### Diagnostic Notebooks
- **Pre-installed** by Dockerfile (e.g. `find_provisioning_script.ipynb`)
- **Located in a standard location** (e.g. `/notebooks/`)
- **For monitoring & troubleshooting only**

---

## Vast.ai Integration

### Startup Mechanisms

#### Docker Entrypoint/CMD
- Launches primary process and sets up base environment
- Handles all startup scenarios

#### Provisioning Script
- **Runs once** at first boot via `PROVISIONING_SCRIPT` env var
- Handles:
  - System dependency install
  - SSH/VNC setup
  - Cloning VisoMaster repo
  - Must be robust, idempotent, and error-tolerant

#### On-Start Script

```bash
#!/bin/bash
# Shortened On-Start Script for vast.ai

# Download and execute provisioning script from environment variable
if [ -n "$PROVISIONING_SCRIPT" ]; then
  echo "Using PROVISIONING_SCRIPT: $PROVISIONING_SCRIPT"
  curl -s -o /tmp/prov.sh "$PROVISIONING_SCRIPT" || wget -q -O /tmp/prov.sh "$PROVISIONING_SCRIPT"
  chmod +x /tmp/prov.sh && bash /tmp/prov.sh
# Fallback to local files
else
  for script in /vast_ai_provisioning_script.sh /src/provisioning_script.sh /VisoMaster/src/provisioning_script.sh; do
    if [ -f "$script" ]; then
      echo "Found script: $script"
      bash "$script"
      exit 0
    fi
  done
  echo "ERROR: No provisioning script found"
fi
```

---

## Current Issues & Workarounds

### Missing Log Files
- **Possible causes:**
  - Supervisor not installed/configured in Dockerfile
  - `/logs` directory not created or permission issues
  - Scripts not executed in correct order
  - Error handling/logging not robust
  - Service startup order and dependencies unclear

### Identified Issues

#### Supervisor Not Starting
- **Cause:** Not installed/configured in Dockerfile
- **Impact:** SSH, Jupyter, VNC don’t start automatically
- **Fix:** Explicitly install & configure supervisor in Dockerfile

#### VisoMaster Repo Conflict
- **Cause:** Cloning into existing directory fails
- **Impact:** Provisioning script errors
- **Fix:** Implement robust clone logic—handle pre-existing directories

#### Python Version Mismatch
- **Cause:** Using Python 3.8 instead of 3.10
- **Impact:** JupyterLab dependency conflicts
- **Fix:** Dockerfile must install Python 3.10 explicitly

---

## Monitoring & Debugging

- **Logs:** `/logs` directory (ensure pre-created, permissions set)
- **Diagnostic notebook:** `find_provisioning_script.ipynb`
  - Check log files
  - Monitor services
  - Manually start services
  - Diagnose repo issues

---

## Setting Up New Instances

1. **Choose correct Docker image** (pre-configured, no extra steps)
2. **Set environment variables:**
   - `PROVISIONING_SCRIPT`: URL to provisioning script (optional)
   - `VNC_RESOLUTION`: Display resolution (optional)
   - `VNC_PW`: VNC password (optional)
3. **Monitor startup:**
   - Check `/logs`
   - Use diagnostic notebooks if needed

---

## Best Practices for Dockerfile Development

- **Complete Automation:** No manual steps after launch
- **Robust Error Handling:** Handle all edge cases, log every operation
- **Service Management:** Complete supervisor setup, correct startup order, health checks
- **Environment Consistency:** Pin dependency versions, verify tools
- **Security:** Sensible defaults, firewalls, secure credentials

---

## Additional Resources

- [Docker documentation](https://docs.docker.com/)
- [Vast.ai documentation](https://vast.ai/docs/)
- [Supervisor documentation](http://supervisord.org/)
- [JupyterLab documentation](https://jupyterlab.readthedocs.io/)

---

*Document created: April 29, 2025*  
*Last updated: April 29, 2025*