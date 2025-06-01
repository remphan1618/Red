#!/bin/bash

source /venv/main/bin/activate
export PYTHONUTF8=1
export PYTHONIOENCODING=utf-8
COMFYUI_DIR=${WORKSPACE}/ComfyUI

# Packages are installed after nodes so we can fix them...
# Corrected order: Core PIP packages first, then nodes, then specific node requirements.

APT_PACKAGES=(
    #"package-1" # e.g., build-essential, cmake if needed by some pip packages from source
    #"package-2"
)

PIP_PACKAGES=(
    "-U --pre triton"
    "sageattention==1.0.6"
    "torch==2.8.0.dev20250507+cu128 torchvision==0.22.0.dev20250508+cu128 torchaudio --index-url https://download.pytorch.org/whl/nightly/cu128 --force-reinstall"
    #"package-1" # Other general pip packages
    #"package-2"
)

NODES=(
    "https://github.com/ltdrdata/ComfyUI-Manager"
    "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite"
    "https://github.com/kijai/ComfyUI-KJNodes"
    "https://github.com/cubiq/ComfyUI_essentials"
    "https://github.com/Fannovel16/ComfyUI-Frame-Interpolation"
    "https://github.com/pollockjj/ComfyUI-MultiGPU"
    "https://github.com/asagi4/ComfyUI-Adaptive-Guidance"
    "https://github.com/city96/ComfyUI-GGUF"
    "https://github.com/kijai/ComfyUI-WanVideoWrapper"
    "https://github.com/aria1th/ComfyUI-LogicUtils"
    "https://github.com/rgthree/rgthree-comfy"
    "https://github.com/crystian/ComfyUI-Crystools"
    #"https://github.com/other/node" # Add other ComfyUI nodes here
)

WORKFLOWS=(

)

CHECKPOINT_MODELS=(
    # Add other checkpoint model URLs here
)

UNET_MODELS=(
)

LORA_MODELS=(
)

VAE_MODELS=(
)

ESRGAN_MODELS=(
)

CONTROLNET_MODELS=(
)

### DO NOT EDIT BELOW HERE UNLESS YOU KNOW WHAT YOU ARE DOING ###

function provisioning_start() {
    provisioning_print_header
    provisioning_get_apt_packages   # System-level packages
    provisioning_get_pip_packages   # Core Python packages (PyTorch, Triton, etc.)
    provisioning_get_nodes          # ComfyUI custom nodes and their standard requirements.txt

    # Install specific requirements for ComfyUI-Frame-Interpolation (requirements-with-cupy.txt)
    # This runs after provisioning_get_nodes, which would have installed its regular requirements.txt (if present)
    local frame_interp_req_cupy="${COMFYUI_DIR}/custom_nodes/ComfyUI-Frame-Interpolation/requirements-with-cupy.txt"
    if [[ -f "$frame_interp_req_cupy" ]]; then
        printf "Installing ComfyUI-Frame-Interpolation requirements (with cupy)...\n"
        python -m pip install --no-cache-dir -r "$frame_interp_req_cupy"
    fi
    
    # Download models and other files
    provisioning_get_files \
        "${COMFYUI_DIR}/models/checkpoints" \
        "${CHECKPOINT_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/unet" \
        "${UNET_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/loras" \
        "${LORA_MODELS[@]}" # Corrected path from lora to loras if that's ComfyUI standard
    provisioning_get_files \
        "${COMFYUI_DIR}/models/controlnet" \
        "${CONTROLNET_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/vae" \
        "${VAE_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/esrgan" \
        "${ESRGAN_MODELS[@]}"
    provisioning_print_end
}

function provisioning_get_apt_packages() {
    if [[ ${#APT_PACKAGES[@]} -gt 0 ]]; then # Check if array has elements
        echo "Updating apt and installing APT packages: ${APT_PACKAGES[*]}..."
        sudo apt-get update && sudo apt-get install -y ${APT_PACKAGES[@]}
    fi
}

function provisioning_get_pip_packages() {
    if [[ ${#PIP_PACKAGES[@]} -gt 0 ]]; then # Check if array has elements
        echo "Installing PIP packages: ${PIP_PACKAGES[*]}..."
        # Loop and install one by one to handle complex arguments in strings
        for package_string in "${PIP_PACKAGES[@]}"; do
            echo "Installing: $package_string"
            # Using eval here is generally risky but might be necessary if package_string contains shell metacharacters
            # or complex options not handled well by direct array expansion into pip.
            # A safer approach if no complex shell interpretation is needed per string:
            # python -m pip install --no-cache-dir $package_string (this splits package_string by spaces)
            # For strings like "torch==X torchvision==Y --index-url Z", this works fine.
            python -m pip install --no-cache-dir $package_string
        done
    fi
}

function provisioning_get_nodes() {
    for repo in "${NODES[@]}"; do
        # Extract dir name from repo URL (e.g., ComfyUI-Manager from https://github.com/ltdrdata/ComfyUI-Manager)
        # More robustly handles .git suffix if present, though not typical for NODES array here.
        dir_name=$(basename "${repo}" .git)
        path="${COMFYUI_DIR}/custom_nodes/${dir_name}"
        requirements="${path}/requirements.txt"

        if [[ -d $path ]]; then
            if [[ ${AUTO_UPDATE,,} != "false" ]]; then # Assuming AUTO_UPDATE is an env var
                printf "Updating node: %s...\n" "${repo}"
                ( cd "$path" && git pull )
                if [[ -e $requirements ]]; then
                   printf "Installing requirements for %s...\n" "${dir_name}"
                   python -m pip install --no-cache-dir -r "$requirements"
                fi
            fi
        else
            printf "Downloading node: %s...\n" "${repo}"
            git clone "${repo}" "${path}" --recursive
            if [[ -e $requirements ]]; then
                printf "Installing requirements for %s...\n" "${dir_name}"
                python -m pip install --no-cache-dir -r "${requirements}"
            fi
        fi
    done
}

function provisioning_get_files() {
    if [[ -z $2 ]]; then return 1; fi
    
    dir="$1"
    mkdir -p "$dir"
    shift
    arr=("$@")
    if [[ ${#arr[@]} -eq 0 ]]; then return 0; fi # No files to download
    printf "Downloading %s model(s) to %s...\n" "${#arr[@]}" "$dir"
    for url in "${arr[@]}"; do
        printf "Downloading: %s\n" "${url}"
        provisioning_download "${url}" "${dir}"
        printf "\n"
    done
}

function provisioning_print_header() {
    printf "\n##############################################\n#                                            #\n#          Provisioning container            #\n#                                            #\n#         This will take some time           #\n#                                            #\n# Your container will be ready on completion #\n#                                            #\n##############################################\n\n"
}

function provisioning_print_end() {
    printf "\nProvisioning complete:  Application will start now\n\n"
}

# (Keep provisioning_has_valid_hf_token, provisioning_has_valid_civitai_token, and provisioning_download functions as they are)
function provisioning_has_valid_hf_token() {
    [[ -n "$HF_TOKEN" ]] || return 1
    url="https://huggingface.co/api/whoami-v2"

    response=$(curl -o /dev/null -s -w "%{http_code}" -X GET "$url" \
        -H "Authorization: Bearer $HF_TOKEN" \
        -H "Content-Type: application/json")

    if [ "$response" -eq 200 ]; then
        return 0
    else
        return 1
    fi
}

function provisioning_has_valid_civitai_token() {
    [[ -n "$CIVITAI_TOKEN" ]] || return 1
    url="https://civitai.com/api/v1/models?hidden=1&limit=1"

    response=$(curl -o /dev/null -s -w "%{http_code}" -X GET "$url" \
        -H "Authorization: Bearer $CIVITAI_TOKEN" \
        -H "Content-Type: application/json")

    if [ "$response" -eq 200 ]; then
        return 0
    else
        return 1
    fi
}

function provisioning_download() {
    local url="$1"
    local dir="$2"
    local dotbytes="${3:-4M}"
    local auth_header=""

    if [[ -n $HF_TOKEN && $url =~ ^https://([a-zA-Z0-9_-]+\.)?huggingface\.co(/|$|\?) ]]; then
        auth_header="--header=Authorization: Bearer $HF_TOKEN"
    elif [[ -n $CIVITAI_TOKEN && $url =~ ^https://([a-zA-Z0-9_-]+\.)?civitai\.com(/|$|\?) ]]; then
        auth_header="--header=Authorization: Bearer $CIVITAI_TOKEN"
    fi

    # Use aria2c if available, otherwise wget
    if command -v aria2c &> /dev/null; then
        printf "Using aria2c for download...\n"
        aria2c --console-log-level=error -c -x 16 -s 16 -k 1M ${auth_header} -d "$dir" -o "$(basename "$url" | sed 's/\?.*//')" "$url"
    else
        printf "Using wget for download...\n"
        # The auth_header variable needs to be passed to wget carefully.
        # If auth_header is empty, it should not pass an empty --header.
        if [[ -n "$auth_header" ]]; then
            wget $auth_header -qnc --content-disposition --show-progress -e dotbytes="$dotbytes" -P "$dir" "$url"
        else
            wget -qnc --content-disposition --show-progress -e dotbytes="$dotbytes" -P "$dir" "$url"
        fi
    fi
}


# Allow user to disable provisioning if they started with a script they didn't want
if [[ ! -f /.noprovisioning ]]; then
    provisioning_start
fi
