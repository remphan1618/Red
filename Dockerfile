FROM nvidia/cuda:12.4.0-devel-ubuntu22.04

# Add container labels for better identification and documentation
LABEL io.k8s.description="Headless VNC Container with Xfce window manager, firefox and chromium" \
      io.k8s.display-name="Headless VNC Container based on Ubuntu" \
      io.openshift.expose-services="6901:http,5901:xvnc" \
      io.openshift.tags="vnc, ubuntu, xfce" \
      io.openshift.non-scalable=true

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

### Connection ports for controlling the UI:
### VNC port:5901
### noVNC webport, connect via http://IP:6901/?password=vncpassword
ENV DISPLAY=:1 \
    VNC_PORT=5901 \
    NO_VNC_PORT=6901
EXPOSE $VNC_PORT $NO_VNC_PORT

### Environment config
ENV HOME=/workspace \
    TERM=xterm \
    STARTUPDIR=/dockerstartup \
    INST_SCRIPTS=/workspace/install \
    NO_VNC_HOME=/workspace/noVNC \
    DEBIAN_FRONTEND=noninteractive \
    VNC_COL_DEPTH=24 \
    VNC_PW=vncpassword \
    VNC_VIEW_ONLY=false \
    TZ=Asia/Seoul
WORKDIR $HOME

# Install required packages
RUN . /usr/local/bin/build_helpers.sh && \
    log_step "package_installation" && \
    (apt-get update && apt-get install -y --no-install-recommends \
    openssh-server \
    python3-pip \
    python3-dev \
    wget \
    curl \
    git \
    build-essential \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    rsync \
    tmux \
    unzip \
    ffmpeg \
    jq \
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
    tzdata \
    || log_error "package_installation" "Failed to install some packages") && \
    ln -fs /usr/share/zoneinfo/$TZ /etc/localtime && \
    dpkg-reconfigure -f noninteractive tzdata && \
    rm -rf /var/lib/apt/lists/* && \
    complete_step "package_installation"

# Set locale
ENV LANG='en_US.UTF-8' LANGUAGE='en_US:en' LC_ALL='en_US.UTF-8'

# Set up SSH
RUN . /usr/local/bin/build_helpers.sh && \
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
RUN . /usr/local/bin/build_helpers.sh && \
    log_step "directory_setup" && \
    mkdir -p /workspace /logs /dockerstartup /VisoMaster/{models,Images,Videos,Output,model_assets} && \
    complete_step "directory_setup"

# Set up TigerVNC configuration
RUN . /usr/local/bin/build_helpers.sh && \
    log_step "vnc_config" && \
    (printf '\n# docker-headless-vnc-container:\n$localhost = "no";\n1;\n' >>/etc/tigervnc/vncserver-config-defaults \
    || log_error "vnc_config" "Failed to configure TigerVNC") && \
    complete_step "vnc_config"

# Set up Python and necessary packages
RUN . /usr/local/bin/build_helpers.sh && \
    log_step "python_setup" && \
    (pip3 install --no-cache-dir --upgrade pip setuptools wheel \
    || log_error "python_setup" "Failed to upgrade pip packages") && \
    complete_step "python_setup"

### Add all install scripts before executing them
COPY ./src/common/install/ /workspace/install/
COPY ./src/debian/install/ /workspace/install/
RUN chmod 765 /workspace/install/*

### Install common tools first
RUN . /usr/local/bin/build_helpers.sh && \
    log_step "tools_installation" && \
    (bash /workspace/install/tools.sh \
    || log_error "tools_installation" "Failed to install common tools") && \
    complete_step "tools_installation"

### Install components by executing scripts
RUN . /usr/local/bin/build_helpers.sh && \
    log_step "components_installation" && \
    (bash /workspace/install/install_custom_fonts.sh && \
     bash /workspace/install/tigervnc.sh && \
     bash /workspace/install/no_vnc_1.5.0.sh && \
     bash /workspace/install/firefox.sh && \
     bash /workspace/install/icewm_ui.sh && \
     bash /workspace/install/libnss_wrapper.sh \
     || log_error "components_installation" "Failed to install some components") && \
    complete_step "components_installation"

### Copy window manager configuration files
COPY ./src/debian/icewm/ /workspace/

### Configure startup components
ADD ./src/common/scripts $STARTUPDIR
RUN $INST_SCRIPTS/debian/set_user_permission.sh $STARTUPDIR $HOME

# Copy window manager script
COPY src/debian/icewm/wm_startup.sh /workspace/wm_startup.sh
RUN . /usr/local/bin/build_helpers.sh && \
    log_step "wm_script_setup" && \
    (chmod +x /workspace/wm_startup.sh \
    || log_error "wm_script_setup" "Failed to set permissions on window manager script") && \
    complete_step "wm_script_setup"

# Copy VNC startup script
COPY src/vnc_startup_jupyterlab_filebrowser.sh /dockerstartup/vnc_startup.sh
RUN . /usr/local/bin/build_helpers.sh && \
    log_step "vnc_script_setup" && \
    (chmod +x /dockerstartup/vnc_startup.sh \
    || log_error "vnc_script_setup" "Failed to set permissions on VNC script") && \
    complete_step "vnc_script_setup"

# Copy provisioning script which now also handles service management
COPY vast_ai_provisioning_script.sh /dockerstartup/vast_ai_provisioning_script.sh
RUN . /usr/local/bin/build_helpers.sh && \
    log_step "provisioning_script_setup" && \
    (chmod +x /dockerstartup/vast_ai_provisioning_script.sh \
    || log_error "provisioning_script_setup" "Failed to set permissions on provisioning script") && \
    complete_step "provisioning_script_setup"

# Copy requirements files 
COPY requirements.txt /VisoMaster/requirements.txt
COPY requirements_124.txt /VisoMaster/requirements_cu124.txt

# Install requirements immediately after copying them
RUN . /usr/local/bin/build_helpers.sh && \
    log_step "requirements_installation" && \
    (pip3 install -r /VisoMaster/requirements.txt && \
     pip3 install -r /VisoMaster/requirements_cu124.txt && \
     pip3 install opencv-python-headless pyqt-toast-notification==1.3.2 \
    || log_error "requirements_installation" "Failed to install requirements") && \
    complete_step "requirements_installation"

### Clone VisoMaster repository
WORKDIR /workspace
RUN . /usr/local/bin/build_helpers.sh && \
    log_step "repo_clone" && \
    (git clone https://github.com/remphan1618/VisoMaster.git \
    || log_error "repo_clone" "Failed to clone repository") && \
    complete_step "repo_clone"

### Install scikit-image
RUN . /usr/local/bin/build_helpers.sh && \
    log_step "scikit_installation" && \
    (pip install scikit-image \
    || log_error "scikit_installation" "Failed to install scikit-image") && \
    complete_step "scikit_installation"

### Download models (as requested, placed at the end)
WORKDIR /workspace/VisoMaster/model_assets
RUN . /usr/local/bin/build_helpers.sh && \
    log_step "model_download" && \
    (python download_models.py \
    || log_error "model_download" "Failed to download models") && \
    complete_step "model_download"

# Generate build summary
RUN . /usr/local/bin/build_helpers.sh && \
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

### Set VNC resolution
ENV VNC_RESOLUTION=1280x1024

# Set ENTRYPOINT to use the provisioning script which will call the VNC startup
ENTRYPOINT ["/bin/bash", "/dockerstartup/vast_ai_provisioning_script.sh"]
CMD ["--wait"]

# Expose ports
EXPOSE 22 5901 6901 8080 8585 8888
