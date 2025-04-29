#!/bin/bash

# Setup script for Vast.ai environment

echo "===== Setting up Python environment ====="
# Make sure python and python3 are both available
if ! command -v python &> /dev/null; then
    echo "Creating python symlink to python3"
    ln -sf $(which python3) /usr/bin/python
fi

echo "===== Installing PyTorch and dependencies ====="
# Install PyTorch with CUDA support
pip install torch torchvision torchaudio --extra-index-url https://download.pytorch.org/whl/cu118

# Install other essential packages
echo "===== Installing other essential packages ====="
pip install transformers diffusers accelerate safetensors
pip install numpy matplotlib opencv-python scikit-image

# Setup VisoMaster directories if they don't exist
echo "===== Setting up VisoMaster directories ====="
mkdir -p /workspace
if [ ! -d "/workspace/visomaster" ]; then
    echo "Cloning VisoMaster repository"
    cd /workspace
    git clone https://github.com/visomaster/VisoMaster.git visomaster
fi

# Create required directories
mkdir -p /VisoMaster/models
mkdir -p /VisoMaster/model_assets

echo "===== Environment setup complete ====="
echo "Run 'python -c \"import torch; print(torch.cuda.is_available())\"' to verify PyTorch CUDA setup"
