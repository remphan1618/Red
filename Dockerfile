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
    supervisor \
    xauth \
    mcookie \
    openbox \
    tigervnc-standalone-server \
    # X11/VNC required packages
    xterm \
    xdg-utils \
    # Add GUI dependencies that were missing (libEGL.so.1 and related dependencies)
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

# Set up SSH properly by creating essential directories and fixing configuration
RUN mkdir -p /var/run/sshd \
    && chmod 0755 /var/run/sshd \
    && ssh-keygen -A \
    # Fix SSH configuration to avoid exit code 255
    && sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config \
    && sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config \
    && sed -i 's/#UsePAM yes/UsePAM no/' /etc/ssh/sshd_config \
    && echo "PidFile /var/run/sshd/sshd.pid" >> /etc/ssh/sshd_config 

# Create workspace directory and initial wm_startup.sh
RUN mkdir -p /workspace

# Set up TigerVNC configuration
RUN printf '\n# docker-headless-vnc-container:\n$localhost = "no";\n1;\n' >>/etc/tigervnc/vncserver-config-defaults

# Set up Python (without virtual environment) and necessary packages
RUN pip3 install --no-cache-dir --upgrade pip setuptools wheel && \
    pip3 install PySide6 jupyter jupyterlab numpy tqdm

# Create needed directories
RUN mkdir -p /logs /dockerstartup /VisoMaster/models /VisoMaster/model_assets

# Set up X11 authentication
RUN touch /root/.Xauthority && \
    chmod 600 /root/.Xauthority && \
    echo 'touch ~/.Xauthority' >> /root/.bashrc && \
    echo 'xauth generate :1 . trusted' >> /root/.bashrc

# Copy configuration files
COPY src/debian/icewm/wm_startup.sh /workspace/wm_startup.sh
COPY src/vnc_startup_jupyterlab_filebrowser.sh /dockerstartup/vnc_startup.sh
COPY src/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Make scripts executable
RUN chmod +x /workspace/wm_startup.sh /dockerstartup/vnc_startup.sh

# Copy and activate provisioning script
COPY src/provisioning_script.sh /tmp/provisioning_script.sh
RUN chmod +x /tmp/provisioning_script.sh

# Copy requirements files
COPY requirements.txt /VisoMaster/requirements.txt
COPY requirements_124.txt /VisoMaster/requirements_cu124.txt

# Expose ports
EXPOSE 22 5901 6901 8080 8585 8888

# Set entrypoint to run provisioning script then start supervisord
ENTRYPOINT ["/bin/bash", "-c", "/tmp/provisioning_script.sh && exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf"]
