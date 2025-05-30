#!/bin/bash

# Change to the primary workspace directory
cd /workspace/
echo "Operating from $(pwd)"

# Cause the script to exit on failure.
set -eo pipefail

# --- Notebook Download Section (operates in /workspace/) ---
# ... (notebook download logic remains the same) ...
NOTEBOOK_URL="https://raw.githubusercontent.com/remphan1618/Red/main/Modelgeddah.ipynb"
OUTPUT_FILENAME="Modelgeddah.ipynb"

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

# --- !!! ADD THIS LINE HERE !!! ---
# Mark the SwarmUI directory as safe for Git operations by the current user
# This resolves "dubious ownership" errors.
echo "Marking ${SWARMUI_DIR} as a safe directory for Git..."
git config --global --add safe.directory "${SWARMUI_DIR}"
# --- !!! END OF ADDED LINE !!! ---

echo "Checking/Updating ${SWARMUI_DIR_BASENAME} (target branch: ${SWARMUI_BRANCH})..."

if [ ! -d "$SWARMUI_DIR/.git" ]; then
    echo "${SWARMUI_DIR_BASENAME} directory at ${SWARMUI_DIR} not found or not a git repository."
    echo "Attempting to clone ${SWARMUI_REPO_URL} (branch ${SWARMUI_BRANCH}) into ${SWARMUI_DIR}..."
    # Note: git clone creates the directory. The safe.directory command above applies
    # if the user running this script differs from a potential future owner,
    # or if parts of the directory structure are pre-existing with different ownership.
    # For a fresh clone into an empty path by the current user, safe.directory might not be strictly
    # needed for the clone itself, but it's good practice for subsequent operations.
    if git clone --branch "${SWARMUI_BRANCH}" --depth 1 "${SWARMUI_REPO_URL}" "${SWARMUI_DIR}"; then
        echo "✅ ${SWARMUI_DIR_BASENAME} cloned successfully into ${SWARMUI_DIR} (branch ${SWARMUI_BRANCH})."
    else
        echo "❌ Error: Failed to clone ${SWARMUI_DIR_BASENAME} from ${SWARMUI_REPO_URL}."
        exit 1
    fi
else
    echo "${SWARMUI_DIR_BASENAME} found at ${SWARMUI_DIR}. Checking for updates on branch '${SWARMUI_BRANCH}'..."
    pushd "$SWARMUI_DIR" > /dev/null
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD) # This was likely the failing command
    echo "Current local branch: ${CURRENT_BRANCH}" # Added for verbosity

    if [ "$CURRENT_BRANCH" != "$SWARMUI_BRANCH" ]; then
        echo "Currently not on branch '${SWARMUI_BRANCH}'. Attempting to checkout '${SWARMUI_BRANCH}'..."
        if ! git checkout "${SWARMUI_BRANCH}"; then
             echo "⚠️ Checkout failed. Attempting to fetch and then checkout..."
             git fetch origin "${SWARMUI_BRANCH}" # Fetch the specific branch
             if ! git checkout "${SWARMUI_BRANCH}"; then
                echo "❌ Failed to checkout branch '${SWARMUI_BRANCH}' even after fetch."
                popd > /dev/null
                exit 1
             fi
        fi
        echo "✅ Successfully checked out branch '${SWARMUI_BRANCH}'."
    fi
    LOCAL_COMMIT_HASH_BEFORE_PULL=$(git rev-parse HEAD)
    git fetch origin --prune # Fetch all updates for origin remote
    REMOTE_COMMIT_HASH=$(git rev-parse "origin/${SWARMUI_BRANCH}")
    if [ "$LOCAL_COMMIT_HASH_BEFORE_PULL" == "$REMOTE_COMMIT_HASH" ]; then
        echo "✅ ${SWARMUI_DIR_BASENAME} (branch ${SWARMUI_BRANCH}) is already up to date."
    else
        echo "Updating ${SWARMUI_DIR_BASENAME} (branch ${SWARMUI_BRANCH})..."
        # Attempt to stash local changes if any, then pull, then pop.
        # This is safer than a hard reset if there are intentional local modifications.
        STASH_NEEDED=$(git status --porcelain | wc -l)
        if [ "$STASH_NEEDED" -gt 0 ]; then
            echo "  Local changes detected. Stashing before pull..."
            git stash push -u -m "autostash_before_update_$(date +%s)"
        fi
        
        if git pull origin "${SWARMUI_BRANCH}"; then
            echo "✅ ${SWARMUI_DIR_BASENAME} updated successfully. New commit: $(git rev-parse HEAD)"
            if [ "$STASH_NEEDED" -gt 0 ]; then
                echo "  Attempting to pop stashed changes..."
                if git stash pop; then
                    echo "  ✅ Stash popped successfully."
                else
                    echo "  ⚠️ Failed to pop stash. Manual conflict resolution might be needed in ${SWARMUI_DIR}."
                fi
            fi
        else
            echo "❌ Error: Failed to pull updates for ${SWARMUI_DIR_BASENAME} (branch ${SWARMUI_BRANCH})."
            if [ "$STASH_NEEDED" -gt 0 ]; then
                 echo "  Pull failed even after stashing. Consider manual intervention or a hard reset if local changes are not important."
            fi
            popd > /dev/null
            exit 1
        fi
    fi
    popd > /dev/null
fi
echo "✅ ${SWARMUI_DIR_BASENAME} check/update process complete."

# --- Modify and Run ComfyUI Installation Script ---
# ... (rest of the script for modifying and running comfy-install-linux.sh remains the same) ...
SWARMUI_COMFY_INSTALL_SCRIPT_RELPATH="launchtools/comfy-install-linux.sh"
SWARMUI_COMFY_INSTALL_SCRIPT_FULLPATH="${SWARMUI_DIR}/${SWARMUI_COMFY_INSTALL_SCRIPT_RELPATH}"

if [ -f "$SWARMUI_COMFY_INSTALL_SCRIPT_FULLPATH" ]; then
    echo "Modifying ${SWARMUI_COMFY_INSTALL_SCRIPT_FULLPATH} to include custom node installation..."
    chmod u+w "$SWARMUI_COMFY_INSTALL_SCRIPT_FULLPATH"
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
    CUSTOM_NODE_INSTALL_LOGIC=$(cat <<EOF

echo ""
echo "--- Starting ComfyUI Custom Node Installation (appended logic) ---"
COMFYUI_BASE_DIR="." 
CUSTOM_NODES_DIR="\${COMFYUI_BASE_DIR}/custom_nodes"
mkdir -p "\${CUSTOM_NODES_DIR}"
echo "Custom nodes will be installed in: \$(readlink -f \${CUSTOM_NODES_DIR})"
echo "Using Python: \$python for node requirements installation."
NODES_TO_INSTALL_BASH_ARRAY_STR="($(printf "'%s' " "${NODES_TO_INSTALL_STR[@]}"))"
eval "declare -a NODES_TO_INSTALL=\${NODES_TO_INSTALL_BASH_ARRAY_STR}"
for NODE_REPO_URL in "\${NODES_TO_INSTALL[@]}"; do
    NODE_DIR_NAME=\$(basename "\${NODE_REPO_URL}" .git)
    NODE_INSTALL_PATH="\${CUSTOM_NODES_DIR}/\${NODE_DIR_NAME}"
    echo ""
    echo "Processing node: \${NODE_DIR_NAME} (from \${NODE_REPO_URL})"
    if [ -d "\${NODE_INSTALL_PATH}/.git" ]; then
        echo "  Updating existing node \${NODE_DIR_NAME}..."
        # Try to stash local changes before pulling
        (cd "\${NODE_INSTALL_PATH}" && git stash push -u -m "autostash_node_\$(date +%s)" >/dev/null 2>&1)
        if (cd "\${NODE_INSTALL_PATH}" && git pull --ff-only); then
             (cd "\${NODE_INSTALL_PATH}" && git stash pop >/dev/null 2>&1 || true) # Try to pop, ignore if no stash or conflicts
        else
            echo "  WARN: Fast-forward pull failed for \${NODE_DIR_NAME}. Trying regular pull..."
            (cd "\${NODE_INSTALL_PATH}" && git pull) || echo "  ERROR: Pull failed for \${NODE_DIR_NAME}."
            (cd "\${NODE_INSTALL_PATH}" && git stash pop >/dev/null 2>&1 || true) # Try to pop anyway
        fi
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
    # Check if the custom logic is already in the script to prevent appending multiple times
    if ! grep -q "--- Starting ComfyUI Custom Node Installation (appended logic) ---" "$SWARMUI_COMFY_INSTALL_SCRIPT_FULLPATH"; then
        printf '%s\n' "$CUSTOM_NODE_INSTALL_LOGIC" >> "$SWARMUI_COMFY_INSTALL_SCRIPT_FULLPATH"
        echo "✅ Appended custom node installation logic to ${SWARMUI_COMFY_INSTALL_SCRIPT_FULLPATH}."
    else
        echo "ℹ️ Custom node installation logic already present in ${SWARMUI_COMFY_INSTALL_SCRIPT_FULLPATH}."
    fi

    GPU_TYPE_FOR_COMFY="nv"
    if ! command -v nvidia-smi &> /dev/null; then
        echo "nvidia-smi not found. Assuming non-NVIDIA or driver issue. Check comfy-install-linux.sh options."
        echo "Warning: Proceeding with GPU_TYPE=${GPU_TYPE_FOR_COMFY} for ComfyUI install."
    else
        echo "nvidia-smi found. Using GPU_TYPE=${GPU_TYPE_FOR_COMFY} for ComfyUI install."
    fi
    echo "Running the modified ${SWARMUI_COMFY_INSTALL_SCRIPT_RELPATH} from ${SWARMUI_DIR} with GPU_TYPE=${GPU_TYPE_FOR_COMFY}..."
    pushd "${SWARMUI_DIR}" > /dev/null
    chmod +x "./${SWARMUI_COMFY_INSTALL_SCRIPT_RELPATH}"
    if ./"${SWARMUI_COMFY_INSTALL_SCRIPT_RELPATH}" "${GPU_TYPE_FOR_COMFY}"; then
        echo "✅ ComfyUI installation (including custom nodes via modified script) appears successful."
    else
        echo "❌ ComfyUI installation (including custom nodes via modified script) failed. Check output above."
        popd > /dev/null
        exit 1
    fi
    popd > /dev/null
else
    echo "⚠️ Warning: ${SWARMUI_COMFY_INSTALL_SCRIPT_FULLPATH} not found."
    echo "   Cannot run ComfyUI automatic installation or install its custom nodes."
    # exit 1 # Consider exiting if ComfyUI is critical
fi

echo ""
echo "Script finished. All operations based in /workspace/ completed."
