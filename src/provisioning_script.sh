    #!/bin/bash
    # This script clones the repo, activates venv, installs TensorRT, and downloads models.
    # It's intended to be copied into the Docker image and run via the Vast.ai On-Start field.

    # --- Define Paths and Variables ---
    PROJECT_PARENT_DIR="/root"
    VISOMASTER_REPO_NAME="VisoMaster"
    VISOMASTER_ROOT_DIR="$PROJECT_PARENT_DIR/$VISOMASTER_REPO_NAME"
    VISOMASTER_REPO_URL="https://github.com/remphan1618/VisoMaster.git"
    MODEL_DOWNLOAD_SCRIPT_NAME="download_models.py"
    MODEL_DOWNLOAD_SCRIPT_FULL_PATH="$VISOMASTER_ROOT_DIR/$MODEL_DOWNLOAD_SCRIPT_NAME"
    TENSORRT_REQS_FILE="requirements_cu124.txt"
    TENSORRT_REQS_FULL_PATH="$VISOMASTER_ROOT_DIR/$TENSORRT_REQS_FILE"
    VENV_PATH="/opt/venv"
    LOG_FILE="$PROJECT_PARENT_DIR/onstart_script.log" # Log file location

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
    cd "$VISOMASTER_ROOT_DIR" || { echo "ERROR: Failed to cd to $VISOMASTER_ROOT_DIR!" >&2; exit 1; }
    echo "Executing $MODEL_DOWNLOAD_SCRIPT_FULL_PATH..."
    python "$MODEL_DOWNLOAD_SCRIPT_FULL_PATH"
    if [ $? -ne 0 ]; then echo "ERROR: download_models.py failed!" >&2; exit 1; fi
    echo "Model download finished."

    # Optional: Deactivate venv
    # deactivate

    echo "--- Provisioning Script Finished $(date) ---"
    # Container ENTRYPOINT will run next.
    
