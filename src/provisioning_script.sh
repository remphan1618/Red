#!/bin/bash
# This script clones the repo, activates venv, installs TensorRT, downloads models,
# overwrites the inswapper model, and creates output directories.
# It's intended to be copied into the Docker image and run via the Vast.ai On-Start field.

# --- Define Paths and Variables ---
PROJECT_PARENT_DIR="/root"
VISOMASTER_REPO_NAME="VisoMaster"
VISOMASTER_ROOT_DIR="$PROJECT_PARENT_DIR/$VISOMASTER_REPO_NAME"
VISOMASTER_REPO_URL="https://github.com/remphan1618/VisoMaster.git"
MODEL_DOWNLOAD_SCRIPT_NAME="download_models.py"
MODEL_DOWNLOAD_SCRIPT_FULL_PATH="$VISOMASTER_ROOT_DIR/$MODEL_DOWNLOAD_SCRIPT_NAME"
TENSORRT_REQS_FILE="requirements_cu124.txt" # Assuming this file exists in the repo
TENSORRT_REQS_FULL_PATH="$VISOMASTER_ROOT_DIR/$TENSORRT_REQS_FILE"
VENV_PATH="/opt/venv"
LOG_FILE="$PROJECT_PARENT_DIR/onstart_script.log" # Log file location

# Specific Inswapper Model Details
# Updated URL
INSWAPPER_URL="https://huggingface.co/Red1618/Viso/resolve/main/inswapper_128_fp16.onnx?download=true"
DOWNLOADED_INSWAPPER_NAME="inswapper_128_fp16.onnx.download" # Temporary download name
# Assuming the target directory is within the cloned repo structure
TARGET_MODEL_DIR="$VISOMASTER_ROOT_DIR/models" # Adjust if the model path is different
TARGET_INSWAPPER_NAME="inswapper_128_fp16.onnx" # Final name in the target directory

# Directories to create
IMAGES_DIR="$VISOMASTER_ROOT_DIR/Images"
VIDEOS_DIR="$VISOMASTER_ROOT_DIR/Videos"
OUTPUT_DIR="$VISOMASTER_ROOT_DIR/Output"


# --- Setup Logging & Execution ---
# Redirect stdout/stderr to log file and console
exec > >(tee -a "$LOG_FILE") 2> >(tee -a "$LOG_FILE" >&2)
echo "--- Starting Provisioning Script $(date) ---"
echo "--- Logging to $LOG_FILE ---"
# Exit on error, print commands
set -eux

# --- Clone VisoMaster Repository ---
if [ ! -d "$VISOMASTER_ROOT_DIR" ]; then
  echo "Cloning VisoMaster..."
  git clone "$VISOMASTER_REPO_URL" "$VISOMASTER_ROOT_DIR" || exit 1
  echo "Cloned."
else
  echo "VisoMaster directory exists, skipping clone."
  # Optional: Add git pull if needed
  # cd "$VISOMASTER_ROOT_DIR" && git pull origin main || echo "Git pull failed."
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

# --- Download VisoMaster Models ---
echo "Downloading models..."
if [ ! -f "$MODEL_DOWNLOAD_SCRIPT_FULL_PATH" ]; then echo "ERROR: Model download script ($MODEL_DOWNLOAD_SCRIPT_NAME) not found in repo!" >&2; exit 1; fi
# Navigate into the repo directory BEFORE running the script
cd "$VISOMASTER_ROOT_DIR" || { echo "ERROR: Failed to cd to $VISOMASTER_ROOT_DIR!" >&2; exit 1; }
echo "Executing $MODEL_DOWNLOAD_SCRIPT_FULL_PATH from $(pwd)..."
python "$MODEL_DOWNLOAD_SCRIPT_FULL_PATH"
if [ $? -ne 0 ]; then echo "ERROR: download_models.py failed!" >&2; exit 1; fi
echo "Model download finished."

# --- Download and Overwrite Specific Inswapper Model ---
echo "Downloading specific inswapper model from $INSWAPPER_URL..."
# Ensure the target model directory exists (the download script should create it, but check just in case)
mkdir -p "$TARGET_MODEL_DIR" || { echo "ERROR: Failed to create target model directory $TARGET_MODEL_DIR" >&2; exit 1; }
# Download the file using wget to a temporary name in the target directory
# Using --output-document (-O) to specify the output file name
wget -O "$TARGET_MODEL_DIR/$DOWNLOADED_INSWAPPER_NAME" "$INSWAPPER_URL"
if [ $? -ne 0 ]; then echo "ERROR: Failed to download inswapper model!" >&2; exit 1; fi
echo "Inswapper model downloaded."

# Rename the downloaded file to the target name, overwriting if it exists
echo "Renaming/Overwriting $DOWNLOADED_INSWAPPER_NAME to $TARGET_INSWAPPER_NAME in $TARGET_MODEL_DIR..."
# Use mv -f to force overwrite without prompting
mv -f "$TARGET_MODEL_DIR/$DOWNLOADED_INSWAPPER_NAME" "$TARGET_MODEL_DIR/$TARGET_INSWAPPER_NAME"
if [ $? -ne 0 ]; then echo "ERROR: Failed to rename/overwrite inswapper model!" >&2; exit 1; fi
echo "Inswapper model replaced successfully."

# Optional: Deactivate venv
# deactivate

echo "--- Provisioning Script Finished $(date) ---"
# Container ENTRYPOINT will run next.

