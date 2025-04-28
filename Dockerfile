FROM nvidia/cuda:11.8.0-base-ubuntu20.04

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

# Create startup script
RUN echo '#!/bin/bash\n\
# Initialize Xauthority\n\
touch /root/.Xauthority\n\
xauth generate :1 . trusted\n\
\n\
# Start VNC server\n\
vncserver :1 -depth 24 -geometry 1280x800 -localhost no\n\
\n\
# Start WebSockets proxy with clear argument separation\n\
websockify 0.0.0.0:6080 localhost:5901\n\
\n\
# Keep container running\n\
tail -f /dev/null\n\
' > /root/startup.sh && chmod +x /root/startup.sh

# Set the startup command
CMD ["/bin/bash", "/root/startup.sh"]
