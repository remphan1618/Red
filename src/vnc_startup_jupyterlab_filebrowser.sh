#!/bin/bash
### Modified to prevent immediate exits on errors
set +e

## Create logs directory if it doesn't exist
mkdir -p /logs

## print out help
help (){
echo "
USAGE:
docker run -it -p 6901:6901 -p 5901:5901 consol/<image>:<tag> <option>

IMAGES:
consol/debian-xfce-vnc
consol/rocky-xfce-vnc
consol/debian-icewm-vnc
consol/rocky-icewm-vnc

TAGS:
latest  stable version of branch 'master'
dev     current development version of branch 'dev'

OPTIONS:
-w, --wait      (default) keeps the UI and the vncserver up until SIGINT or SIGTERM will received
-s, --skip      skip the vnc startup and just execute the assigned command.
                example: docker run consol/rocky-xfce-vnc --skip bash
-d, --debug     enables more detailed startup output
                e.g. 'docker run consol/rocky-xfce-vnc --debug bash'
-h, --help      print out this help

Fore more information see: https://github.com/ConSol/docker-headless-vnc-container
"
}
if [[ $1 =~ -h|--help ]]; then
    help
    exit 0
fi

# should also source $STARTUPDIR/generate_container_user
source $HOME/.bashrc

# add `--skip` to startup args, to skip the VNC startup procedure
if [[ $1 =~ -s|--skip ]]; then
    echo -e "\n\n------------------ SKIP VNC STARTUP -----------------"
    echo -e "\n\n------------------ EXECUTE COMMAND ------------------"
    echo "Executing command: '${@:2}'"
    exec "${@:2}"
fi
if [[ $1 =~ -d|--debug ]]; then
    echo -e "\n\n------------------ DEBUG VNC STARTUP -----------------"
    export DEBUG=true
fi

## correct forwarding of shutdown signal
cleanup () {
    kill -s SIGTERM $!
    exit 0
}
trap cleanup SIGINT SIGTERM

## write correct window size to chrome properties
# $STARTUPDIR/chrome-init.sh
# source $HOME/.chromium-browser.init

## resolve_vnc_connection
VNC_IP=$(hostname -i)

## change vnc password - making it completely open
echo -e "\n------------------ disabling VNC password ------------------"
# Set VNC to no security mode
mkdir -p "$HOME/.vnc"
PASSWD_PATH="$HOME/.vnc/passwd"

if [[ -f $PASSWD_PATH ]]; then
    echo -e "\n---------  purging existing VNC password settings  ---------"
    rm -f $PASSWD_PATH
fi

# Create an empty password file
touch $PASSWD_PATH
chmod 644 $PASSWD_PATH

## start vncserver and noVNC webclient
echo -e "\n------------------ start noVNC  ----------------------------"
if [[ $DEBUG == true ]]; then echo "$NO_VNC_HOME/utils/novnc_proxy --vnc localhost:$VNC_PORT --listen $NO_VNC_PORT"; fi
$NO_VNC_HOME/utils/novnc_proxy --vnc localhost:$VNC_PORT --listen $NO_VNC_PORT > /logs/no_vnc_startup.log 2>&1 &
PID_SUB=$!

#echo -e "\n------------------ start VNC server ------------------------"
#echo "remove old vnc locks to be a reattachable container"
vncserver -kill $DISPLAY &> /logs/vnc_startup.log \
    || rm -rfv /tmp/.X*-lock /tmp/.X11-unix &> /logs/vnc_startup.log \
    || echo "no locks present"

echo -e "start vncserver with param: VNC_COL_DEPTH=$VNC_COL_DEPTH, VNC_RESOLUTION=$VNC_RESOLUTION\n..."

# Modified to disable all security and authentication
vnc_cmd="vncserver $DISPLAY -depth $VNC_COL_DEPTH -geometry $VNC_RESOLUTION -localhost no -interface 0.0.0.0 -SecurityTypes None"

if [[ $DEBUG == true ]]; then echo "$vnc_cmd"; fi
$vnc_cmd > /logs/no_vnc_startup.log 2>&1

echo -e "start window manager\n..."
$HOME/wm_startup.sh &> /logs/wm_startup.log

## log connect options
echo -e "\n\n------------------ VNC environment started ------------------"
echo -e "\nVNCSERVER started on DISPLAY= $DISPLAY \n\t=> connect via VNC viewer with $VNC_IP:$VNC_PORT"
echo -e "\nnoVNC HTML client started:\n\t=> connect via http://$VNC_IP:$NO_VNC_PORT/?password=...\n"
echo -e "Starting jupyterlab at port 8080..."
nohup jupyter lab --port 8080 --notebook-dir=/workspace --allow-root --no-browser --ip=0.0.0.0  --NotebookApp.token='' --NotebookApp.password='' > /logs/jupyter.log 2>&1 &
echo -e "Starting jupyterlab at port 8585..."
nohup filebrowser -r /workspace -p 8585 -a 0.0.0.0 --noauth > /logs/filebrowser.log 2>&1 &

# Modified to use correct path and handle errors
echo -e "Looking for VisoMaster..."
if [ -d "/VisoMaster" ] && [ -f "/VisoMaster/main.py" ]; then
    echo -e "Starting VisoMaster..."
    python /VisoMaster/main.py > /logs/visomaster.log 2>&1 &
    echo -e "VisoMaster started in background with PID $!"
elif [ -d "/$HOME/VisoMaster" ] && [ -f "/$HOME/VisoMaster/main.py" ]; then
    echo -e "Starting VisoMaster from home directory..."
    python /$HOME/VisoMaster/main.py > /logs/visomaster.log 2>&1 &
    echo -e "VisoMaster started in background with PID $!"
else
    echo -e "VisoMaster not found. Skipping VisoMaster startup."
fi

if [[ $DEBUG == true ]] || [[ $1 =~ -t|--tail-log ]]; then
    echo -e "\n------------------ $HOME/.vnc/*$DISPLAY.log ------------------"
    # if option `-t` or `--tail-log` block the execution and tail the VNC log
    tail -f /logs/*.log $HOME/.vnc/*$DISPLAY.log
fi

if [ -z "$1" ] || [[ $1 =~ -w|--wait ]]; then
    # Keep the script running indefinitely to prevent supervisor from restarting it
    echo "Keeping VNC service alive..."
    while true; do
        sleep 60
    done
else
    # unknown option ==> call command
    echo -e "\n\n------------------ EXECUTE COMMAND ------------------"
    echo "Executing command: '$@'"
    exec "$@"
fi
