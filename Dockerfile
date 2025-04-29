FROM nvidia/cuda:12.4.0-devel-ubuntu22.04

# Install required packages
RUN apt-get update && apt-get install -y --no-install-recommends \
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
    && rm -rf /var/lib/apt/lists/*

# Set up SSH
RUN mkdir -p /var/run/sshd \
    && chmod 0755 /var/run/sshd \
    && ssh-keygen -A \
    && sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config \
    && sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config \
    && sed -i 's/#UsePAM yes/UsePAM no/' /etc/ssh/sshd_config \
    && echo "PidFile /var/run/sshd/sshd.pid" >> /etc/ssh/sshd_config 

# Create required directories
RUN mkdir -p /workspace /logs /dockerstartup /VisoMaster/{models,Images,Videos,Output,model_assets}

# Set up TigerVNC configuration
RUN printf '\n# docker-headless-vnc-container:\n$localhost = "no";\n1;\n' >>/etc/tigervnc/vncserver-config-defaults

# Set up Python and necessary packages (base packages only, rest will be installed by provisioning script)
RUN pip3 install --no-cache-dir --upgrade pip setuptools wheel

# Copy window manager script
COPY src/debian/icewm/wm_startup.sh /workspace/wm_startup.sh
RUN chmod +x /workspace/wm_startup.sh

# Copy VNC startup script
COPY src/vnc_startup_jupyterlab_filebrowser.sh /dockerstartup/vnc_startup.sh
RUN chmod +x /dockerstartup/vnc_startup.sh

# Copy provisioning script which now also handles service management
COPY vast_ai_provisioning_script.sh /dockerstartup/vast_ai_provisioning_script.sh
RUN chmod +x /dockerstartup/vast_ai_provisioning_script.sh

# Copy requirements files 
COPY requirements.txt /VisoMaster/requirements.txt
COPY requirements_124.txt /VisoMaster/requirements_cu124.txt

# Run the services part of the script at container startup
CMD ["/bin/bash", "/dockerstartup/vast_ai_provisioning_script.sh", "--services-only"]

# Expose ports
EXPOSE 22 5901 6901 8080 8585 8888
