# Use the smaller runtime base image
FROM nvidia/cuda:12.4.1-cudnn-runtime-ubuntu22.04

# Set a refresh date (adjust as needed)
ENV REFRESHED_AT 2024-08-12

# == Environment Variables ==
ENV HOME=/root \
    TERM=xterm \
    STARTUPDIR=/dockerstartup \
    # *** Using /install for install scripts ***
    INST_SCRIPTS=/install \
    NO_VNC_HOME=/noVNC \
    VENV_PATH=/opt/venv \
    DEBIAN_FRONTEND=noninteractive \
    VNC_COL_DEPTH=24 \
    VNC_PW=vncpassword \
    VNC_VIEW_ONLY=false \
    TZ=Asia/Seoul \
    LANG='en_US.UTF-8' \
    LANGUAGE='en_US:en' \
    LC_ALL='en_US.UTF-8' \
    PATH="/opt/venv/bin:$PATH"

# Set working directory to root
WORKDIR /

# == Expose Ports ==
EXPOSE 5901 6901 8888 22 8585

# == Install System Dependencies ==
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
# Keep SSH config targeted at /root/.ssh
RUN mkdir -p /root/.ssh && \
    chmod 700 /root/.ssh && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config && \
    echo "StrictModes no" >> /etc/ssh/sshd_config && \
    mkdir -p /var/run/sshd

# == Configure Supervisor ==
RUN mkdir -p /etc/supervisor/conf.d
COPY ./src/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# == Add and Run Install Scripts ==
# *** Using /install ***
RUN mkdir -p $INST_SCRIPTS
ADD ./src/common/install/ $INST_SCRIPTS/
ADD ./src/debian/install/ $INST_SCRIPTS/
RUN chmod 765 $INST_SCRIPTS/*

# Run Installers from /install
RUN $INST_SCRIPTS/tools.sh
RUN $INST_SCRIPTS/install_custom_fonts.sh
RUN $INST_SCRIPTS/tigervnc.sh
RUN $INST_SCRIPTS/no_vnc_1.5.0.sh
RUN $INST_SCRIPTS/icewm_ui.sh
RUN $INST_SCRIPTS/libnss_wrapper.sh
RUN apt-get clean && rm -rf /var/lib/apt/lists/* || echo "No apt lists to clean"

# == Add Runtime Configs and Scripts ==
# *** Copy IceWM config to /etc/icewm for clarity ***
RUN mkdir -p /etc/icewm
COPY ./src/debian/icewm/wm_startup.sh /etc/icewm/wm_startup.sh
RUN chmod 755 /etc/icewm/wm_startup.sh

RUN mkdir -p $STARTUPDIR
ADD ./src/common/scripts $STARTUPDIR
COPY ./src/vnc_startup_jupyterlab_filebrowser.sh /dockerstartup/vnc_startup.sh
# *** Copy provisioning script to / ***
COPY ./src/provisioning_script.sh /provisioning_script.sh
RUN chmod +x /provisioning_script.sh
RUN chmod 765 /dockerstartup/vnc_startup.sh

# == Setup Python Virtual Environment and Install Dependencies ==
RUN python3 -m venv $VENV_PATH
RUN . $VENV_PATH/bin/activate && \
    pip install --no-cache-dir --upgrade pip && \
    # Repo is cloned by provisioning_script.sh into /VisoMaster
    pip install --no-cache-dir scikit-image jupyterlab tqdm && \
    rm -rf /root/.cache/pip

# Set WORKDIR back to / just in case
WORKDIR /

# == Install File Browser ==
RUN wget -O - https://raw.githubusercontent.com/filebrowser/get/master/get.sh | bash

# == Final Setup & Permission Fixes ==
# *** Target /VisoMaster for permissions if needed ***
RUN if [ -f $INST_SCRIPTS/set_user_permission.sh ]; then $INST_SCRIPTS/set_user_permission.sh $STARTUPDIR /VisoMaster; fi
# Fix /root/.ssh permissions
RUN mkdir -p /root/.ssh && \
    chown root:root /root/.ssh && \
    chmod 700 /root/.ssh && \
    touch /root/.ssh/authorized_keys && \
    chmod 600 /root/.ssh/authorized_keys

# *** Copy debug notebook to / ***
COPY ./src/debug_toolkit.ipynb /debug_toolkit.ipynb

# Set default VNC resolution
ENV VNC_RESOLUTION=1280x1024

# == Entrypoint ==
ENTRYPOINT ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]

# --- Notes ---
# Remember to create a .dockerignore file.
# Consider pinning versions.
