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

# Mark the SwarmUI directory as safe for Git operations by the current user
# This resolves "dubious ownership" errors, especially if the directory might exist with different ownership.
echo "Marking ${SWARMUI_DIR} as a safe directory for Git..."
# Create .gitconfig if it doesn't exist, as `git config --global` might fail otherwise in some minimal environments
mkdir -p ~/.config/git # Common location, though git might use ~/.gitconfig directly
touch ~/.gitconfig
git config --global --add safe.directory "${SWARMUI_DIR}"

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
    echo "Current local branch in ${SWARMUI_DIR}: ${CURRENT_BRANCH}"

    if [ "$CURRENT_BRANCH" != "$SWARMUI_BRANCH" ]; then
        echo "Currently not on branch '${SWARMUI_BRANCH}'. Attempting to checkout '${SWARMUI_BRANCH}'..."
        # Try to checkout the branch. If it doesn't exist locally, fetch it and then checkout.
        if ! git checkout "${SWARMUI_BRANCH}" 2>/dev/null; then
             echo "  Local branch '${SWARMUI_BRANCH}' not found or checkout failed. Fetching from origin..."
             git fetch origin "${SWARMUI_BRANCH}:${SWARMUI_BRANCH}" # Fetch and create local tracking branch
             if ! git checkout "${SWARMUI_BRANCH}"; then
                echo "❌ Failed to checkout branch '${SWARMUI_BRANCH}' even after fetch."
                popd > /dev/null
                exit 1
             fi
        fi
        echo "✅ Successfully checked out branch '${SWARMUI_BRANCH}'."
    fi
    
    LOCAL_COMMIT_HASH_BEFORE_PULL=$(git rev-parse HEAD)
    echo "Fetching latest changes from remote 'origin' for ${SWARMUI_DIR_BASENAME}..."
    git fetch origin --prune # Fetch updates for the 'origin' remote and prune stale branches
    REMOTE_COMMIT_HASH=$(git rev-parse "origin/${SWARMUI_BRANCH}")

    if [ "$LOCAL_COMMIT_HASH_BEFORE_PULL" == "$REMOTE_COMMIT_HASH" ]; then
        echo "✅ ${SWARMUI_DIR_BASENAME} (branch ${SWARMUI_BRANCH}) is already up to date."
    else
        echo "Updating ${SWARMUI_DIR_BASENAME} (branch ${SWARMUI_BRANCH})..."
        STASH_NEEDED=$(git status --porcelain | wc -l)
        if [ "$STASH_NEEDED" -gt 0 ]; then
            echo "  Local changes detected in ${SWARMUI_DIR}. Stashing before pull..."
            git stash push -u -m "autostash_swarmui_update_$(date +%s)"
        fi
        
        if git pull origin "${SWARMUI_BRANCH}"; then
            echo "✅ ${SWARMUI_DIR_BASENAME} updated successfully. New commit: $(git rev-parse HEAD)"
            if [ "$STASH_NEEDED" -gt 0 ]; then
                echo "  Attempting to pop stashed changes in ${SWARMUI_DIR}..."
                if git stash pop; then
                    echo "  ✅ Stash popped successfully."
                else
                    echo "  ⚠️ Failed to pop stash in ${SWARMUI_DIR}. Manual conflict resolution might be needed."
                fi
            fi
        else
            echo "❌ Error: Failed to pull updates for ${SWARMUI_DIR_BASENAME} (branch ${SWARMUI_BRANCH})."
            if [ "$STASH_NEEDED" -gt 0 ]; then
                 echo "  Pull failed. Stashed changes (if any) are still saved. Consider manual intervention or a hard reset if local changes are not important."
                 echo "  To view stashes: git stash list"
                 echo "  To apply latest stash (after resolving pull issue): git stash pop"
                 echo "  To discard latest stash: git stash drop"
            fi
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
    echo "Ensuring ${SWARMUI_COMFY_INSTALL_SCRIPT_FULLPATH} is writable and executable..."
    chmod u+w "$SWARMUI_COMFY_INSTALL_SCRIPT_FULLPATH"
    chmod +x "$SWARMUI_COMFY_INSTALL_SCRIPT_FULLPATH" # Ensure original script is executable

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

    CUSTOM_NODE_INSTALL_LOGIC_MARKER="--- Starting ComfyUI Custom Node Installation (appended logic) ---"

    # Check if the custom logic is already in the script to prevent appending multiple times
    if ! grep -qF "$CUSTOM_NODE_INSTALL_LOGIC_MARKER" "$SWARMUI_COMFY_INSTALL_SCRIPT_FULLPATH"; then
        echo "Custom node installation logic not found in ${SWARMUI_COMFY_INSTALL_SCRIPT_FULLPATH}. Appending..."
        
        CUSTOM_NODE_INSTALL_LOGIC=$(cat <<EOF

echo ""
echo "$CUSTOM_NODE_INSTALL_LOGIC_MARKER"
# We are already in the ComfyUI directory (e.g., dlbackend/ComfyUI) at this point in comfy-install-linux.sh
COMFYUI_BASE_DIR="\$(pwd)" # Use current directory as ComfyUI base
CUSTOM_NODES_DIR="\${COMFYUI_BASE_DIR}/custom_nodes"
mkdir -p "\${CUSTOM_NODES_DIR}"

echo "Custom nodes will be installed in: \${CUSTOM_NODES_DIR}"
echo "Using Python: \$python for node requirements installation."

# Convert NODES_TO_INSTALL_STR to a bash array here
# Note: This array definition is now part of the HEREDOC and will be evaluated by comfy-install-linux.sh
declare -a NODES_TO_INSTALL_BASH_ARRAY=($(printf "'%s' " "${NODES_TO_INSTALL_STR[@]}"))

for NODE_REPO_URL in "\${NODES_TO_INSTALL_BASH_ARRAY[@]}"; do
    NODE_DIR_NAME=\$(basename "\${NODE_REPO_URL}" .git)
    NODE_INSTALL_PATH="\${CUSTOM_NODES_DIR}/\${NODE_DIR_NAME}"

    echo ""
    echo "Processing node: \${NODE_DIR_NAME} (from \${NODE_REPO_URL})"
    if [ -d "\${NODE_INSTALL_PATH}/.git" ]; then
        echo "  Updating existing node \${NODE_DIR_NAME}..."
        (cd "\${NODE_INSTALL_PATH}" && git stash push -u -m "autostash_node_\$(basename \${NODE_INSTALL_PATH})_\$(date +%s)" >/dev/null 2>&1)
        if (cd "\${NODE_INSTALL_PATH}" && git pull --ff-only); then
             (cd "\${NODE_INSTALL_PATH}" && git stash pop >/dev/null 2>&1 || true) 
        else
            echo "  WARN: Fast-forward pull failed for \${NODE_DIR_NAME}. Trying regular pull..."
            (cd "\${NODE_INSTALL_PATH}" && git pull) || echo "  ERROR: Pull failed for \${NODE_DIR_NAME}."
            (cd "\${NODE_INSTALL_PATH}" && git stash pop >/dev/null 2>&1 || true) 
        fi
    else
        if [ -d "\${NODE_INSTALL_PATH}" ]; then
             echo "  WARN: Directory \${NODE_INSTALL_PATH} exists but is not a git repo. Skipping."
        else
            echo "  Cloning new node \${NODE_DIR_NAME}..."
            git clone --recursive "\${NODE_REPO_URL}" "\${NODE_INSTALL_PATH}"
        fi
    fi

    # Proceed with requirements only if the node path exists and is a directory (after clone/pull attempt)
    if [ -d "\${NODE_INSTALL_PATH}" ]; then
        REQUIREMENTS_FILE="\${NODE_INSTALL_PATH}/requirements.txt"
        if [ -f "\${REQUIREMENTS_FILE}" ]; then
            echo "  Installing requirements for \${NODE_DIR_NAME} from \${REQUIREMENTS_FILE}..."
            # Use the python executable defined by comfy-install-linux.sh
            if \$python -s -m pip install --no-cache-dir -r "\${REQUIREMENTS_FILE}"; then
                echo "  ✅ Requirements installed for \${NODE_DIR_NAME}."
            else
                echo "  ❌ Failed to install requirements for \${NODE_DIR_NAME}."
            fi
        else
            echo "  No requirements.txt found for \${NODE_DIR_NAME}."
        fi
    else
        echo "  WARN: Node directory \${NODE_INSTALL_PATH} not found after clone/pull attempt. Skipping requirements."
    fi
    echo "  Finished processing \${NODE_DIR_NAME}."
done

echo "--- ComfyUI Custom Node Installation Finished ---"
echo ""
EOF
)
        # Append the logic. Use printf to avoid issues with '%' in the logic.
        printf '%s\n' "$CUSTOM_NODE_INSTALL_LOGIC" >> "$SWARMUI_COMFY_INSTALL_SCRIPT_FULLPATH"
        echo "✅ Appended custom node installation logic to ${SWARMUI_COMFY_INSTALL_SCRIPT_FULLPATH}."
    else
        echo "ℹ️ Custom node installation logic (marker: '$CUSTOM_NODE_INSTALL_LOGIC_MARKER') already present in ${SWARMUI_COMFY_INSTALL_SCRIPT_FULLPATH}."
    fi

    GPU_TYPE_FOR_COMFY="nv" # Default for Vast.ai NVIDIA instances
    if ! command -v nvidia-smi &> /dev/null; then
        echo "nvidia-smi not found. This could mean it's an AMD GPU, CPU-only instance, or NVIDIA drivers are not (yet) loaded."
        echo "The comfy-install-linux.sh script itself has GPU type validation."
        echo "Proceeding with default GPU_TYPE=${GPU_TYPE_FOR_COMFY} for ComfyUI install."
    else
        echo "nvidia-smi found. Using GPU_TYPE=${GPU_TYPE_FOR_COMFY} for ComfyUI install."
    fi

    echo "Running the modified ${SWARMUI_COMFY_INSTALL_SCRIPT_RELPATH} from ${SWARMUI_DIR} with GPU_TYPE=${GPU_TYPE_FOR_COMFY}..."
    
    pushd "${SWARMUI_DIR}" > /dev/null
    # The comfy-install-linux.sh script is expected to be run from SwarmUI's base directory.
    # It handles cd'ing into dlbackend/ComfyUI itself.
    if ./"${SWARMUI_COMFY_INSTALL_SCRIPT_RELPATH}" "${GPU_TYPE_FOR_COMFY}"; then
        echo "✅ ComfyUI installation (including custom nodes via modified script) appears successful."
    else
        echo "❌ ComfyUI installation (including custom nodes via modified script) failed. Check output above."
        popd > /dev/null
        exit 1
    fi
    popd > /dev/null
else
    echo "⚠️ Critical Warning: ${SWARMUI_COMFY_INSTALL_SCRIPT_FULLPATH} not found."
    echo "   Cannot run ComfyUI automatic installation or install its custom nodes."
    echo "   SwarmUI will likely not function correctly without the ComfyUI backend."
    exit 1 # Exiting because ComfyUI setup is critical for SwarmUI
fi
# --- End SwarmUI ComfyUI Setup ---

echo ""
echo "Provisioning script finished. All operations based in /workspace/ completed."
# The script will now exit. Other services (like Jupyter, Caddy) will be started by supervisor or other means.
