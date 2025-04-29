#!/bin/bash
# This script clones the repo into /VisoMaster, activates venv, installs TensorRT, downloads models,
# overwrites the inswapper model, creates output directories, AND STARTS VNC. Logs go to /logs.
# Run via Vast.ai On-Start: bash /provisioning_script.sh

# --- Define Paths and Variables ---
PROJECT_PARENT_DIR="/"
VISOMASTER_REPO_NAME="VisoMaster"
VISOMASTER_ROOT_DIR="$PROJECT_PARENT_DIR$VISOMASTER_REPO_NAME" # Results in /VisoMaster
VISOMASTER_REPO_URL="https://github.com/remphan1618/VisoMaster.git"
MODEL_DOWNLOAD_SCRIPT_NAME="download_models.py"
MODEL_DOWNLOAD_SCRIPT_FULL_PATH="$VISOMASTER_ROOT_DIR/$MODEL_DOWNLOAD_SCRIPT_NAME"
TENSORRT_REQS_FILE="requirements_cu124.txt" # Assuming this file exists in the repo
TENSORRT_REQS_FULL_PATH="$VISOMASTER_ROOT_DIR/$TENSORRT_REQS_FILE"
VENV_PATH="/opt/venv"
LOG_DIR="/logs"
LOG_FILE="$LOG_DIR/onstart_script.log"
# *** CORRECTED VNC SCRIPT PATH ***
VNC_STARTUP_SCRIPT="/dockerstartup/vnc_startup.sh" # Path where Dockerfile copies the script

# Specific Inswapper Model Details
INSWAPPER_URL="https://huggingface.co/Red1618/Viso/resolve/main/inswapper_128_fp16.onnx?download=true"
DOWNLOADED_INSWAPPER_NAME="inswapper_128_fp16.onnx.download"
TARGET_MODEL_DIR="$VISOMASTER_ROOT_DIR/models"
TARGET_INSWAPPER_NAME="inswapper_128_fp16.onnx"

# Directories to create
IMAGES_DIR="$VISOMASTER_ROOT_DIR/Images"
VIDEOS_DIR="$VISOMASTER_ROOT_DIR/Videos"
OUTPUT_DIR="$VISOMASTER_ROOT_DIR/Output"


# --- Setup Logging & Execution ---
mkdir -p "$LOG_DIR" # Create log directory first
exec > >(tee -a "$LOG_FILE") 2> >(tee -a "$LOG_FILE" >&2)
echo "--- Starting Provisioning Script $(date) ---"
echo "--- Logging to $LOG_FILE ---"
set -eux

# --- Clone VisoMaster Repository ---
if [ ! -d "$VISOMASTER_ROOT_DIR" ]; then
  echo "Cloning VisoMaster into $VISOMASTER_ROOT_DIR..."
  git clone "$VISOMASTER_REPO_URL" "$VISOMASTER_ROOT_DIR" || exit 1
  echo "Cloned."
else
  echo "Directory $VISOMASTER_ROOT_DIR already exists, skipping clone."
fi

# --- Create Required Directories ---
echo "Creating required directories inside $VISOMASTER_ROOT_DIR..."
mkdir -p "$IMAGES_DIR" || { echo "ERROR: Failed to create $IMAGES_DIR" >&2; exit 1; }
mkdir -p "$VIDEOS_DIR" || { echo "ERROR: Failed to create $VIDEOS_DIR" >&2; exit 1; }
mkdir -p "$OUTPUT_DIR" || { echo "ERROR: Failed to create $OUTPUT_DIR" >&2; exit 1; }
echo "Directories created: Images, Videos, Output."

# --- Activate Python Virtual Environment ---
echo "Activating venv..."
if [ ! -f "$VENV_PATH/bin/activate" ]; then echo "ERROR: Venv activate script not found!" >&2; exit 1; fi
source "$VENV_PATH/bin/activate"
echo "Python: $(which python)"

# --- Install TensorRT ---
echo "Installing TensorRT..."
if [ ! -f "$TENSORRT_REQS_FULL_PATH" ]; then echo "ERROR: TensorRT reqs file ($TENSORRT_REQS_FILE) not found in repo!" >&2; exit 1; fi
pip install -r "$TENSORRT_REQS_FULL_PATH" --no-cache-dir
echo "TensorRT install finished."

# --- Install tqdm ---
echo "Installing tqdm..."
pip install tqdm --no-cache-dir
echo "tqdm installed."

# --- Download VisoMaster Models ---
echo "Downloading models..."
if [ ! -f "$MODEL_DOWNLOAD_SCRIPT_FULL_PATH" ]; then echo "ERROR: Model download script ($MODEL_DOWNLOAD_SCRIPT_NAME) not found in repo!" >&2; exit 1; fi
cd "$VISOMASTER_ROOT_DIR" || { echo "ERROR: Failed to cd to $VISOMASTER_ROOT_DIR!" >&2; exit 1; }
echo "Executing $MODEL_DOWNLOAD_SCRIPT_FULL_PATH from $(pwd)..."
python "$MODEL_DOWNLOAD_SCRIPT_FULL_PATH"
if [ $? -ne 0 ]; then echo "ERROR: download_models.py failed!" >&2; exit 1; fi
echo "Model download finished."

# --- Download and Overwrite Specific Inswapper Model ---
echo "Downloading specific inswapper model from $INSWAPPER_URL..."
mkdir -p "$TARGET_MODEL_DIR" || { echo "ERROR: Failed to create target model directory $TARGET_MODEL_DIR" >&2; exit 1; }
wget -O "$TARGET_MODEL_DIR/$DOWNLOADED_INSWAPPER_NAME" "$INSWAPPER_URL"
if [ $? -ne 0 ]; then echo "ERROR: Failed to download inswapper model!" >&2; exit 1; fi
echo "Inswapper model downloaded."

echo "Renaming/Overwriting $DOWNLOADED_INSWAPPER_NAME to $TARGET_INSWAPPER_NAME in $TARGET_MODEL_DIR..."
mv -f "$TARGET_MODEL_DIR/$DOWNLOADED_INSWAPPER_NAME" "$TARGET_MODEL_DIR/$TARGET_INSWAPPER_NAME"
if [ $? -ne 0 ]; then echo "ERROR: Failed to rename/overwrite inswapper model!" >&2; exit 1; fi
echo "Inswapper model replaced successfully."

# --- Check if supervisor is running before starting VNC manually ---
if pgrep supervisord > /dev/null; then
    echo "Supervisor is running. Skipping manual VNC startup as it should be managed by supervisor."
else
    # --- Start VNC Service only if supervisor isn't running ---
    echo "Supervisor not detected. Attempting to start VNC service manually in the background..."
    # *** Check for the CORRECT path ***
    if [ ! -f "$VNC_STARTUP_SCRIPT" ]; then
        echo "ERROR: VNC startup script not found at $VNC_STARTUP_SCRIPT!" >&2
        exit 1
    fi
    # Run the VNC startup script in the background using bash
    bash "$VNC_STARTUP_SCRIPT" --wait &
    VNC_PID=$! # Get the process ID of the background VNC script
    sleep 5 # Give it a few seconds to potentially start or fail
    # Check if the process is still running (basic check)
    if kill -0 $VNC_PID > /dev/null 2>&1; then
        echo "VNC startup script process launched (PID: $VNC_PID). Check VNC connection."
    else
        echo "WARNING: VNC startup script process (PID: $VNC_PID) does not seem to be running after launch attempt. Check logs."
    fi
fi

echo "--- Provisioning Script Finished $(date) ---"
# Vast.ai should now consider the On-Start complete. VNC runs in background.
