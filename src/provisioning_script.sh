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
set -eu # Changed from 'set -eux' to not exit on errors

# --- Clone VisoMaster Repository ---
if [ ! -d "$VISOMASTER_ROOT_DIR/.git" ]; then
  echo "Checking VisoMaster directory..."
  if [ -d "$VISOMASTER_ROOT_DIR" ] && [ "$(ls -A $VISOMASTER_ROOT_DIR)" ]; then
    echo "Directory $VISOMASTER_ROOT_DIR already exists and has content, skipping clone."
    echo "Using existing VisoMaster directory."
  else
    echo "Cloning VisoMaster into $VISOMASTER_ROOT_DIR..."
    git clone "$VISOMASTER_REPO_URL" "$VISOMASTER_ROOT_DIR" || { 
      echo "ERROR: Failed to clone repository. Continuing execution..." >&2
    }
  fi
else
  echo "Directory $VISOMASTER_ROOT_DIR already contains a git repository, updating..."
  cd "$VISOMASTER_ROOT_DIR"
  git pull || echo "ERROR: Failed to update repository. Continuing execution..." >&2
fi

# --- Create Required Directories ---
echo "Creating required directories inside $VISOMASTER_ROOT_DIR..."
mkdir -p "$IMAGES_DIR" || { echo "ERROR: Failed to create $IMAGES_DIR" >&2; }
mkdir -p "$VIDEOS_DIR" || { echo "ERROR: Failed to create $VIDEOS_DIR" >&2; }
mkdir -p "$OUTPUT_DIR" || { echo "ERROR: Failed to create $OUTPUT_DIR" >&2; }
mkdir -p "$TARGET_MODEL_DIR" || { echo "ERROR: Failed to create $TARGET_MODEL_DIR" >&2; }
echo "Directories created: Images, Videos, Output, models."

# --- Activate Python Virtual Environment ---
echo "Activating venv..."
if [ ! -f "$VENV_PATH/bin/activate" ]; then 
  echo "WARNING: Venv activate script not found at $VENV_PATH/bin/activate!" >&2
  echo "Continuing without virtual environment"
else
  source "$VENV_PATH/bin/activate"
  echo "Python: $(which python)"
fi

# --- Install TensorRT ---
echo "Installing TensorRT..."
if [ ! -f "$TENSORRT_REQS_FULL_PATH" ]; then 
  echo "WARNING: TensorRT reqs file ($TENSORRT_REQS_FILE) not found in repo!" >&2
  echo "Checking alternative locations for requirements files..."
  if [ -f "/requirements_124.txt" ]; then
    echo "Using /requirements_124.txt instead..."
    pip install -r "/requirements_124.txt" --no-cache-dir || echo "WARNING: Failed to install TensorRT. Continuing execution..." >&2
  else
    echo "WARNING: Could not find any requirements file. Skipping TensorRT installation."
  fi
else
  pip install -r "$TENSORRT_REQS_FULL_PATH" --no-cache-dir || echo "WARNING: Failed to install TensorRT. Continuing execution..." >&2
fi
echo "TensorRT install attempt finished."

# --- Install tqdm ---
echo "Installing tqdm..."
pip install tqdm --no-cache-dir || echo "WARNING: Failed to install tqdm. Continuing execution..." >&2
echo "tqdm install attempt finished."

# --- Download VisoMaster Models ---
if [ -f "$MODEL_DOWNLOAD_SCRIPT_FULL_PATH" ]; then
  echo "Downloading models..."
  cd "$VISOMASTER_ROOT_DIR" || { 
    echo "ERROR: Failed to cd to $VISOMASTER_ROOT_DIR!" >&2
    echo "Skipping model download." 
  }
  
  if [ -f "$MODEL_DOWNLOAD_SCRIPT_NAME" ]; then
    echo "Executing $MODEL_DOWNLOAD_SCRIPT_FULL_PATH from $(pwd)..."
    python "$MODEL_DOWNLOAD_SCRIPT_FULL_PATH" || echo "WARNING: download_models.py failed! Continuing execution..." >&2
    echo "Model download attempt finished."
  else
    echo "WARNING: $MODEL_DOWNLOAD_SCRIPT_NAME not found in current directory $(pwd). Skipping model download."
  fi
else
  echo "WARNING: Model download script ($MODEL_DOWNLOAD_SCRIPT_FULL_PATH) not found. Skipping model download."
fi

# --- Download and Overwrite Specific Inswapper Model ---
echo "Downloading specific inswapper model from $INSWAPPER_URL..."
wget -O "$TARGET_MODEL_DIR/$DOWNLOADED_INSWAPPER_NAME" "$INSWAPPER_URL" || {
  echo "ERROR: Failed to download inswapper model!" >&2
  echo "Continuing execution..." 
}

if [ -f "$TARGET_MODEL_DIR/$DOWNLOADED_INSWAPPER_NAME" ]; then
  echo "Renaming/Overwriting $DOWNLOADED_INSWAPPER_NAME to $TARGET_INSWAPPER_NAME in $TARGET_MODEL_DIR..."
  mv -f "$TARGET_MODEL_DIR/$DOWNLOADED_INSWAPPER_NAME" "$TARGET_MODEL_DIR/$TARGET_INSWAPPER_NAME" || {
    echo "ERROR: Failed to rename/overwrite inswapper model!" >&2
    echo "Continuing execution..." 
  }
  echo "Inswapper model operation finished."
else
  echo "WARNING: Downloaded inswapper model not found, skipping rename operation."
fi

# --- Check if supervisor is running before starting VNC manually ---
if pgrep supervisord > /dev/null; then
    echo "Supervisor is running. Skipping manual VNC startup as it should be managed by supervisor."
else
    # --- Start VNC Service only if supervisor isn't running ---
    echo "Supervisor not detected. Attempting to start VNC service manually in the background..."
    # *** Check for the CORRECT path ***
    if [ ! -f "$VNC_STARTUP_SCRIPT" ]; then
        echo "WARNING: VNC startup script not found at $VNC_STARTUP_SCRIPT!" >&2
        echo "Checking alternative locations..."
        
        # Try to find the script in other locations
        for alt_path in "/src/vnc_startup_jupyterlab.sh" "/vnc_startup.sh"; do
            if [ -f "$alt_path" ]; then
                echo "Found alternative VNC script at $alt_path"
                # Copy to expected location
                cp "$alt_path" "$VNC_STARTUP_SCRIPT"
                chmod +x "$VNC_STARTUP_SCRIPT"
                break
            fi
        done
    fi
    
    # Try to start VNC if we have a script
    if [ -f "$VNC_STARTUP_SCRIPT" ]; then
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
    else
        echo "WARNING: Could not find VNC startup script. VNC will not be started manually."
    fi
fi

echo "--- Provisioning Script Finished $(date) ---"
# Vast.ai should now consider the On-Start complete.
