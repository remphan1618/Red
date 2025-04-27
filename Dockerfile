# Use the smaller runtime base image
FROM nvidia/cuda:12.4.1-cudnn-runtime-ubuntu22.04

# Set a refresh date (adjust as needed)
ENV REFRESHED_AT 2024-08-12

# == Environment Variables ==
# Define static ENV vars early for better layer caching
# *** Changed HOME to /workspace ***
ENV HOME=/workspace \
    TERM=xterm \
    STARTUPDIR=/dockerstartup \
    INST_SCRIPTS=/workspace/install \
    NO_VNC_HOME=/workspace/noVNC \
    VENV_PATH=/opt/venv \
    DEBIAN_FRONTEND=noninteractive \
    VNC_COL_DEPTH=24 \
    VNC_PW=vncpassword \
    VNC_VIEW_ONLY=false \
    TZ=Asia/Seoul \
    LANG='en_US.UTF-8' \
    LANGUAGE='en_US:en' \
    LC_ALL='en_US.UTF-8' \
    # Add VENV to PATH
    PATH="/opt/venv/bin:$PATH"

# Create and set working directory to /workspace
RUN mkdir -p /workspace && chown root:root /workspace
WORKDIR /workspace

# == Expose Ports ==
# Explicitly list ports instead of using ENV vars in EXPOSE
EXPOSE 5901 6901 8888 22 8585

# == Install System Dependencies ==
# Combine all apt-get operations into a single RUN layer
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget git build-essential software-properties-common apt-transport-https \
    ca-certificates unzip ffmpeg tzdata python3 python3-pip python3-venv \
    openssh-server supervisor libegl1 libgl1-mesa-glx libglib2.0-0 \
    libxcb-cursor0 libxcb-xinerama0 libxkbcommon-x11-0 libqt5gui5 \
    libqt5core5a libqt5widgets5 libqt5x11extras5 pcmanfm \
    && ln -fs /usr/share/zoneinfo/$TZ /etc/localtime && \
    dpkg-reconfigure -f noninteractive tzdata && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# == Configure SSH Server ==
# Create .ssh dir in /root with correct initial permissions for key injection
RUN mkdir -p /root/.ssh && \
    chmod 700 /root/.ssh && \
    # Configure sshd_config
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config && \
    # Ensure sshd directory exists
    mkdir -p /var/run/sshd

# == Configure Supervisor ==
RUN mkdir -p /etc/supervisor/conf.d
# Use lowercase 'src'
COPY ./src/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# == Add and Run Install Scripts ==
# Add scripts from both common and debian install directories
RUN mkdir -p $INST_SCRIPTS
# Use lowercase 'common'
ADD ./src/common/install/ $INST_SCRIPTS/
ADD ./src/debian/install/ $INST_SCRIPTS/
RUN chmod 765 $INST_SCRIPTS/*

# Run Installers (Ensure these scripts exist in EITHER src/common/install OR src/debian/install)
RUN $INST_SCRIPTS/tools.sh
RUN $INST_SCRIPTS/install_custom_fonts.sh
RUN $INST_SCRIPTS/tigervnc.sh
RUN $INST_SCRIPTS/no_vnc_1.5.0.sh
RUN $INST_SCRIPTS/icewm_ui.sh
RUN $INST_SCRIPTS/libnss_wrapper.sh
# RUN $INST_SCRIPTS/firefox.sh # Firefox removed

# Cleanup after running external installers
RUN apt-get clean && rm -rf /var/lib/apt/lists/* || echo "No apt lists to clean"

# == Add Runtime Configs and Scripts ==
# *** Changed target from $HOME to /workspace ***
ADD ./src/debian/icewm/ /workspace/ # IceWM runtime config
RUN mkdir -p $STARTUPDIR
# Add Common helper scripts
# Use lowercase 'common'
ADD ./src/common/scripts $STARTUPDIR
# Use lowercase 'src'
COPY ./src/vnc_startup_jupyterlab_filebrowser.sh /dockerstartup/vnc_startup.sh
# *** Changed target from /root to /workspace ***
COPY ./src/provisioning_script.sh /workspace/provisioning_script.sh
RUN chmod +x /workspace/provisioning_script.sh
RUN chmod 765 /dockerstartup/vnc_startup.sh

# == Setup Python Virtual Environment and Install Dependencies ==
RUN python3 -m venv $VENV_PATH
RUN . $VENV_PATH/bin/activate && \
    pip install --no-cache-dir --upgrade pip && \
    # Repo is cloned by provisioning_script.sh into /workspace
    # Install base requirements if any, plus scikit-image, jupyterlab, and tqdm
    pip install --no-cache-dir scikit-image jupyterlab tqdm && \
    rm -rf /root/.cache/pip # Pip cache is still under /root usually

# Set WORKDIR explicitly again just to be sure
WORKDIR /workspace

# == Install File Browser ==
RUN wget -O - https://raw.githubusercontent.com/filebrowser/get/master/get.sh | bash

# == Final Setup & Permission Fixes ==
# Run permission script if it exists and does other things
# *** Changed target from $HOME to /workspace ***
RUN if [ -f $INST_SCRIPTS/set_user_permission.sh ]; then $INST_SCRIPTS/set_user_permission.sh $STARTUPDIR /workspace; fi
# *** Fix /root/.ssh ownership/permissions for SSH keys ***
# *** Keep targeting /root/.ssh as that's where Vast.ai likely injects keys ***
RUN mkdir -p /root/.ssh && \
    chown root:root /root/.ssh && \
    chmod 700 /root/.ssh && \
    # Set permissions for authorized_keys if it exists (Vast.ai creates this later)
    touch /root/.ssh/authorized_keys && \
    chmod 600 /root/.ssh/authorized_keys

# *** Changed target from /root to /workspace ***
COPY ./src/debug_toolkit.ipynb /workspace/debug_toolkit.ipynb

# Set default VNC resolution (can be overridden at runtime)
ENV VNC_RESOLUTION=1280x1024

# == Entrypoint ==
# Use Supervisor to manage services
ENTRYPOINT ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]

# --- Notes ---
# Remember to create a .dockerignore file.
# Consider pinning versions.
