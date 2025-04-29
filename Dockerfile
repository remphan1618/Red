FROM nvidia/cuda:11.8.0-base-ubuntu20.04

# Reset any entrypoint from the parent image to avoid "multiple entrypoints" warnings
ENTRYPOINT []

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install required packages
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    xauth \
    tigervnc-standalone-server \
    tigervnc-common \
    websockify \
    git \
    python3-venv \
    wget \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install python websockify properly
RUN pip3 install websockify

# Create necessary directories and files for VNC
RUN mkdir -p /root/.vnc

# Create a default VNC password
RUN mkdir -p /root/.vnc && echo "vncpasswd123" | vncpasswd -f > /root/.vnc/passwd && \
    chmod 600 /root/.vnc/passwd

# Create .Xauthority file
RUN touch /root/.Xauthority

# Set up Python virtual environment
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Copy provisioning script
COPY provisioning_script.sh /root/provisioning_script.sh
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
