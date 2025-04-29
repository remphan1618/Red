FROM nvidia/cuda:11.8.0-base-ubuntu20.04

# Reset any entrypoint from the parent image to avoid "multiple entrypoints" warnings
ENTRYPOINT []

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

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
    git \
    wget \
    curl \
    supervisor \
    openssh-server \
    && rm -rf /var/lib/apt/lists/*

# Install pip for Python 3.10
RUN curl -sS https://bootstrap.pypa.io/get-pip.py | python3.10

# Install python websockify properly
RUN python3.10 -m pip install websockify

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

# Create directories for logs and supervisor configuration
RUN mkdir -p /etc/supervisor/conf.d

# Copy supervisor configuration
COPY src/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

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
# Copy VNC startup script if it doesn't exist\n\
if [ ! -f /dockerstartup/vnc_startup.sh ]; then\n\
    cp /src/vnc_startup_jupyterlab.sh /dockerstartup/vnc_startup.sh\n\
    chmod +x /dockerstartup/vnc_startup.sh\n\
fi\n\
\n\
# Start supervisor which will manage all services\n\
echo "Starting supervisor..."\n\
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf\n\
' > /root/startup.sh && chmod +x /root/startup.sh

# Set the startup command
CMD ["/bin/bash", "/root/startup.sh"]
