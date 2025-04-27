    # Use the smaller runtime base image
    FROM nvidia/cuda:12.4.1-cudnn-runtime-ubuntu22.04

    # Set a refresh date (adjust as needed)
    ENV REFRESHED_AT 2024-08-12

    # == Environment Variables ==
    # Define static ENV vars early for better layer caching
    ENV HOME=/root \
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

    # Set working directory
    WORKDIR $HOME

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
    RUN mkdir -p /var/run/sshd /root/.ssh && \
        chmod 700 /root/.ssh && \
        sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
        sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config

    # == Configure Supervisor ==
    RUN mkdir -p /etc/supervisor/conf.d
    COPY ./src/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

    # == Add and Run Install Scripts ==
    RUN mkdir -p $INST_SCRIPTS
    ADD ./src/common/install/ $INST_SCRIPTS/
    ADD ./src/debian/install/ $INST_SCRIPTS/
    RUN chmod 765 $INST_SCRIPTS/*

    # Run Installers
    RUN $INST_SCRIPTS/tools.sh
    RUN $INST_SCRIPTS/install_custom_fonts.sh
    RUN $INST_SCRIPTS/tigervnc.sh
    RUN $INST_SCRIPTS/no_vnc_1.5.0.sh
    RUN $INST_SCRIPTS/icewm_ui.sh
    RUN $INST_SCRIPTS/libnss_wrapper.sh
    RUN apt-get clean && rm -rf /var/lib/apt/lists/* || echo "No apt lists to clean"

    # == Add Runtime Configs and Scripts ==
    ADD ./src/debian/icewm/ $HOME/ # IceWM runtime config
    RUN mkdir -p $STARTUPDIR
    ADD ./src/common/scripts $STARTUPDIR # Common helper scripts
    COPY ./src/vnc_startup_jupyterlab_filebrowser.sh /dockerstartup/vnc_startup.sh # Main startup script
    # *** ADDED: Copy the provisioning script and make it executable ***
    COPY ./src/provisioning_script.sh /root/provisioning_script.sh
    RUN chmod +x /root/provisioning_script.sh
    # *** End ADDED ***
    RUN chmod 765 /dockerstartup/vnc_startup.sh

    # == Setup Python Virtual Environment and Install Dependencies ==
    RUN python3 -m venv $VENV_PATH
    RUN . $VENV_PATH/bin/activate && \
        pip install --no-cache-dir --upgrade pip && \
        # Note: Repo is now cloned by provisioning_script.sh, not here.
        # Install base requirements, scikit-image, jupyterlab
        # Ensure requirements.txt is copied or available if needed for base install
        # If requirements.txt is ONLY needed after cloning, this pip install might change
        # Assuming base requirements are minimal or handled by apt:
        pip install --no-cache-dir scikit-image jupyterlab && \
        rm -rf /root/.cache/pip

    # Set WORKDIR after installs if needed
    WORKDIR $HOME

    # == Install File Browser ==
    RUN wget -O - https://raw.githubusercontent.com/filebrowser/get/master/get.sh | bash

    # == Final Setup ==
    RUN $INST_SCRIPTS/set_user_permission.sh $STARTUPDIR $HOME

    # Set default VNC resolution (can be overridden at runtime)
    ENV VNC_RESOLUTION=1280x1024

    # == Entrypoint ==
    ENTRYPOINT ["/usr/bin/supervisord", "-c", "/etc/supervisor/supervisord.conf"]

    # --- Notes ---
    # Remember to create a .dockerignore file.
    # Consider pinning versions.
    
