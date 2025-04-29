FROM nvidia/cuda:12.4.1-cudnn-devel-ubuntu22.04

# Reset any entrypoint from the parent image
ENTRYPOINT []

# Environment setup
ENV REFRESHED_AT=2024-08-12 \
    DEBIAN_FRONTEND=noninteractive \
    DISPLAY=:1 \
    VNC_PORT=5901 \
    NO_VNC_PORT=6901 \
    VNC_COL_DEPTH=24 \
    VNC_RESOLUTION=1280x1024 \
    VNC_PW=vncpasswd123 \
    VNC_VIEW_ONLY=false \
    HOME=/workspace \
    TERM=xterm \
    STARTUPDIR=/dockerstartup \
    NO_VNC_HOME=/usr/share/novnc \
    TZ=Asia/Seoul \
    PATH=/opt/conda/bin:$PATH

# Create necessary directories for logs and workspace
RUN mkdir -p /logs /Logs /workspace && \
    chmod 777 /logs /Logs /workspace
WORKDIR /workspace

# Install base system packages
RUN apt-get update && apt-get install -y \
    wget \
    git \
    build-essential \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    unzip \
    ffmpeg \
    jq \
    tzdata \
    tigervnc-standalone-server \
    tigervnc-common \
    websockify \
    icewm \
    xauth \
    x11-xserver-utils \
    x11-utils \
    xterm \
    supervisor \
    openssh-server \
    net-tools \
    curl && \
    ln -fs /usr/share/zoneinfo/$TZ /etc/localtime && \
    dpkg-reconfigure -f noninteractive tzdata && \
    rm -rf /var/lib/apt/lists/*

# Install Miniconda for Python environment
RUN wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O miniconda.sh && \
    bash miniconda.sh -b -p /opt/conda && \
    rm miniconda.sh && \
    echo "source activate base" >> ~/.bashrc

# Create conda environment for VisoMaster
RUN conda create -n visomaster python=3.10.13 && conda clean --all -y
ENV PATH=/opt/conda/envs/visomaster/bin:$PATH
RUN echo "source activate visomaster" >> ~/.bashrc

# Install CUDA and cuDNN in conda environment
RUN conda install -c nvidia/label/cuda-12.4.1 cuda-runtime && \
    conda install -c conda-forge cudnn

# Set up VNC basics
RUN mkdir -p /root/.vnc && \
    echo "vncpasswd123" | vncpasswd -f > /root/.vnc/passwd && \
    chmod 600 /root/.vnc/passwd && \
    touch /root/.Xauthority

# Install NoVNC for browser-based VNC access
RUN mkdir -p /usr/share/novnc && \
    cd /tmp && \
    wget -qO- https://github.com/novnc/noVNC/archive/v1.3.0.tar.gz | tar xz && \
    cp -rf /tmp/noVNC-1.3.0/* /usr/share/novnc/ && \
    rm -rf /tmp/noVNC-1.3.0 && \
    mkdir -p /usr/share/novnc/utils/websockify && \
    cd /usr/share/novnc/utils && \
    wget -qO- https://github.com/novnc/websockify/archive/v0.10.0.tar.gz | tar xz && \
    cp -rf websockify-0.10.0/* websockify/ && \
    rm -rf websockify-0.10.0 && \
    ln -sf /usr/share/novnc/utils/websockify/run /usr/share/novnc/utils/novnc_proxy && \
    chmod +x /usr/share/novnc/utils/novnc_proxy

# Install filebrowser for web-based file management
RUN cd /tmp && \
    curl -fsSL https://github.com/filebrowser/filebrowser/releases/download/v2.23.0/linux-amd64-filebrowser.tar.gz | tar -xz && \
    mv filebrowser /usr/local/bin/ && \
    chmod +x /usr/local/bin/filebrowser

# Install Firefox for web browsing within VNC
COPY src/common/install/firefox.sh /tmp/firefox.sh
RUN chmod +x /tmp/firefox.sh && /tmp/firefox.sh

# Copy VNC and window manager configuration files
COPY src/debian/icewm/wm_startup.sh /root/wm_startup.sh
COPY src/vnc_startup_jupyterlab_filebrowser.sh /src/vnc_startup_jupyterlab_filebrowser.sh
COPY src/vnc_startup_jupyterlab.sh /src/vnc_startup_jupyterlab.sh
RUN chmod +x /root/wm_startup.sh /src/vnc_startup_jupyterlab*.sh

# Configure supervisor for service management
RUN mkdir -p /etc/supervisor/conf.d
COPY src/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Configure SSH server
RUN mkdir -p /var/run/sshd && \
    echo 'root:password' | chpasswd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config

# Install Python packages and setup JupyterLab
RUN pip install jupyterlab tqdm PySide6 scikit-image

# Copy provisioning script for VisoMaster setup
COPY src/provisioning_script.sh /root/provisioning_script.sh
RUN chmod +x /root/provisioning_script.sh

# Create startup script with improved logging and error handling
RUN echo '#!/bin/bash\n\
# Setup logging to /logs/\n\
mkdir -p /logs\n\
STARTUP_LOG="/logs/startup.log"\n\
exec > >(tee -a "$STARTUP_LOG") 2> >(tee -a "$STARTUP_LOG" >&2)\n\
\n\
echo "--- Starting startup script $(date) ---"\n\
echo "--- Logging to $STARTUP_LOG ---"\n\
\n\
# Run provisioning script for VisoMaster setup\n\
echo "Starting provisioning script..."\n\
/bin/bash /root/provisioning_script.sh || echo "Warning: Provisioning script had errors"\n\
\n\
# Initialize X11 authentication\n\
touch /root/.Xauthority\n\
xauth generate :1 . trusted\n\
\n\
# Ensure required directories exist\n\
mkdir -p /logs /dockerstartup\n\
chmod 777 /logs\n\
\n\
# Setup VNC startup script\n\
if [ ! -f /dockerstartup/vnc_startup.sh ]; then\n\
    if [ -f /src/vnc_startup_jupyterlab_filebrowser.sh ]; then\n\
        echo "Using filebrowser VNC script..."\n\
        cp /src/vnc_startup_jupyterlab_filebrowser.sh /dockerstartup/vnc_startup.sh\n\
    elif [ -f /src/vnc_startup_jupyterlab.sh ]; then\n\
        echo "Using regular VNC script..."\n\
        cp /src/vnc_startup_jupyterlab.sh /dockerstartup/vnc_startup.sh\n\
    else\n\
        echo "ERROR: No VNC startup scripts found!"\n\
    fi\n\
    chmod +x /dockerstartup/vnc_startup.sh 2>/dev/null || true\n\
fi\n\
\n\
# Start supervisor to manage all services\n\
echo "Starting supervisor..."\n\
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf\n\
' > /root/startup.sh && chmod +x /root/startup.sh

# Clone VisoMaster (the provisioning script will handle dependencies and models)
WORKDIR /workspace

# Expose required ports
EXPOSE 5901 6901 22 8080 8585

# Set the final entrypoint command
CMD ["/bin/bash", "/root/startup.sh"]
