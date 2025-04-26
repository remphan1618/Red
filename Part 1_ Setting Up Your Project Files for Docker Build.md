# **Part 1: Setting Up Your Project Files for Docker Build**

This guide covers getting your local files and folders organized correctly so you can build your custom Docker image automatically.  
**Goal Recap:** Create a Docker image with IceWM, VNC, SSH, Jupyter (no auth), and VisoMaster, ready for Docker Hub and Vast.ai.

## **Step 1.1: Organize Your Project Folder**

You need a main folder for this project. Inside that folder, create the files and subfolders exactly as shown below. Pay close attention to names and locations. Getting this structure right is fundamental, as the Dockerfile relies on these specific paths to copy files into the image during the build process.  
your-project-folder/  
├── Dockerfile                      \# \<-- The main recipe (Content below)  
└── src/                            \# \<-- Folder named 'src'  
    ├── supervisord.conf            \# \<-- \*\*\* NEW file you MUST create \*\*\* (Content below)  
    ├── vnc\_startup\_jupyterlab\_filebrowser.sh \# \<-- Your main startup script  
    ├── common/                     \# \<-- Folder  
    │   ├── install/                \# \<-- Folder  
    │   │   ├── firefox.sh  
    │   │   ├── no\_vnc\_1.5.0.sh  
    │   │   └── set\_user\_permission.sh  
    │   └── scripts/                \# \<-- Folder  
    │       └── generate\_container\_user \# (and maybe others needed by your scripts)  
    └── debian/                     \# \<-- Folder  
        ├── install/                \# \<-- Folder  
        │   ├── icewm\_ui.sh         \# \<-- \*\*\* CHECK NAME\! Must be this & install IceWM \*\*\*  
        │   ├── install\_custom\_fonts.sh  
        │   ├── libnss\_wrapper.sh  
        │   ├── tigervnc.sh  
        │   └── tools.sh  
        └── icewm/                  \# \<-- Folder  
            └── wm\_startup.sh       \# \<-- The script that runs 'icewm-session'

**Super Important Checks:**  
These checks are critical to ensure the Docker build process runs smoothly and the final container behaves as expected. Skipping these often leads to build failures or runtime issues that can be tricky to diagnose.

1. **src/supervisord.conf:** You *must* create this specific file inside the src folder. Think of Supervisor as the orchestra conductor for your container; it tells the different services (SSH, Jupyter, VNC) when and how to start. This configuration file (supervisord.conf) is the sheet music for that conductor. Without this file being copied into the image correctly, Supervisor won't know what to do, and your services simply won't start up automatically when the container launches. Make sure you copy the exact text provided in Step 1.3 below into this file.  
2. **src/debian/install/icewm\_ui.sh:** This one is crucial and has two parts. First, make absolutely sure the file exists with this *exact name* (icewm\_ui.sh) in this *exact folder* (src/debian/install/). The Dockerfile explicitly tries to run a script with this name (RUN $INST\_SCRIPTS/icewm\_ui.sh); if it's named differently (like xfce\_ui.sh) or missing, the Docker build will fail at that step. Second, verify the *content* of the script. Open it up and confirm it actually installs the IceWM window manager (look for commands like apt-get update && apt-get install \-y icewm icewm-common or similar). If it installs XFCE or something else, the VNC session won't start correctly later because the runtime scripts expect IceWM. If your script *does* install IceWM but has a different name, **rename the file** to icewm\_ui.sh. Consistency between the installation script, the runtime scripts (wm\_startup.sh), and the Dockerfile commands is key.  
3. **Other Scripts:** Take a moment to double-check that all the other .sh files listed in the folder structure above (like tools.sh, tigervnc.sh, firefox.sh, etc.) are actually present in the correct install folders (src/common/install/ or src/debian/install/). While their exact location between these two specific install folders isn't critical (since both get copied to the same place in the image), their *presence* is vital. If the Dockerfile tries to execute a script (e.g., RUN $INST\_SCRIPTS/tools.sh) and that script file wasn't copied because it was missing from your local src directory, the Docker build will halt with an error right there.

## **Step 1.2: Create the Dockerfile**

Create a file named Dockerfile (no extension) directly inside your-project-folder/. Paste this *entire* block of text into it:  
\# Base image (CUDA 12.4.1)  
FROM nvidia/cuda:12.4.1-cudnn-devel-ubuntu22.04

\# Set a refresh date (adjust as needed)  
ENV REFRESHED\_AT 2024-08-12

\# Labels describing the image  
LABEL io.k8s.description="Headless VNC Container with IceWM, Jupyter, SSH, VisoMaster for Vast.ai" \\  
      io.k8s.display-name="VNC IceWM VisoMaster" \\  
      io.openshift.expose-services="6901:http,5901:xvnc,8888:http,22:ssh" \\  
      io.openshift.tags="vnc, icewm, jupyter, ssh, vastai, visomaster" \\  
      io.openshift.non-scalable=true

\#\#\# Connection ports Environment Variables  
ENV DISPLAY=:1 \\  
    VNC\_PORT=5901 \\  
    NO\_VNC\_PORT=6901 \\  
    JUPYTER\_PORT=8888 \\  
    SSH\_PORT=22  
\# Expose ports  
EXPOSE $VNC\_PORT $NO\_VNC\_PORT $JUPYTER\_PORT $SSH\_PORT

\#\#\# Environment config Variables  
ENV HOME=/root \\  
    TERM=xterm \\  
    STARTUPDIR=/dockerstartup \\  
    INST\_SCRIPTS=/workspace/install \\  
    NO\_VNC\_HOME=/workspace/noVNC \\  
    DEBIAN\_FRONTEND=noninteractive \\  
    VNC\_COL\_DEPTH=24 \\  
    VNC\_PW=vncpassword \\  
    VNC\_VIEW\_ONLY=false \\  
    TZ=Asia/Seoul \\  
    LANG='en\_US.UTF-8' \\  
    LANGUAGE='en\_US:en' \\  
    LC\_ALL='en\_US.UTF-8'  
\# Set working directory  
WORKDIR $HOME

\#\#\# Install dependencies: Base Utils, System Python, SSH Server, Supervisor  
RUN apt-get update && apt-get install \-y \--no-install-recommends \\  
    wget \\  
    git \\  
    build-essential \\  
    software-properties-common \\  
    apt-transport-https \\  
    ca-certificates \\  
    unzip \\  
    ffmpeg \\  
    tzdata \\  
    python3 \\  
    python3-pip \\  
    python3-venv \\  
    openssh-server \\  
    supervisor \\  
    \# Set timezone  
    && ln \-fs /usr/share/zoneinfo/$TZ /etc/localtime && \\  
    dpkg-reconfigure \-f noninteractive tzdata && \\  
    \# Clean up apt cache  
    apt-get clean && \\  
    rm \-rf /var/lib/apt/lists/\* && \\  
    \# Ensure pip is up to date for the system Python  
    python3 \-m pip install \--no-cache-dir \--upgrade pip

\#\#\# Configure SSH Server (Allow Root Login via key, disable password auth)  
RUN mkdir \-p /var/run/sshd /root/.ssh && \\  
    chmod 700 /root/.ssh && \\  
    \# Allow root login (needed for key injection on platforms like Vast.ai)  
    sed \-i 's/\#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd\_config && \\  
    \# Disable password authentication for security (rely on keys)  
    sed \-i 's/\#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd\_config

\#\#\# Configure Supervisor  
RUN mkdir \-p /etc/supervisor/conf.d  
\# Copy the supervisor config file from the build context  
COPY ./src/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

\#\#\# Add install scripts from src/common and src/debian into the image  
RUN mkdir \-p $INST\_SCRIPTS  
ADD ./src/common/install/ $INST\_SCRIPTS/  
ADD ./src/debian/install/ $INST\_SCRIPTS/  
\# Make scripts executable  
RUN chmod 765 $INST\_SCRIPTS/\*

\#\#\# Run Installers from the INST\_SCRIPTS directory  
RUN $INST\_SCRIPTS/tools.sh  
RUN $INST\_SCRIPTS/install\_custom\_fonts.sh  
RUN $INST\_SCRIPTS/tigervnc.sh  
RUN $INST\_SCRIPTS/no\_vnc\_1.5.0.sh  
RUN $INST\_SCRIPTS/firefox.sh  
\# \*\*\* IMPORTANT: Ensure 'icewm\_ui.sh' exists in src/debian/install and installs IceWM \*\*\*  
RUN $INST\_SCRIPTS/icewm\_ui.sh  
RUN $INST\_SCRIPTS/libnss\_wrapper.sh

\#\#\# Add IceWM runtime config (e.g., wm\_startup.sh)  
ADD ./src/debian/icewm/ $HOME/

\#\#\# Configure startup directory and permissions  
RUN mkdir \-p $STARTUPDIR  
ADD ./src/common/scripts $STARTUPDIR  
RUN $INST\_SCRIPTS/set\_user\_permission.sh $STARTUPDIR $HOME

\#\#\# Install VisoMaster (remphan1618 fork)  
RUN git clone https://github.com/remphan1618/VisoMaster.git  
WORKDIR $HOME/VisoMaster

\# Install Python dependencies using requirements.txt (using system pip)  
RUN pip install \--no-cache-dir \-r requirements.txt  
\# Keep scikit-image install (using system pip)  
RUN pip install \--no-cache-dir scikit-image

\# Keep model/dependency downloads as removal was not explicitly requested  
RUN mkdir \-p ./dependencies \# Ensure directory exists  
RUN wget \-O ./dependencies/ffmpeg.exe https://github.com/visomaster/visomaster-assets/releases/download/v0.1.0\_dp/ffmpeg.exe  
RUN python3 download\_models.py

\#\#\# Install jupyterlab using system pip  
RUN pip install \--no-cache-dir jupyterlab  
\# Port 8888 already exposed

\#\#\# Install filebrowser  
RUN wget \-O \- https://raw.githubusercontent.com/filebrowser/get/master/get.sh | bash  
\# Expose filebrowser port if you intend to run it manually or via supervisor  
EXPOSE 8585

\#\#\# Install extra libraries (GUI/Qt/File Manager)  
RUN apt-get update && apt-get install \-y \--no-install-recommends \\  
    libegl1 libgl1-mesa-glx libglib2.0-0 \\  
    libxcb-cursor0 libxcb-xinerama0 libxkbcommon-x11-0 \\  
    libqt5gui5 libqt5core5a libqt5widgets5 libqt5x11extras5 \\  
    pcmanfm \\  
    \# Clean up apt cache  
    && apt-get clean && rm \-rf /var/lib/apt/lists/\*

\#\#\# Copy main startup script and set permissions  
\# This script is expected to be run by Supervisor  
COPY ./src/vnc\_startup\_jupyterlab\_filebrowser.sh /dockerstartup/vnc\_startup.sh  
RUN chmod 765 /dockerstartup/vnc\_startup.sh

\# Set default VNC resolution  
ENV VNC\_RESOLUTION=1280x1024

\# Set the entrypoint to run Supervisor, which manages other processes  
ENTRYPOINT \["/usr/bin/supervisord", "-c", "/etc/supervisor/supervisord.conf"\]  
\# CMD is not needed when using supervisor as entrypoint

## **Step 1.3: Create the Supervisor Config (src/supervisord.conf)**

Create a file named supervisord.conf inside your src/ folder. Paste this *entire* block into it:  
\# /src/supervisord.conf  
\# Configuration file for Supervisor process manager

\[supervisord\]  
nodaemon=true       ; Run supervisor in the foreground (required for Docker)  
user=root           ; Run supervisor itself as root

\[program:sshd\]  
command=/usr/sbin/sshd \-D ; Run the SSH daemon in the foreground  
autostart=true            ; Start sshd automatically when supervisor starts  
autorestart=true          ; Restart sshd if it crashes  
priority=10               ; Lower priority means start earlier  
stdout\_logfile=/dev/stdout ; Redirect stdout to container log  
stdout\_logfile\_maxbytes=0  ; Disable log rotation for stdout  
stderr\_logfile=/dev/stderr ; Redirect stderr to container log  
stderr\_logfile\_maxbytes=0  ; Disable log rotation for stderr

\[program:jupyter\]  
\# Run jupyter lab, listening on all interfaces (0.0.0.0), NO AUTHENTICATION (token/password \= '')  
command=jupyter lab \--ip=0.0.0.0 \--port=8888 \--no-browser \--allow-root \--NotebookApp.token='' \--NotebookApp.password='' \--NotebookApp.allow\_origin='\*' \--NotebookApp.base\_url=${JUPYTER\_BASE\_URL:-/}  
directory=/root/VisoMaster  ; Start Jupyter in the VisoMaster directory  
autostart=true              ; Start Jupyter automatically  
autorestart=true            ; Restart Jupyter if it crashes  
priority=20                 ; Start after sshd  
stdout\_logfile=/dev/stdout  
stdout\_logfile\_maxbytes=0  
stderr\_logfile=/dev/stderr  
stderr\_logfile\_maxbytes=0  
user=root                   ; Run Jupyter as root

\[program:vnc\]  
\# Runs the original VNC startup script from /dockerstartup/  
\# This script should handle starting the VNC server and the window manager (IceWM)  
\# Ensure the script inside /dockerstartup/vnc\_startup.sh correctly calls the IceWM startup script (e.g., /root/wm\_startup.sh)  
command=/dockerstartup/vnc\_startup.sh \--wait  
autostart=true              ; Start VNC automatically  
autorestart=true            ; Restart VNC service if it crashes  
priority=30                 ; Start after Jupyter  
stdout\_logfile=/dev/stdout  
stdout\_logfile\_maxbytes=0  
stderr\_logfile=/dev/stderr  
stderr\_logfile\_maxbytes=0  
user=root                   ; Run VNC startup as root

## **Step 1.4: Create the GitHub Actions Workflow File**

This file tells GitHub how to automatically build your image.

1. In your-project-folder/, create a folder named .github (with the dot).  
2. Inside .github/, create another folder named workflows.  
3. Inside .github/workflows/, create a file named docker-build.yml.  
4. Paste this *entire* block into docker-build.yml:

name: Build and Push Docker Image

on:  
  push:  
    branches:  
      \- main  \# Trigger on pushes to the main branch  
  workflow\_dispatch:  \# Allow manual triggering from the GitHub UI

jobs:  
  build-and-push:  
    name: Build and Push VisoMaster Image  
    runs-on: ubuntu-latest  
    permissions:  
      contents: read  
      packages: write \# Might be needed depending on cache/registry setup

    steps:  
      \# Step 1: Get your code from GitHub  
      \- name: Checkout code  
        uses: actions/checkout@v4  
        with:  
          fetch-depth: 0 \# Gets all history, useful for tags/SHAs

      \# Step 2: Set up Docker Buildx (fancy builder)  
      \- name: Set up Docker Buildx  
        uses: docker/setup-buildx-action@v3

      \# Step 3: Log in to Docker Hub so we can push the image  
      \- name: Login to Docker Hub  
        uses: docker/login-action@v3  
        with:  
          username: ${{ secrets.DOCKERHUB\_USERNAME }}  
          \# IMPORTANT: Use a Docker Hub Access Token here, not your password\!  
          password: ${{ secrets.DOCKERHUB\_PASSWORD }}

      \# Step 4: Build the image and push it to Docker Hub  
      \- name: Build and push Docker image  
        id: build-and-push  
        uses: docker/build-push-action@v5  
        with:  
          context: . \# Use the current directory as the build context  
          file: ./Dockerfile \# Tell it where your Dockerfile is  
          \# Only push if it's the main branch or manually triggered  
          push: ${{ github.event\_name \== 'push' || github.event\_name \== 'workflow\_dispatch' }}  
          \# Tag the image with 'latest' and the specific commit ID  
          tags: |  
            ${{ secrets.DOCKERHUB\_USERNAME }}/visomasterdockah:latest  
            ${{ secrets.DOCKERHUB\_USERNAME }}/visomasterdockah:${{ github.sha }}  
          \# Use GitHub Actions cache to speed up future builds  
          cache-from: type=gha  
          cache-to: type=gha,mode=max

      \# Step 5: Print the image digest (like a fingerprint) if it was pushed  
      \- name: Image digest  
        if: steps.build-and-push.outputs.digest \!= ''  
        run: echo "Pushed image digest: ${{ steps.build-and-push.outputs.digest }}"

**Next Steps:** Once you have completed all steps in this guide (created the files, verified the structure and script names), proceed to Part 2 which covers setting up secrets, pushing to GitHub, and using the image on Vast.ai.