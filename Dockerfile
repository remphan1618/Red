# Use the smaller runtime base image
FROM nvidia/cuda:12.4.1-cudnn-runtime-ubuntu22.04

# Set a refresh date (adjust as needed)
ENV REFRESHED_AT 2024-08-12

# Labels describing the image
LABEL io.k8s.description="Headless VNC Container with IceWM, Jupyter, SSH, VisoMaster for Vast.ai (Runtime Base)" \
      io.k8s.display-name="VNC IceWM VisoMaster Runtime" \
      io.openshift.expose-services="6901:http,5901:xvnc,8888:http,22:ssh" \
      io.openshift.tags="vnc, icewm, jupyter, ssh, vastai, visomaster, runtime" \
      io.openshift.non-scalable=true

### Connection ports Environment Variables
ENV DISPLAY=:1 \
    VNC_PORT=5901 \
    NO_VNC_PORT=6901 \
    JUPYTER_PORT=8888 \
    SSH_PORT=22
# Expose ports
EXPOSE $VNC_PORT $NO_VNC_PORT $JUPYTER_PORT $SSH_PORT

### Environment config Variables
ENV HOME=/root \
    TERM=xterm \
    STARTUPDIR=/dockerstartup \
    INST_SCRIPTS=/workspace/install \
    NO_VNC_HOME=/workspace/noVNC \
    DEBIAN_FRONTEND=noninteractive \
    VNC_COL_DEPTH=24 \
    VNC_PW=vncpassword \
    VNC_VIEW_ONLY=false \
    TZ=Asia/Seoul \
    LANG='en_US.UTF-8' \
    LANGUAGE='en_US:en' \
    LC_ALL='en_US.UTF-8'
# Set working directory
WORKDIR $HOME

### Install dependencies: Base Utils, System Python, SSH Server, Supervisor
# Combine update, install, setup, and cleanup in one RUN command to reduce layers
# Note: build-essential might not be strictly needed with runtime image, but keep for now in case pip needs it
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    git \
    build-essential \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    unzip \
    ffmpeg \
    tzdata \
    python3 \
    python3-pip \
    python3-venv \
    openssh-server \
    supervisor \
    # Set timezone
    && ln -fs /usr/share/zoneinfo/$TZ /etc/localtime && \
    dpkg-reconfigure -f noninteractive tzdata && \
    # *** Aggressive Cleanup within the same layer ***
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    # Ensure pip is up to date for the system Python
    python3 -m pip install --no-cache-dir --upgrade pip && \
    # *** Clean pip cache ***
    rm -rf /root/.cache/pip

### Configure SSH Server (Allow Root Login via key, disable password auth)
RUN mkdir -p /var/run/sshd /root/.ssh && \
    chmod 700 /root/.ssh && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config

### Configure Supervisor
RUN mkdir -p /etc/supervisor/conf.d
COPY ./src/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

### Add install scripts from src/common and src/debian into the image
RUN mkdir -p $INST_SCRIPTS
ADD ./src/common/install/ $INST_SCRIPTS/
ADD ./src/debian/install/ $INST_SCRIPTS/
# Make scripts executable
RUN chmod 765 $INST_SCRIPTS/*

### Run Installers from the INST_SCRIPTS directory
RUN $INST_SCRIPTS/tools.sh
RUN $INST_SCRIPTS/install_custom_fonts.sh
# --- Keep TigerVNC (VNC Server) ---
RUN $INST_SCRIPTS/tigervnc.sh
# --- Keep noVNC (Web VNC Client) ---
RUN $INST_SCRIPTS/no_vnc_1.5.0.sh
# --- REMOVED Firefox installation ---
# RUN $INST_SCRIPTS/firefox.sh
# --- Install IceWM ---
RUN $INST_SCRIPTS/icewm_ui.sh
RUN $INST_SCRIPTS/libnss_wrapper.sh
# Add a cleanup step after running external installers
RUN apt-get clean && rm -rf /var/lib/apt/lists/* || echo "No apt lists to clean"

### Add IceWM runtime config (e.g., wm_startup.sh)
ADD ./src/debian/icewm/ $HOME/

### Configure startup directory and permissions
RUN mkdir -p $STARTUPDIR
ADD ./src/common/scripts $STARTUPDIR
RUN $INST_SCRIPTS/set_user_permission.sh $STARTUPDIR $HOME

### Install VisoMaster (remphan1618 fork)
RUN git clone https://github.com/remphan1618/VisoMaster.git
WORKDIR $HOME/VisoMaster

# Install Python dependencies using requirements.txt (using system pip)
RUN pip install --no-cache-dir -r requirements.txt && \
    # *** Clean pip cache ***
    rm -rf /root/.cache/pip
# Keep scikit-image install (using system pip)
RUN pip install --no-cache-dir scikit-image && \
    # *** Clean pip cache ***
    rm -rf /root/.cache/pip

# --- Model download steps REMOVED ---

### Install jupyterlab using system pip
RUN pip install --no-cache-dir jupyterlab && \
    # *** Clean pip cache ***
    rm -rf /root/.cache/pip
# Port 8888 already exposed

### Install filebrowser
RUN wget -O - https://raw.githubusercontent.com/filebrowser/get/master/get.sh | bash
# Expose filebrowser port if you intend to run it manually or via supervisor
EXPOSE 8585

### Install extra libraries (GUI/Qt/File Manager)
# Combine update, install, and cleanup in one RUN command
RUN apt-get update && apt-get install -y --no-install-recommends \
    libegl1 libgl1-mesa-glx libglib2.0-0 \
    libxcb-cursor0 libxcb-xinerama0 libxkbcommon-x11-0 \
    libqt5gui5 libqt5core5a libqt5widgets5 libqt5x11extras5 \
    pcmanfm \
    # *** Aggressive Cleanup within the same layer ***
    && apt-get clean && rm -rf /var/lib/apt/lists/*

### Copy main startup script and set permissions
COPY ./src/vnc_startup_jupyterlab_filebrowser.sh /dockerstartup/vnc_startup.sh
RUN chmod 765 /dockerstartup/vnc_startup.sh

# Set default VNC resolution
ENV VNC_RESOLUTION=1280x1024

# Set the entrypoint to run Supervisor, which manages other processes
ENTRYPOINT ["/usr/bin/supervisord", "-c", "/etc/supervisor/supervisord.conf"]
# CMD is not needed when using supervisor as entrypoint
