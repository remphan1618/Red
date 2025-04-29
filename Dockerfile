FROM nvidia/cuda:12.4.0-devel-ubuntu22.04

# Set up build logging
RUN mkdir -p /logs/build
ENV BUILD_LOG="/logs/build/dockerfile_build.log"
ENV ERROR_LOG="/logs/build/dockerfile_errors.log"

# Create build error handler function
RUN echo '#!/bin/bash\n\
log_error() {\n\
  local component="$1"\n\
  local error_msg="$2"\n\
  echo "[$(date "+%Y-%m-%d %H:%M:%S")] ERROR in $component: $error_msg" | tee -a $ERROR_LOG\n\
  echo "$error_msg" > "/logs/build/${component}_FAILED.status"\n\
  echo "ERROR: $component failed, but continuing build..."\n\
  return 0\n\
}\n\
log_step() {\n\
  local component="$1"\n\
  echo "[$(date "+%Y-%m-%d %H:%M:%S")] STEP: Starting $component" | tee -a $BUILD_LOG\n\
  echo "STARTED: $(date)" > "/logs/build/${component}_STATUS.txt"\n\
}\n\
complete_step() {\n\
  local component="$1"\n\
  echo "[$(date "+%Y-%m-%d %H:%M:%S")] STEP: $component completed" | tee -a $BUILD_LOG\n\
  echo "COMPLETED: $(date)" >> "/logs/build/${component}_STATUS.txt"\n\
}\n\
' > /usr/local/bin/build_helpers.sh && chmod +x /usr/local/bin/build_helpers.sh

# Install required packages
RUN source /usr/local/bin/build_helpers.sh && \
    log_step "package_installation" && \
    (apt-get update && apt-get install -y --no-install-recommends \
    openssh-server \
    python3-pip \
    python3-dev \
    wget \
    curl \
    rsync \
    tmux \
    git \
    xauth \
    x11-apps \
    openbox \
    tigervnc-standalone-server \
    xterm \
    xdg-utils \
    # GUI dependencies
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
    libxcb-shape0 \
    libx11-xcb1 \
    libxcursor1 \
    libxi6 \
    libxtst6 \
    mesa-utils \
    xvfb \
    icewm \
    icewm-common \
    xinit \
    menu \
    || log_error "package_installation" "Failed to install some packages") && \
    rm -rf /var/lib/apt/lists/* && \
    complete_step "package_installation"

# Set up SSH
RUN source /usr/local/bin/build_helpers.sh && \
    log_step "ssh_setup" && \
    (mkdir -p /var/run/sshd \
    && chmod 0755 /var/run/sshd \
    && ssh-keygen -A \
    && sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config \
    && sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config \
    && sed -i 's/#UsePAM yes/UsePAM no/' /etc/ssh/sshd_config \
    && echo "PidFile /var/run/sshd/sshd.pid" >> /etc/ssh/sshd_config \
    || log_error "ssh_setup" "Failed to configure SSH") && \
    complete_step "ssh_setup"

# Create required directories
RUN source /usr/local/bin/build_helpers.sh && \
    log_step "directory_setup" && \
    mkdir -p /workspace /logs /dockerstartup /VisoMaster/{models,Images,Videos,Output,model_assets} && \
    complete_step "directory_setup"

# Set up TigerVNC configuration
RUN source /usr/local/bin/build_helpers.sh && \
    log_step "vnc_config" && \
    (printf '\n# docker-headless-vnc-container:\n$localhost = "no";\n1;\n' >>/etc/tigervnc/vncserver-config-defaults \
    || log_error "vnc_config" "Failed to configure TigerVNC") && \
    complete_step "vnc_config"

# Set up Python and necessary packages (base packages only, rest will be installed by provisioning script)
RUN source /usr/local/bin/build_helpers.sh && \
    log_step "python_setup" && \
    (pip3 install --no-cache-dir --upgrade pip setuptools wheel \
    || log_error "python_setup" "Failed to upgrade pip packages") && \
    complete_step "python_setup"

# Copy window manager script
COPY src/debian/icewm/wm_startup.sh /workspace/wm_startup.sh
RUN source /usr/local/bin/build_helpers.sh && \
    log_step "wm_script_setup" && \
    (chmod +x /workspace/wm_startup.sh \
    || log_error "wm_script_setup" "Failed to set permissions on window manager script") && \
    complete_step "wm_script_setup"

# Copy VNC startup script
COPY src/vnc_startup_jupyterlab_filebrowser.sh /dockerstartup/vnc_startup.sh
RUN source /usr/local/bin/build_helpers.sh && \
    log_step "vnc_script_setup" && \
    (chmod +x /dockerstartup/vnc_startup.sh \
    || log_error "vnc_script_setup" "Failed to set permissions on VNC script") && \
    complete_step "vnc_script_setup"

# Copy provisioning script which now also handles service management
COPY vast_ai_provisioning_script.sh /dockerstartup/vast_ai_provisioning_script.sh
RUN source /usr/local/bin/build_helpers.sh && \
    log_step "provisioning_script_setup" && \
    (chmod +x /dockerstartup/vast_ai_provisioning_script.sh \
    || log_error "provisioning_script_setup" "Failed to set permissions on provisioning script") && \
    complete_step "provisioning_script_setup"

# Copy requirements files 
COPY requirements.txt /VisoMaster/requirements.txt
COPY requirements_124.txt /VisoMaster/requirements_cu124.txt

# Generate build summary
RUN source /usr/local/bin/build_helpers.sh && \
    echo "-------- Dockerfile Build Summary --------" > /logs/build/build_summary.txt && \
    echo "Completed at: $(date)" >> /logs/build/build_summary.txt && \
    echo "" >> /logs/build/build_summary.txt && \
    error_count=$(find "/logs/build/" -name "*_FAILED.status" | wc -l) && \
    if [ "$error_count" -gt 0 ]; then \
      echo "⚠️ Build completed with $error_count errors:" >> /logs/build/build_summary.txt && \
      find "/logs/build/" -name "*_FAILED.status" | while read status_file; do \
        component=$(basename "$status_file" | sed 's/_FAILED.status//') && \
        echo "  - $component: $(cat "$status_file" | head -1)" >> /logs/build/build_summary.txt; \
      done; \
    else \
      echo "✅ Build completed successfully with no errors" >> /logs/build/build_summary.txt; \
    fi && \
    echo "" >> /logs/build/build_summary.txt && \
    echo "Log file: $BUILD_LOG" >> /logs/build/build_summary.txt && \
    echo "Error log: $ERROR_LOG" >> /logs/build/build_summary.txt && \
    echo "------------------------------------------" >> /logs/build/build_summary.txt && \
    cat /logs/build/build_summary.txt

# Run the services part of the script at container startup
CMD ["/bin/bash", "/dockerstartup/vast_ai_provisioning_script.sh", "--services-only"]

# Expose ports
EXPOSE 22 5901 6901 8080 8585 8888
