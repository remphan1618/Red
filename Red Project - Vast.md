Red Project - Vast.ai Environment Documentation
Overview
The Red project provides a containerized machine learning environment designed for Vast.ai GPU instances. Its primary function is to set up and run VisoMaster, a specialized ML project, along with supporting tools like VNC for remote access, JupyterLab for interactive development, and SSH for secure connections.

System Architecture & Goals
Core Philosophy
The goal is to have the Dockerfile fully automate everything, with no supplemental installation steps required. The included diagnostic and informational notebooks are meant to be extracted to a folder by the Dockerfile and serve solely as troubleshooting tools, not as installation mechanisms.

Key Components
Docker Container

Based on NVIDIA CUDA-enabled Ubuntu image
Configured with Python environment and ML dependencies
Includes VNC server for graphical interface access
Automatically installs and configures all required software
Provisioning System

Dual Provisioning Scripts:
Root script (/vast_ai_provisioning_script.sh): Executed by vast.ai's provisioning mechanism
Source script (/src/provisioning_script.sh): Used within the Docker container
Both scripts should be fully automated with no manual intervention required
Service Management

Supervisor daemon manages:
SSH server
Jupyter notebook/lab
VNC server
WebSocket proxy for browser access
All service setup should be handled automatically by the Dockerfile and provisioning scripts
VisoMaster Application

ML application cloned from GitHub repository
Core functionality of the environment
Installed during provisioning process with built-in conflict resolution
Diagnostic Notebooks

Pre-installed by the Dockerfile
Provide monitoring and troubleshooting capabilities only
Do not perform installation or configuration tasks
Vast.ai Integration
The system integrates with vast.ai through three complementary mechanisms:

Docker Entrypoint/CMD

Defines the primary process when container starts
Sets up basic environment configuration
Should be comprehensive enough to handle all startup scenarios
Provisioning Script

Run once on first boot via PROVISIONING_SCRIPT environment variable
Handles one-time setup operations like:
Installing system dependencies
Setting up SSH
Configuring VNC environment
Cloning VisoMaster repository
Must be robust with proper error handling and idempotency
On-Start Script

Executed every time the instance starts
Handles runtime environment adjustments
Ensures services are properly started
Should verify that everything is running as expected
On-Start Script Content
```
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
Current Issues & Workarounds
Missing Log Files Issue
The logs aren't being created properly due to several likely reasons:

Supervisor Not Installed or Running:

The supervisor daemon is not being installed or started correctly in the Dockerfile
The Dockerfile should include explicit supervisor installation and configuration
Log Directory Permissions/Creation Issue:

The Dockerfile should create and set proper permissions on the /logs directory
This ensures logs can be written regardless of which script runs first
Script Execution Path:

The on-start script exits immediately after finding and running the first provisioning script
The Dockerfile should ensure all necessary setup steps are completed regardless of script order
Error Handling Limitations:

The Dockerfile should set up proper logging for all services and scripts
Log rotation and persistence should be configured automatically
Service Startup Order:

The Dockerfile should establish a clear service start sequence
Dependencies between services should be properly defined in supervisor configuration
Identified Issues
Supervisor Not Starting

Cause: Supervisor is not properly installed or configured in the Dockerfile
Impact: Services like SSH, Jupyter, and VNC don't start automatically
Solution: Update Dockerfile to properly install and configure supervisor
VisoMaster Repository Conflict

Cause: Provisioning script attempts to clone into existing directory
Impact: Script fails with "directory already exists" error
Solution: Update Dockerfile to include robust clone logic that handles existing directories
Python Version Mismatch

Cause: Using Python 3.8 instead of Python 3.10
Impact: JupyterLab dependency conflicts
Solution: Update Dockerfile to install Python 3.10 explicitly
Monitoring & Debugging
Logs are stored in the /logs directory

The find_provisioning_script.ipynb notebook provides tools to:

Check existing log files
Monitor service status
Start services manually
Diagnose repository issues
These notebooks should be:

Pre-installed by the Dockerfile
Located in a standard location
Ready for use without any additional setup
Setting Up New Instances
When creating a new vast.ai instance:

Choose the correct Docker image

The image should contain everything pre-configured
No additional installation steps should be needed
Set environment variables

PROVISIONING_SCRIPT: URL to your provisioning script (optional, as local scripts should work)
VNC_RESOLUTION: Set display resolution (optional)
VNC_PW: Set VNC password (optional)
Monitor startup

Check logs in /logs directory
Use the pre-installed diagnostic notebooks if needed
Best Practices for Dockerfile Development
Complete Automation

Dockerfile should handle all installation and configuration steps
No manual steps should be required after container launch
Robust Error Handling

Add checks and fallbacks in the Dockerfile and scripts
Handle cases where directories already exist
Log all operations for easier debugging
Service Management

Configure supervisor completely in the Dockerfile
Implement proper startup order in configuration
Include health check mechanisms
Environment Consistency

Use specific version numbers for dependencies
Verify tool compatibility before building
Test the Dockerfile thoroughly with different configurations
Security Configuration

Set secure defaults in the Dockerfile
Configure firewalls and access controls
Use secure credential management
Additional Resources
Docker documentation: https://docs.docker.com/
Vast.ai documentation: https://vast.ai/docs/
Supervisor documentation: http://supervisord.org/
JupyterLab documentation: https://jupyterlab.readthedocs.io/
Document created: April 29, 2025
Last updated: April 29, 2025