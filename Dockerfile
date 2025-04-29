FROM nvidia/cuda:11.8.0-base-ubuntu20.04

# Reset any entrypoint from the parent image to avoid "multiple entrypoints" warnings
ENTRYPOINT []

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

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

# Copy provisioning script - using the correct path from src directory
COPY src/provisioning_script.sh /root/provisioning_script.sh
RUN chmod +x /root/provisioning_script.sh

# Create startup script
RUN echo '#!/bin/bash\n\
# Run provisioning script\n\
echo "Starting provisioning script..."\n\
/bin/bash /root/provisioning_script.sh || echo "Warning: Provisioning script had errors"\n\
\n\
# Initialize Xauthority\n\
touch /root/.Xauthority\n\
xauth generate :1 . trusted\n\
\n\
# Start VNC server\n\
echo "Starting VNC server..."\n\
vncserver :1 -depth 24 -geometry 1280x800 -localhost no\n\
\n\
# Start WebSockets proxy with clear argument separation\n\
echo "Starting WebSockets proxy..."\n\
websockify 0.0.0.0:6080 localhost:5901 &\n\
\n\
# Keep container running\n\
echo "Startup complete - container running"\n\
tail -f /dev/null\n\
' > /root/startup.sh && chmod +x /root/startup.sh

# Set the startup command - use CMD instead of ENTRYPOINT for flexibility
CMD ["/bin/bash", "/root/startup.sh"]
