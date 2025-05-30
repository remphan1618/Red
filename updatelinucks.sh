#!/bin/bash

# Change to the primary workspace directory
cd /workspace/
echo "Operating from $(pwd)"

# Cause the script to exit on failure.
set -eo pipefail

# --- Notebook Download Section (operates in /workspace/) ---
NOTEBOOK_URL="https://raw.githubusercontent.com/remphan1618/Red/main/Modelgeddah.ipynb"
OUTPUT_FILENAME="Modelgeddah.ipynb" # Will be saved to /workspace/Modelgeddah.ipynb

echo "Downloading ${OUTPUT_FILENAME} from ${NOTEBOOK_URL} to $(pwd)/ ..."
if curl -sSL -o "${OUTPUT_FILENAME}" "${NOTEBOOK_URL}"; then
    echo "✅ Successfully downloaded ${OUTPUT_FILENAME} to $(pwd)/"
else
    echo "❌ Error: Failed to download ${OUTPUT_FILENAME}."
    if command -v wget &> /dev/null; then
        echo "Attempting download with wget..."
        if wget -O "${OUTPUT_FILENAME}" "${NOTEBOOK_URL}"; then
            echo "✅ Successfully downloaded ${OUTPUT_FILENAME} with wget to $(pwd)/"
        else
            echo "❌ Error: Failed to download ${OUTPUT_FILENAME} with wget as well."
            exit 1
        fi
    else
        exit 1
    fi
fi
# --- End Notebook Download Section ---

echo "" # Newline for better log readability

# --- SwarmUI Update and ComfyUI Setup Section ---
SWARMUI_DIR_BASENAME="SwarmUI"
SWARMUI_DIR="/workspace/${SWARMUI_DIR_BASENAME}" # Full path: /workspace/SwarmUI
SWARMUI_REPO_URL="https://github.com/mcmonkeyprojects/SwarmUI.git"
SWARMUI_BRANCH="master"

echo "Checking/Updating ${SWARMUI_DIR_BASENAME} (target branch: ${SWARMUI_BRANCH})..."

if [ ! -d "$SWARMUI_DIR/.git" ]; then
    echo "${SWARMUI_DIR_BASENAME} directory at ${SWARMUI_DIR} not found or not a git repository."
    echo "Attempting to clone ${SWARMUI_REPO_URL} (branch ${SWARMUI_BRANCH}) into ${SWARMUI_DIR}..."
    if git clone --branch "${SWARMUI_BRANCH}" --depth 1 "${SWARMUI_REPO_URL}" "${SWARMUI_DIR}"; then
        echo "✅ ${SWARMUI_DIR_BASENAME} cloned successfully into ${SWARMUI_DIR} (branch ${SWARMUI_BRANCH})."
    else
        echo "❌ Error: Failed to clone ${SWARMUI_DIR_BASENAME} from ${SWARMUI_REPO_URL}."
        exit 1
    fi
else
    echo "${SWARMUI_DIR_BASENAME} found at ${SWARMUI_DIR}. Checking for updates on branch '${SWARMUI_BRANCH}'..."
    pushd "$SWARMUI_DIR" > /dev/null
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
    if [ "$CURRENT_BRANCH" != "$SWARMUI_BRANCH" ]; then
        echo "Currently not on branch '${SWARMUI_BRANCH}'. Attempting to checkout '${SWARMUI_BRANCH}'..."
        if ! git checkout "${SWARMUI_BRANCH}"; then
             echo "⚠️ Checkout failed. Attempting to fetch and then checkout..."
             git fetch origin "${SWARMUI_BRANCH}"
             if ! git checkout "${SWARMUI_BRANCH}"; then
                echo "❌ Failed to checkout branch '${SWARMUI_BRANCH}' even after fetch."
                popd > /dev/null
                exit 1
             fi
        fi
        echo "✅ Successfully checked out branch '${SWARMUI_BRANCH}'."
    fi
    LOCAL_COMMIT_HASH_BEFORE_PULL=$(git rev-parse HEAD)
    git fetch origin --prune
    REMOTE_COMMIT_HASH=$(git rev-parse "origin/${SWARMUI_BRANCH}")
    if [ "$LOCAL_COMMIT_HASH_BEFORE_PULL" == "$REMOTE_COMMIT_HASH" ]; then
        echo "✅ ${SWARMUI_DIR_BASENAME} (branch ${SWARMUI_BRANCH}) is already up to date."
    else
        echo "Updating ${SWARMUI_DIR_BASENAME} (branch ${SWARMUI_BRANCH})..."
        if git pull origin "${SWARMUI_BRANCH}"; then
            echo "✅ ${SWARMUI_DIR_BASENAME} updated successfully. New commit: $(git rev-parse HEAD)"
        else
            echo "❌ Error: Failed to pull updates for ${SWARMUI_DIR_BASENAME} (branch ${SWARMUI_BRANCH})."
            popd > /dev/null
            exit 1
        fi
    fi
    popd > /dev/null
fi
echo "✅ ${SWARMUI_DIR_BASENAME} check/update process complete."

# --- Modify and Run ComfyUI Installation Script ---
SWARMUI_COMFY_INSTALL_SCRIPT_RELPATH="launchtools/comfy-install-linux.sh"
SWARMUI_COMFY_INSTALL_SCRIPT_FULLPATH="${SWARMUI_DIR}/${SWARMUI_COMFY_INSTALL_SCRIPT_RELPATH}"

if [ -f "$SWARMUI_COMFY_INSTALL_SCRIPT_FULLPATH" ]; then
    echo "Modifying ${SWARMUI_COMFY_INSTALL_SCRIPT_FULLPATH} to include custom node installation..."

    # Ensure the script is writable
    chmod u+w "$SWARMUI_COMFY_INSTALL_SCRIPT_FULLPATH"

    # Define the ComfyUI Custom Nodes to install
    # This list is taken from your notebook
    # Important: Ensure proper quoting for array elements if they contain spaces or special chars
    NODES_TO_INSTALL_STR=(
        "https://github.com/Comfy-Org/ComfyUI-Manager"
        "https://github.com/kijai/ComfyUI-KJNodes"
        "https://github.com/aria1th/ComfyUI-LogicUtils"
        "https://github.com/crystian/ComfyUI-Crystools"
        "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite"
        "https://github.com/rgthree/rgthree-comfy"
        "https://github.com/calcuis/gguf"
        "https://github.com/city96/ComfyUI-GGUF"
    )

    # Create the shell script content to append
    # This will be executed *within* comfy-install-linux.sh,
    # so it will be in the ComfyUI directory and have $python (venv or system) available.
    CUSTOM_NODE_INSTALL_LOGIC=$(cat <<EOF

echo ""
echo "--- Starting ComfyUI Custom Node Installation (appended logic) ---"
# We are already in the ComfyUI directory at this point in comfy-install-linux.sh
COMFYUI_BASE_DIR="." 
CUSTOM_NODES_DIR="\${COMFYUI_BASE_DIR}/custom_nodes"
mkdir -p "\${CUSTOM_NODES_DIR}"

echo "Custom nodes will be installed in: \$(readlink -f \${CUSTOM_NODES_DIR})"
echo "Using Python: \$python for node requirements installation."

# Convert NODES_TO_INSTALL_STR to a bash array here to avoid issues with here-doc expansion
NODES_TO_INSTALL_BASH_ARRAY_STR="($(printf "'%s' " "${NODES_TO_INSTALL_STR[@]}"))"
eval "declare -a NODES_TO_INSTALL=\${NODES_TO_INSTALL_BASH_ARRAY_STR}"


for NODE_REPO_URL in "\${NODES_TO_INSTALL[@]}"; do
    NODE_DIR_NAME=\$(basename "\${NODE_REPO_URL}" .git)
    NODE_INSTALL_PATH="\${CUSTOM_NODES_DIR}/\${NODE_DIR_NAME}"

    echo ""
    echo "Processing node: \${NODE_DIR_NAME} (from \${NODE_REPO_URL})"
    if [ -d "\${NODE_INSTALL_PATH}/.git" ]; then
        echo "  Updating existing node \${NODE_DIR_NAME}..."
        (cd "\${NODE_INSTALL_PATH}" && git reset --hard HEAD && git pull --ff-only) || (echo "  WARN: Pull failed for \${NODE_DIR_NAME}, might have local changes. Trying to continue." && (cd "\${NODE_INSTALL_PATH}" && git pull))
    else
        echo "  Cloning new node \${NODE_DIR_NAME}..."
        git clone --recursive "\${NODE_REPO_URL}" "\${NODE_INSTALL_PATH}"
    fi

    REQUIREMENTS_FILE="\${NODE_INSTALL_PATH}/requirements.txt"
    if [ -f "\${REQUIREMENTS_FILE}" ]; then
        echo "  Installing requirements for \${NODE_DIR_NAME} from \${REQUIREMENTS_FILE}..."
        if \$python -s -m pip install -r "\${REQUIREMENTS_FILE}"; then
            echo "  ✅ Requirements installed for \${NODE_DIR_NAME}."
        else
            echo "  ❌ Failed to install requirements for \${NODE_DIR_NAME}."
        fi
    else
        echo "  No requirements.txt found for \${NODE_DIR_NAME}."
    fi
    echo "  Finished processing \${NODE_DIR_NAME}."
done

echo "--- ComfyUI Custom Node Installation Finished ---"
echo ""
EOF
)
    # Append the logic. Use printf to avoid issues with '%' in the logic.
    printf '%s\n' "$CUSTOM_NODE_INSTALL_LOGIC" >> "$SWARMUI_COMFY_INSTALL_SCRIPT_FULLPATH"
    echo "✅ Modification of ${SWARMUI_COMFY_INSTALL_SCRIPT_FULLPATH} complete."

    # Determine GPU type for ComfyUI installation
    # For Vast.ai, 'nv' (NVIDIA) is extremely common.
    # If you might use AMD, you'll need a more dynamic detection.
    GPU_TYPE_FOR_COMFY="nv"
    if ! command -v nvidia-smi &> /dev/null; then
        echo "nvidia-smi not found, assuming AMD or CPU. Check comfy-install-linux.sh for options."
        # Potentially set GPU_TYPE_FOR_COMFY="amd" or handle CPU-only if script supports
        # For now, we will proceed with 'nv' if nvidia-smi is absent, but log a warning.
        # The comfy-install-linux.sh script itself has better error handling for invalid GPU types.
        echo "Warning: Proceeding with GPU_TYPE=${GPU_TYPE_FOR_COMFY} for ComfyUI install, but nvidia-smi was not found."
    else
        echo "nvidia-smi found. Using GPU_TYPE=${GPU_TYPE_FOR_COMFY} for ComfyUI install."
    fi

    echo "Running the modified ${SWARMUI_COMFY_INSTALL_SCRIPT_RELPATH} from ${SWARMUI_DIR} with GPU_TYPE=${GPU_TYPE_FOR_COMFY}..."
    
    # The comfy-install-linux.sh script internally cds to dlbackend and then ComfyUI.
    # It should be run from the SwarmUI base directory.
    pushd "${SWARMUI_DIR}" > /dev/null
    chmod +x "./${SWARMUI_COMFY_INSTALL_SCRIPT_RELPATH}" # Ensure it's executable
    
    if ./"${SWARMUI_COMFY_INSTALL_SCRIPT_RELPATH}" "${GPU_TYPE_FOR_COMFY}"; then
        echo "✅ ComfyUI installation (including custom nodes via modified script) appears successful."
    else
        echo "❌ ComfyUI installation (including custom nodes via modified script) failed. Check output above."
        # It's important that comfy-install-linux.sh also uses set -e or exits on failure
        # for this error code to propagate correctly.
        popd > /dev/null
        exit 1
    fi
    popd > /dev/null
else
    echo "⚠️ Warning: ${SWARMUI_COMFY_INSTALL_SCRIPT_FULLPATH} not found."
    echo "   Cannot run ComfyUI automatic installation or install its custom nodes."
    echo "   SwarmUI might not function correctly without ComfyUI backend."
    # Depending on your needs, you might want to exit 1 here if ComfyUI is essential.
    # exit 1
fi
# --- End SwarmUI ComfyUI Setup ---


echo ""
echo "Script finished. All operations based in /workspace/ completed."
# The script will now exit.
