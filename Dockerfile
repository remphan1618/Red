FROM nvidia/cuda:11.8.0-base-ubuntu20.04

# Reset any entrypoint from the parent image to avoid "multiple entrypoints" warnings
ENTRYPOINT []

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Set VNC environment variables
ENV VNC_PW=vncpasswd123 \
    VNC_RESOLUTION=1280x1024 \
    VNC_COL_DEPTH=24 \
    VNC_PORT=5901 \
    NO_VNC_PORT=6901 \
    DISPLAY=:1 \
    NO_VNC_HOME=/usr/share/novnc

# Create logs directory early with correct permissions
RUN mkdir -p /logs && chmod 777 /logs

# Install required packages and add deadsnakes PPA for Python 3.10
RUN apt-get update && apt-get install -y \
    software-properties-common \
    && add-apt-repository ppa:deadsnakes/ppa \
    && apt-get update \
    && apt-get install -y \
    python3.10 \
    python3.10-venv \
    python3.10-distutils \
    python3-pip \
    xauth \
    tigervnc-standalone-server \
    tigervnc-common \
    websockify \
    icewm \
    xterm \
    git \
    wget \
    curl \
    supervisor \
    openssh-server \
    net-tools \
    && rm -rf /var/lib/apt/lists/*

# Install pip for Python 3.10
RUN curl -sS https://bootstrap.pypa.io/get-pip.py | python3.10

# Install python websockify properly
RUN python3.10 -m pip install websockify

# Install tqdm for model downloading
RUN python3.10 -m pip install tqdm

# Create necessary directories and files for VNC
RUN mkdir -p /root/.vnc

# Create a default VNC password
RUN mkdir -p /root/.vnc && echo "vncpasswd123" | vncpasswd -f > /root/.vnc/passwd && \
    chmod 600 /root/.vnc/passwd

# Create .Xauthority file
RUN touch /root/.Xauthority

# Set up Python virtual environment with Python 3.10
RUN python3.10 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Set Python 3.10 as the default python3
RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.10 1

# Install NoVNC
RUN mkdir -p ${NO_VNC_HOME} && \
    cd /tmp && \
    wget -qO- https://github.com/novnc/noVNC/archive/v1.3.0.tar.gz | tar xz && \
    cp -rf /tmp/noVNC-1.3.0/* ${NO_VNC_HOME}/ && \
    rm -rf /tmp/noVNC-1.3.0 && \
    cd ${NO_VNC_HOME}/utils && \
    wget -qO- https://github.com/novnc/websockify/archive/v0.10.0.tar.gz | tar xz && \
    mv websockify-0.10.0 websockify && \
    ln -s ${NO_VNC_HOME}/utils/websockify/run ${NO_VNC_HOME}/utils/novnc_proxy && \
    chmod +x ${NO_VNC_HOME}/utils/novnc_proxy

# Install filebrowser for VNC filebrowser script
RUN cd /tmp && \
    curl -fsSL https://github.com/filebrowser/filebrowser/releases/download/v2.23.0/linux-amd64-filebrowser.tar.gz | tar -xz && \
    mv filebrowser /usr/local/bin/ && \
    chmod +x /usr/local/bin/filebrowser && \
    mkdir -p /workspace && \
    chmod 777 /workspace

# Create directories for logs and supervisor configuration
RUN mkdir -p /etc/supervisor/conf.d

# Copy supervisor configuration
COPY src/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Copy VNC startup scripts
COPY src/vnc_startup_jupyterlab_filebrowser.sh /src/vnc_startup_jupyterlab_filebrowser.sh
COPY src/vnc_startup_jupyterlab.sh /src/vnc_startup_jupyterlab.sh
COPY src/debian/icewm/wm_startup.sh /root/wm_startup.sh
RUN chmod +x /src/vnc_startup_jupyterlab*.sh /root/wm_startup.sh

# Configure SSH for supervisor
RUN mkdir -p /var/run/sshd
RUN echo 'root:password' | chpasswd
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config

# Copy provisioning script - using the correct path from src directory
COPY src/provisioning_script.sh /root/provisioning_script.sh
RUN chmod +x /root/provisioning_script.sh

# Create startup script with supervisor support and direct logs to /logs/
RUN echo '#!/bin/bash\n\
# Setup logging to /logs/\n\
mkdir -p /logs\n\
STARTUP_LOG="/logs/startup.log"\n\
exec > >(tee -a "$STARTUP_LOG") 2> >(tee -a "$STARTUP_LOG" >&2)\n\
\n\
echo "--- Starting startup script $(date) ---"\n\
echo "--- Logging to $STARTUP_LOG ---"\n\
\n\
# Run provisioning script\n\
echo "Starting provisioning script..."\n\
/bin/bash /root/provisioning_script.sh || echo "Warning: Provisioning script had errors"\n\
\n\
# Initialize Xauthority\n\
touch /root/.Xauthority\n\
xauth generate :1 . trusted\n\
\n\
# Create required directories\n\
mkdir -p /logs /dockerstartup\n\
chmod 777 /logs\n\
\n\
# Copy VNC startup script with filebrowser version prioritized\n\
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
# Start supervisor which will manage all services\n\
echo "Starting supervisor..."\n\
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf\n\
' > /root/startup.sh && chmod +x /root/startup.sh

# Set the startup command
CMD ["/bin/bash", "/root/startup.sh"]
