#!/bin/bash
# This script is for the Vast.ai On-start Script field.
# It runs inside the container *after* it has started and *before* the main ENTRYPOINT.
# Assumes the Dockerfile has already installed all prerequisites and cloned the repo.
# This script installs TensorRT from a requirements file and downloads the VisoMaster models.

# Exit immediately if a command exits with a non-zero status.
# Print commands and their arguments as they are executed.
set -eux # u: treat unset variables as error, x: print commands

echo "--- Running Vast.ai On-Start Script (Model Download + TensorRT Install) ---"

# Define the root directory of the VisoMaster project
# Ensure this matches the location where the Dockerfile cloned the repo
VISOMASTER_ROOT_DIR="/workspace/VisoMaster"
MODEL_DOWNLOAD_SCRIPT_NAME="download_models.py" # Assuming script is in the root of the repo
MODEL_DOWNLOAD_SCRIPT_FULL_PATH="$VISOMASTER_ROOT_DIR/$MODEL_DOWNLOAD_SCRIPT_NAME"
TENSORRT_REQS_FILE="requirements_cu124.txt" # File containing TensorRT packages
TENSORRT_REQS_FULL_PATH="$VISOMASTER_ROOT_DIR/$TENSORRT_REQS_FILE"

# --- Activate Conda Environment ---
# Ensure conda is initialized for bash scripts
# The conda environment name should match the one created in the Dockerfile
CONDA_ENV_NAME="visomaster"
echo "Activating Conda environment: $CONDA_ENV_NAME"
# Source conda.sh to make 'conda activate' available if not already initialized
# The path might vary slightly depending on Miniconda installation details
if [ -f "/opt/conda/etc/profile.d/conda.sh" ]; then
    source "/opt/conda/etc/profile.d/conda.sh"
else
    echo "Warning: Conda profile script not found at /opt/conda/etc/profile.d/conda.sh"
    # Attempt common alternative if needed
    # if [ -f "$HOME/miniconda3/etc/profile.d/conda.sh" ]; then
    #     source "$HOME/miniconda3/etc/profile.d/conda.sh"
    # fi
fi
conda activate "$CONDA_ENV_NAME"
# Verify activation (optional)
echo "Current Python executable: $(which python)"
echo "Current Conda environment: $CONDA_DEFAULT_ENV"

# --- Install TensorRT ---
echo "Installing TensorRT from $TENSORRT_REQS_FULL_PATH..."
# Check if the TensorRT requirements file exists
if [ ! -f "$TENSORRT_REQS_FULL_PATH" ]; then
    echo "Error: TensorRT requirements file not found at $TENSORRT_REQS_FULL_PATH."
    exit 1
fi
# Install using pip from the requirements file
# Running from the root directory, but specifying the full path to the file
pip install -r "$TENSORRT_REQS_FULL_PATH" --no-cache-dir

echo "TensorRT installation finished."

# --- Download VisoMaster Models ---
echo "Starting VisoMaster model download process..."
# Check if the VisoMaster directory exists
if [ ! -d "$VISOMASTER_ROOT_DIR" ]; then
  echo "Error: VisoMaster project directory not found at $VISOMASTER_ROOT_DIR."
  echo "Ensure the Dockerfile cloned the repository correctly."
  exit 1
fi

# Check if the download script exists
# Note: The Dockerfile WORKDIR is /workspace/VisoMaster, so the script should be there.
if [ ! -f "$MODEL_DOWNLOAD_SCRIPT_FULL_PATH" ]; then
    echo "Error: $MODEL_DOWNLOAD_SCRIPT_NAME script not found at $MODEL_DOWNLOAD_SCRIPT_FULL_PATH."
    exit 1
fi

# Navigate to the root of the VisoMaster project
# Running the script from the repo root is often necessary for correct imports.
echo "Changing directory to $VISOMASTER_ROOT_DIR to execute model download script"
cd "$VISOMASTER_ROOT_DIR" || { echo "Failed to change directory to $VISOMASTER_ROOT_DIR!"; exit 1; }

# Execute the Python script to download the models
# Use the determined full path to the script
echo "Executing $MODEL_DOWNLOAD_SCRIPT_FULL_PATH from $(pwd)..."
# Ensure python3 refers to the correct version installed in the Dockerfile (python3.10 via Conda)
python3 "$MODEL_DOWNLOAD_SCRIPT_FULL_PATH"

# Check the exit status of the python script
if [ $? -eq 0 ]; then
  echo "download_models.py executed successfully."
else
  echo "Error: download_models.py failed."
  # Decide if failure should stop container startup. Exit 1 will likely terminate.
  exit 1
fi

echo "VisoMaster model download process finished."

# --- Deactivate Conda Environment (Optional) ---
# conda deactivate

echo "--- On-Start Script Finished ---"

# The container's ENTRYPOINT (/dockerstartup/vnc_startup.sh) will run after this script completes.
