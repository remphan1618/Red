import gradio as gr
import sys
import subprocess
import os
import platform
import shutil
import time
import threading
import queue
import argparse
import copy

try:
    from huggingface_hub import hf_hub_download, snapshot_download, HfFileSystem
    from huggingface_hub.utils import HfHubHTTPError, HFValidationError
except ImportError:
    print("huggingface_hub not found. Attempting installation...")
    try:
        subprocess.check_call([sys.executable, "-m", "pip", "install", "huggingface_hub>=0.20.0"]) # Added version specifier
        import importlib
        importlib.invalidate_caches()
        from huggingface_hub import hf_hub_download, snapshot_download, HfFileSystem
        from huggingface_hub.utils import HfHubHTTPError, HFValidationError
        print("huggingface_hub installed and imported successfully.")
    except Exception as e:
        print(f"ERROR: Failed to install or import huggingface_hub: {e}")
        print("Please install it manually: pip install huggingface_hub>=0.20.0")
        sys.exit(1)


APP_TITLE = f"SwarmUI Model Downloader"

def install_package(package_name, version_spec=""):
    """Installs a package using pip."""
    try:
        print(f"Attempting to install {package_name}{version_spec}...")
        subprocess.check_call([sys.executable, "-m", "pip", "install", f"{package_name}{version_spec}"])
        print(f"Successfully installed {package_name}.")
        if package_name == "huggingface_hub":
            import importlib
            importlib.invalidate_caches()
            globals()['hf_hub_download'] = importlib.import_module('huggingface_hub').hf_hub_download
            globals()['snapshot_download'] = importlib.import_module('huggingface_hub').snapshot_download
            globals()['HfFileSystem'] = importlib.import_module('huggingface_hub').HfFileSystem
            globals()['HfHubHTTPError'] = importlib.import_module('huggingface_hub.utils').HfHubHTTPError
            globals()['HFValidationError'] = importlib.import_module('huggingface_hub.utils').HFValidationError
        elif package_name == "hf_transfer":
             import importlib
             importlib.invalidate_caches()
             globals()['HF_TRANSFER_AVAILABLE'] = True
        return True
    except subprocess.CalledProcessError as e:
        print(f"ERROR: Failed to install {package_name}: {e}")
        print("Please install it manually using: pip install ", f"{package_name}{version_spec}")
    except ImportError:
         print(f"ERROR: Failed to import {package_name} even after attempting install.")
    return False

print("huggingface_hub found (or installed).")

try:
    import hf_transfer
    print("hf_transfer found.")
    HF_TRANSFER_AVAILABLE = True
except ImportError:
    print("hf_transfer is optional but recommended for faster downloads.")
    HF_TRANSFER_AVAILABLE = False
    if install_package("hf_transfer", ">=0.1.8"):
        try:
            import hf_transfer
            print("hf_transfer installed successfully after attempt.")
            HF_TRANSFER_AVAILABLE = True
        except ImportError:
            print("hf_transfer still not found after install attempt.")
            HF_TRANSFER_AVAILABLE = False
    else:
        HF_TRANSFER_AVAILABLE = False

HIDREAM_INFO_LINK = "https://github.com/mcmonkeyprojects/SwarmUI/blob/master/docs/Model%20Support.md#hidream-i1"
GGUF_QUALITY_INFO = "GGUF Quality: Q8 > Q6 > Q5 (K_M > K_S > 1 > 0) > Q4 (K_M > K_S > 1 > 0) > Q3 (K_M > K_S) > Q2_K."

# Define the new VAE model entry here to be referenced in models_structure
ltx_vae_companion_entry = {
    "name": "LTX VAE (BF16) - Companion for LTX 13B Dev Models",
    "repo_id": "wsbagnsv1/ltxv-13b-0.9.7-dev-GGUF",
    "filename_in_repo": "ltxv-13b-0.9.7-vae-BF16.safetensors",
    "save_filename": "LTX_VAE_13B_Dev_BF16.safetensors",
    "target_dir_key": "vae"  # Ensures it's saved in the VAE folder
}

wan_causvid_14b_lora_entry = {
    "name": "Wan 2.1 CausVid T2V/I2V LoRA 14B (Rank 32) - Companion",
    "repo_id": "Kijai/WanVideo_comfy",
    "filename_in_repo": "Wan21_CausVid_14B_T2V_lora_rank32.safetensors",
    "save_filename": "Wan21_CausVid_14B_T2V_lora_rank32.safetensors",
    "target_dir_key": "Lora",
    "info": "High-speed LoRA for Wan 2.1 14B T2V/I2V. Saves to Lora folder. Also listed under 'Wan 2.1 Models' and 'LoRA Models'. See SwarmUI Video Docs for usage details on CFG, Steps, FPS, and Trim Video Start Frames."
}

wan_causvid_1_3b_lora_entry = {
    "name": "Wan 2.1 CausVid T2V LoRA 1.3B (Rank 32) - Companion",
    "repo_id": "Kijai/WanVideo_comfy",
    "filename_in_repo": "Wan21_CausVid_bidirect2_T2V_1_3B_lora_rank32.safetensors",
    "save_filename": "Wan21_CausVid_bidirect2_T2V_1_3B_lora_rank32.safetensors",
    "target_dir_key": "Lora",
    "info": "High-speed LoRA for Wan 2.1 1.3B T2V. Saves to Lora folder. Also listed under 'Wan 2.1 Models' and 'LoRA Models'. See SwarmUI Video Docs for usage details."
}

models_structure = {
    "Download Bundles": {
        "info": "Download pre-defined bundles of commonly used models with a single click.",
        "bundles": [
            {
                "name": "Wan 2.1 Core Models Bundle (GGUF Q6_K + LoRA)",
                "info": (
                    "Downloads a core set of Wan 2.1 models for video generation, including T2V, I2V, and a companion LoRA, plus the recommended UMT5 text encoder.\n\n"
                    "**Includes:**\n"
                    "- Wan 2.1 T2V 1.3B FP16\n"
                    "- Wan 2.1 CausVid T2V/I2V LoRA 14B (Rank 32) - Companion\n"
                    "- Wan 2.1 T2V 14B 720p GGUF Q6_K\n"
                    "- Wan 2.1 I2V 14B 720p GGUF Q6_K\n"
                    "- UMT5 XXL FP8 Scaled (Default for SwarmUI)\n"
                    "\n"
                    "**How to use Wan 2.1:** [Wan 2.1 Parameters](https://github.com/mcmonkeyprojects/SwarmUI/blob/master/docs/Video%20Model%20Support.md#wan-21-parameters)"
                ),
                "models_to_download": [
                    ("Video Generation Models", "Wan 2.1 Models", "Wan 2.1 T2V 1.3B FP16"),
                    ("Video Generation Models", "Wan 2.1 Models", "Wan 2.1 CausVid T2V/I2V LoRA 14B (Rank 32) - Companion"), # This is already a direct entry
                    ("Video Generation Models", "Wan 2.1 Models", "Wan 2.1 T2V 14B 720p GGUF Q6_K"),
                    ("Video Generation Models", "Wan 2.1 Models", "Wan 2.1 I2V 14B 720p GGUF Q6_K"),
                    ("Text Encoder Models", "UMT5 XXL Models", "UMT5 XXL FP8 Scaled (Default for SwarmUI)"),
                ]
            },
            {
                "name": "FLUX Models Bundle",
                "info": (
                    "Downloads a core set of models for using FLUX models in SwarmUI, plus common utility models.\n\n"
                    "**Includes:**\n"
                    "- FLUX DEV 1.0 FP16 (Saved as FLUX_Dev.safetensors)\n"
                    "- FLUX DEV Fill (In/Out-Painting) (Saved as FLUX_DEV_Fill.safetensors)\n"
                    "- FLUX DEV Redux (Style/Mix) (Saved as FLUX_DEV_Redux.safetensors)\n" 
                    "- T5 XXL FP16 (Saved as t5xxl_enconly.safetensors)\n"
                    "- FLUX VAE (Saved as FLUX_VAE.safetensors)\n"
                    "- CLIP-SAE-ViT-L-14 (Saved as clip_l.safetensors - SwarmUI Default)\n"
                    "- Best Image Upscaler Models (Full Set)\n"
                    "- Face Segment/Masking Models (Full Set)\n"
                    "\n"
                    "**How to use FLUX:** [FLUX Model Support](https://github.com/mcmonkeyprojects/SwarmUI/blob/master/docs/Model%20Support.md#black-forest-labs-flux1-models)\n"
                    "**Important Setup Guide:** [General FLUX Install/Usage](https://github.com/mcmonkeyprojects/SwarmUI/blob/master/docs/Model%20Support.md#install)"
                ),
                "models_to_download": [
                    ("Image Generation Models", "FLUX Models", "FLUX DEV 1.0 FP16"),
                    ("Image Generation Models", "FLUX Models", "FLUX DEV Fill (In/Out-Painting)"),
                    ("Image Generation Models", "FLUX Models", "FLUX DEV Redux (Style/Mix)"),
                    ("Text Encoder Models", "T5 XXL Models", "T5 XXL FP16 (Save As t5xxl_enconly for SwarmUI default name)"),
                    ("VAE Models", "Most Common VAEs (e.g. FLUX and HiDream-I1)", "FLUX VAE as FLUX_VAE.safetensors (Used by FLUX, HiDream, etc.)"),
                    ("Text Encoder Models", "Clip Models", "CLIP-SAE-ViT-L-14 (Save As clip_l.safetensors - SwarmUI default name)"),
                    ("Other Models (e.g. Yolo Face Segment, Image Upscaling)", "Image Upscaling Models", "Best Upscaler Models (Full Set Snapshot)"),
                    ("Other Models (e.g. Yolo Face Segment, Image Upscaling)", "Auto Yolo Masking/Segment Models", "Face Segment/Masking Models (Full Set Snapshot)"),
                ]
            },
            {
                 "name": "HiDream-I1 Dev Bundle (Recommended)",
                 "info": (
                     "Downloads the recommended HiDream-I1 Dev model (Q8 GGUF), necessary supporting files, and common utility models.\n\n"
                     "**Includes:**\n"
                     "- HiDream-I1 Dev GGUF Q8_0 (Saved as HiDream_I1_Dev_GGUF_Q8_0.gguf)\n"
                     "- T5 XXL FP16 (Saved as t5xxl_enconly.safetensors)\n"
                     "- Long Clip L for HiDream-I1 (Saved as long_clip_l_hi_dream.safetensors)\n"
                     "- Long Clip G for HiDream-I1 (Saved as long_clip_g_hi_dream.safetensors)\n"
                     "- LLAMA 3.1 8b Instruct FP8 Scaled for HiDream-I1 (Saved as llama_3.1_8b_instruct_fp8_scaled.safetensors)\n"
                     "- FLUX VAE (Saved as FLUX_VAE.safetensors)\n"
                     "- Best Image Upscaler Models (Full Set)\n"
                     "- Face Segment/Masking Models (Full Set)\n"
                     "\n"
                     "**How to use HiDream:** [HiDream Model Support](https://github.com/mcmonkeyprojects/SwarmUI/blob/master/docs/Model%20Support.md#hidream-i1)"
                 ),
                 "models_to_download": [
                     ("Image Generation Models", "HiDream-I1 Dev Models (Recommended)", "HiDream-I1 Dev GGUF Q8_0"),
                     ("Text Encoder Models", "T5 XXL Models", "T5 XXL FP16 (Save As t5xxl_enconly for SwarmUI default name)"),
                     ("Text Encoder Models", "Clip Models", "Long Clip L for HiDream-I1"),
                     ("Text Encoder Models", "Clip Models", "Long Clip G for HiDream-I1"),
                     ("Text Encoder Models", "LLM Text Encoders", "LLAMA 3.1 8b Instruct FP8 Scaled for HiDream-I1"),
                     ("VAE Models", "Most Common VAEs (e.g. FLUX and HiDream-I1)", "FLUX VAE as FLUX_VAE.safetensors (Used by FLUX, HiDream, etc.)"),
                     ("Other Models (e.g. Yolo Face Segment, Image Upscaling)", "Image Upscaling Models", "Best Upscaler Models (Full Set Snapshot)"),
                     ("Other Models (e.g. Yolo Face Segment, Image Upscaling)", "Auto Yolo Masking/Segment Models", "Face Segment/Masking Models (Full Set Snapshot)"),
                 ]
             },
        ]
    },
    "Image Generation Models": {
        "info": "Models for generating images from text or other inputs.",
        "sub_categories": {
            "FLUX Models": {
                "info": ("FLUX models including Dev, ControlNet-like variants, and quantized versions. GGUF Quality: Q8 > Q6 > Q5 > Q4 (K_M > K_S > K > 1 > 0).\n\n"
                         "**How to use FLUX:** [FLUX Model Support](https://github.com/mcmonkeyprojects/SwarmUI/blob/master/docs/Model%20Support.md#black-forest-labs-flux1-models)\n"
                         "**Extremely Important How To Use Parameters and Guide:**\n"
                         "- [General FLUX Install/Usage](https://github.com/mcmonkeyprojects/SwarmUI/blob/master/docs/Model%20Support.md#install)\n"
                         "- [FLUX Tools Usage (Depth, Canny, etc.)](https://github.com/mcmonkeyprojects/SwarmUI/blob/master/docs/Model%20Support.md#flux1-tools)"),
                "target_dir_key": "diffusion_models",
                "models": [
                    {"name": "FLUX DEV 1.0 FP16", "repo_id": "OwlMaster/FLUX_LoRA_Train", "filename_in_repo": "flux1-dev.safetensors", "save_filename": "FLUX_Dev.safetensors"},
                    {"name": "FLUX DEV Fill (In/Out-Painting)", "repo_id": "OwlMaster/SD3New", "filename_in_repo": "flux1-fill-dev.safetensors", "save_filename": "FLUX_DEV_Fill.safetensors"},

                    {"name": "FLUX DEV Depth", "repo_id": "OwlMaster/SD3New", "filename_in_repo": "flux1-depth-dev.safetensors", "save_filename": "FLUX_DEV_Depth.safetensors"},
                    {"name": "FLUX DEV Canny", "repo_id": "OwlMaster/SD3New", "filename_in_repo": "flux1-canny-dev.safetensors", "save_filename": "FLUX_DEV_Canny.safetensors"},
                    {"name": "FLUX DEV Redux (Style/Mix)", "repo_id": "OwlMaster/SD3New", "filename_in_repo": "flux1-redux-dev.safetensors", "save_filename": "FLUX_DEV_Redux.safetensors", "target_dir_key": "style_models"},
                    {"name": "FLUX DEV 1.0 FP8 Scaled", "repo_id": "comfyanonymous/flux_dev_scaled_fp8_test", "filename_in_repo": "flux_dev_fp8_scaled_diffusion_model.safetensors", "save_filename": "FLUX_Dev_FP8_Scaled.safetensors"},
                    {"name": "FLUX DEV 1.0 GGUF Q8", "repo_id": "city96/FLUX.1-dev-gguf", "filename_in_repo": "flux1-dev-Q8_0.gguf", "save_filename": "FLUX_Dev_GGUF_Q8.gguf"},
                    {"name": "FLUX DEV 1.0 GGUF Q6_K", "repo_id": "city96/FLUX.1-dev-gguf", "filename_in_repo": "flux1-dev-Q6_K.gguf", "save_filename": "FLUX_Dev_GGUF_Q6_K.gguf"},
                    {"name": "FLUX DEV 1.0 GGUF Q5_K_S", "repo_id": "city96/FLUX.1-dev-gguf", "filename_in_repo": "flux1-dev-Q5_K_S.gguf", "save_filename": "FLUX_Dev_GGUF_Q5_K_S.gguf"},
                    {"name": "FLUX DEV 1.0 GGUF Q4_K_S", "repo_id": "city96/FLUX.1-dev-gguf", "filename_in_repo": "flux1-dev-Q4_K_S.gguf", "save_filename": "FLUX_Dev_GGUF_Q4_K_S.gguf"},
                    {"name": "FLUX DEV Fill GGUF Q8_0", "repo_id": "YarvixPA/FLUX.1-Fill-dev-gguf", "filename_in_repo": "flux1-fill-dev-Q8_0.gguf", "save_filename": "FLUX_DEV_Fill_GGUF_Q8_0.gguf"},
                    {"name": "FLUX DEV Fill GGUF Q6_K", "repo_id": "YarvixPA/FLUX.1-Fill-dev-gguf", "filename_in_repo": "flux1-fill-dev-Q6_K.gguf", "save_filename": "FLUX_DEV_Fill_GGUF_Q6_K.gguf"},
                    {"name": "FLUX DEV Fill GGUF Q5_K_S", "repo_id": "YarvixPA/FLUX.1-Fill-dev-gguf", "filename_in_repo": "flux1-fill-dev-Q5_K_S.gguf", "save_filename": "FLUX_DEV_Fill_GGUF_Q5_K_S.gguf"},
                    {"name": "FLUX DEV Fill GGUF Q4_K_S", "repo_id": "YarvixPA/FLUX.1-Fill-dev-gguf", "filename_in_repo": "flux1-fill-dev-Q4_K_S.gguf", "save_filename": "FLUX_DEV_Fill_GGUF_Q4_K_S.gguf"},
                    {"name": "FLUX DEV PixelWave V3", "repo_id": "mikeyandfriends/PixelWave_FLUX.1-dev_03", "filename_in_repo": "pixelwave_flux1_dev_bf16_03.safetensors", "save_filename": "FLUX_DEV_PixelWave_V3.safetensors"},
                    {"name": "FLUX DEV De-Distilled (Normal CFG 3.5)", "repo_id": "nyanko7/flux-dev-de-distill", "filename_in_repo": "consolidated_s6700.safetensors", "save_filename": "FLUX_DEV_De_Distilled.safetensors"},
                    {"name": "Flux Sigma Vision Alpha1 FP16 (Normal CFG 3.5)", "repo_id": "MonsterMMORPG/Best_FLUX_Models", "filename_in_repo": "fluxSigmaVision_fp16.safetensors", "save_filename": "Flux_Sigma_Vision_Alpha1_FP16.safetensors"},
                    {"name": "FLEX 1 Alpha (New Arch)", "repo_id": "ostris/Flex.1-alpha", "filename_in_repo": "Flex.1-alpha.safetensors", "save_filename": "FLEX_1_Alpha.safetensors"},
                    {
                        "name": "FLUX DEV ControlNet Inpainting Beta (Alimama)",
                        "repo_id": "alimama-creative/FLUX.1-dev-Controlnet-Inpainting-Beta",
                        "filename_in_repo": "diffusion_pytorch_model.safetensors",
                        "save_filename": "alimama_flux_inpainting.safetensors",
                        "target_dir_key": "controlnet"
                    },
                ]
            },
            "HiDream-I1 Image Editing Models": {
                "info": f"Image editing specific variant of HiDream-I1.\n\n**How to use HiDream:** [{HIDREAM_INFO_LINK}]({HIDREAM_INFO_LINK})",
                "target_dir_key": "diffusion_models",
                "models": [
                     {"name": "HiDream-I1-E1 BF16 Image Editing", "repo_id": "Comfy-Org/HiDream-I1_ComfyUI", "filename_in_repo": "split_files/diffusion_models/hidream_e1_full_bf16.safetensors", "save_filename": "HiDream_I1_E1_Image_Editing_BF16.safetensors"},
                ]
            },
            "HiDream-I1 Full Models": {
                "info": f"Full version of HiDream-I1 models. {GGUF_QUALITY_INFO}\n\n**How to use HiDream:** [{HIDREAM_INFO_LINK}]({HIDREAM_INFO_LINK})",
                "target_dir_key": "diffusion_models",
                "models": [
                     {"name": "HiDream-I1 Full FP16", "repo_id": "Comfy-Org/HiDream-I1_ComfyUI", "filename_in_repo": "split_files/diffusion_models/hidream_i1_full_fp16.safetensors", "save_filename": "HiDream_I1_Full_FP16.safetensors"},
                     {"name": "HiDream-I1 Full FP8", "repo_id": "Comfy-Org/HiDream-I1_ComfyUI", "filename_in_repo": "split_files/diffusion_models/hidream_i1_full_fp8.safetensors", "save_filename": "HiDream_I1_Full_FP8.safetensors"},
                     {"name": "HiDream-I1 Full GGUF F16", "repo_id": "city96/HiDream-I1-Full-gguf", "filename_in_repo": "hidream-i1-full-F16.gguf", "save_filename": "HiDream_I1_Full_GGUF_F16.gguf"},
                     {"name": "HiDream-I1 Full GGUF Q8_0", "repo_id": "city96/HiDream-I1-Full-gguf", "filename_in_repo": "hidream-i1-full-Q8_0.gguf", "save_filename": "HiDream_I1_Full_GGUF_Q8_0.gguf"},
                     {"name": "HiDream-I1 Full GGUF Q6_K", "repo_id": "city96/HiDream-I1-Full-gguf", "filename_in_repo": "hidream-i1-full-Q6_K.gguf", "save_filename": "HiDream_I1_Full_GGUF_Q6_K.gguf"},
                     {"name": "HiDream-I1 Full GGUF Q5_K_M", "repo_id": "city96/HiDream-I1-Full-gguf", "filename_in_repo": "hidream-i1-full-Q5_K_M.gguf", "save_filename": "HiDream_I1_Full_GGUF_Q5_K_M.gguf"},
                     {"name": "HiDream-I1 Full GGUF Q5_K_S", "repo_id": "city96/HiDream-I1-Full-gguf", "filename_in_repo": "hidream-i1-full-Q5_K_S.gguf", "save_filename": "HiDream_I1_Full_GGUF_Q5_K_S.gguf"},
                     {"name": "HiDream-I1 Full GGUF Q5_1", "repo_id": "city96/HiDream-I1-Full-gguf", "filename_in_repo": "hidream-i1-full-Q5_1.gguf", "save_filename": "HiDream_I1_Full_GGUF_Q5_1.gguf"},
                     {"name": "HiDream-I1 Full GGUF Q5_0", "repo_id": "city96/HiDream-I1-Full-gguf", "filename_in_repo": "hidream-i1-full-Q5_0.gguf", "save_filename": "HiDream_I1_Full_GGUF_Q5_0.gguf"},
                     {"name": "HiDream-I1 Full GGUF Q4_K_M", "repo_id": "city96/HiDream-I1-Full-gguf", "filename_in_repo": "hidream-i1-full-Q4_K_M.gguf", "save_filename": "HiDream_I1_Full_GGUF_Q4_K_M.gguf"},
                     {"name": "HiDream-I1 Full GGUF Q4_K_S", "repo_id": "city96/HiDream-I1-Full-gguf", "filename_in_repo": "hidream-i1-full-Q4_K_S.gguf", "save_filename": "HiDream_I1_Full_GGUF_Q4_K_S.gguf"},
                     {"name": "HiDream-I1 Full GGUF Q4_1", "repo_id": "city96/HiDream-I1-Full-gguf", "filename_in_repo": "hidream-i1-full-Q4_1.gguf", "save_filename": "HiDream_I1_Full_GGUF_Q4_1.gguf"},
                     {"name": "HiDream-I1 Full GGUF Q4_0", "repo_id": "city96/HiDream-I1-Full-gguf", "filename_in_repo": "hidream-i1-full-Q4_0.gguf", "save_filename": "HiDream_I1_Full_GGUF_Q4_0.gguf"},
                     {"name": "HiDream-I1 Full GGUF Q3_K_M", "repo_id": "city96/HiDream-I1-Full-gguf", "filename_in_repo": "hidream-i1-full-Q3_K_M.gguf", "save_filename": "HiDream_I1_Full_GGUF_Q3_K_M.gguf"},
                     {"name": "HiDream-I1 Full GGUF Q3_K_S", "repo_id": "city96/HiDream-I1-Full-gguf", "filename_in_repo": "hidream-i1-full-Q3_K_S.gguf", "save_filename": "HiDream_I1_Full_GGUF_Q3_K_S.gguf"},
                     {"name": "HiDream-I1 Full GGUF Q2_K", "repo_id": "city96/HiDream-I1-Full-gguf", "filename_in_repo": "hidream-i1-full-Q2_K.gguf", "save_filename": "HiDream_I1_Full_GGUF_Q2_K.gguf"},
                ]
            },
            "HiDream-I1 Dev Models (Recommended)": {
                "info": f"Development version of HiDream-I1 models (Recommended for general use). {GGUF_QUALITY_INFO}\n\n**How to use HiDream:** [{HIDREAM_INFO_LINK}]({HIDREAM_INFO_LINK})",
                "target_dir_key": "diffusion_models",
                "models": [
                     {"name": "HiDream-I1 Dev BF16", "repo_id": "Comfy-Org/HiDream-I1_ComfyUI", "filename_in_repo": "split_files/diffusion_models/hidream_i1_dev_bf16.safetensors", "save_filename": "HiDream_I1_Dev_BF16.safetensors"},
                     {"name": "HiDream-I1 Dev FP8", "repo_id": "Comfy-Org/HiDream-I1_ComfyUI", "filename_in_repo": "split_files/diffusion_models/hidream_i1_dev_fp8.safetensors", "save_filename": "HiDream_I1_Dev_FP8.safetensors"},
                     {"name": "HiDream-I1 Dev GGUF BF16", "repo_id": "city96/HiDream-I1-Dev-gguf", "filename_in_repo": "hidream-i1-dev-BF16.gguf", "save_filename": "HiDream_I1_Dev_GGUF_BF16.gguf"},
                     {"name": "HiDream-I1 Dev GGUF Q8_0", "repo_id": "city96/HiDream-I1-Dev-gguf", "filename_in_repo": "hidream-i1-dev-Q8_0.gguf", "save_filename": "HiDream_I1_Dev_GGUF_Q8_0.gguf"},
                     {"name": "HiDream-I1 Dev GGUF Q6_K", "repo_id": "city96/HiDream-I1-Dev-gguf", "filename_in_repo": "hidream-i1-dev-Q6_K.gguf", "save_filename": "HiDream_I1_Dev_GGUF_Q6_K.gguf"},
                     {"name": "HiDream-I1 Dev GGUF Q5_K_M", "repo_id": "city96/HiDream-I1-Dev-gguf", "filename_in_repo": "hidream-i1-dev-Q5_K_M.gguf", "save_filename": "HiDream_I1_Dev_GGUF_Q5_K_M.gguf"},
                     {"name": "HiDream-I1 Dev GGUF Q5_K_S", "repo_id": "city96/HiDream-I1-Dev-gguf", "filename_in_repo": "hidream-i1-dev-Q5_K_S.gguf", "save_filename": "HiDream_I1_Dev_GGUF_Q5_K_S.gguf"},
                     {"name": "HiDream-I1 Dev GGUF Q5_1", "repo_id": "city96/HiDream-I1-Dev-gguf", "filename_in_repo": "hidream-i1-dev-Q5_1.gguf", "save_filename": "HiDream_I1_Dev_GGUF_Q5_1.gguf"},
                     {"name": "HiDream-I1 Dev GGUF Q5_0", "repo_id": "city96/HiDream-I1-Dev-gguf", "filename_in_repo": "hidream-i1-dev-Q5_0.gguf", "save_filename": "HiDream_I1_Dev_GGUF_Q5_0.gguf"},
                     {"name": "HiDream-I1 Dev GGUF Q4_K_M", "repo_id": "city96/HiDream-I1-Dev-gguf", "filename_in_repo": "hidream-i1-dev-Q4_K_M.gguf", "save_filename": "HiDream_I1_Dev_GGUF_Q4_K_M.gguf"},
                     {"name": "HiDream-I1 Dev GGUF Q4_K_S", "repo_id": "city96/HiDream-I1-Dev-gguf", "filename_in_repo": "hidream-i1-dev-Q4_K_S.gguf", "save_filename": "HiDream_I1_Dev_GGUF_Q4_K_S.gguf"},
                     {"name": "HiDream-I1 Dev GGUF Q4_1", "repo_id": "city96/HiDream-I1-Dev-gguf", "filename_in_repo": "hidream-i1-dev-Q4_1.gguf", "save_filename": "HiDream_I1_Dev_GGUF_Q4_1.gguf"},
                     {"name": "HiDream-I1 Dev GGUF Q4_0", "repo_id": "city96/HiDream-I1-Dev-gguf", "filename_in_repo": "hidream-i1-dev-Q4_0.gguf", "save_filename": "HiDream_I1_Dev_GGUF_Q4_0.gguf"},
                     {"name": "HiDream-I1 Dev GGUF Q3_K_M", "repo_id": "city96/HiDream-I1-Dev-gguf", "filename_in_repo": "hidream-i1-dev-Q3_K_M.gguf", "save_filename": "HiDream_I1_Dev_GGUF_Q3_K_M.gguf"},
                     {"name": "HiDream-I1 Dev GGUF Q3_K_S", "repo_id": "city96/HiDream-I1-Dev-gguf", "filename_in_repo": "hidream-i1-dev-Q3_K_S.gguf", "save_filename": "HiDream_I1_Dev_GGUF_Q3_K_S.gguf"},
                     {"name": "HiDream-I1 Dev GGUF Q2_K", "repo_id": "city96/HiDream-I1-Dev-gguf", "filename_in_repo": "hidream-i1-dev-Q2_K.gguf", "save_filename": "HiDream_I1_Dev_GGUF_Q2_K.gguf"},
                ]
            },
            "HiDream-I1 Fast Models": {
                "info": f"Faster distilled version of HiDream-I1 models. {GGUF_QUALITY_INFO}\n\n**How to use HiDream:** [{HIDREAM_INFO_LINK}]({HIDREAM_INFO_LINK})",
                "target_dir_key": "diffusion_models",
                "models": [
                     {"name": "HiDream-I1 Fast BF16", "repo_id": "Comfy-Org/HiDream-I1_ComfyUI", "filename_in_repo": "split_files/diffusion_models/hidream_i1_fast_bf16.safetensors", "save_filename": "HiDream_I1_Fast_BF16.safetensors"},
                     {"name": "HiDream-I1 Fast FP8", "repo_id": "Comfy-Org/HiDream-I1_ComfyUI", "filename_in_repo": "split_files/diffusion_models/hidream_i1_fast_fp8.safetensors", "save_filename": "HiDream_I1_Fast_FP8.safetensors"},
                     {"name": "HiDream-I1 Fast GGUF BF16", "repo_id": "city96/HiDream-I1-Fast-gguf", "filename_in_repo": "hidream-i1-fast-BF16.gguf", "save_filename": "HiDream_I1_Fast_GGUF_BF16.gguf"},
                     {"name": "HiDream-I1 Fast GGUF Q8_0", "repo_id": "city96/HiDream-I1-Fast-gguf", "filename_in_repo": "hidream-i1-fast-Q8_0.gguf", "save_filename": "HiDream_I1_Fast_GGUF_Q8_0.gguf"},
                     {"name": "HiDream-I1 Fast GGUF Q6_K", "repo_id": "city96/HiDream-I1-Fast-gguf", "filename_in_repo": "hidream-i1-fast-Q6_K.gguf", "save_filename": "HiDream_I1_Fast_GGUF_Q6_K.gguf"},
                     {"name": "HiDream-I1 Fast GGUF Q5_K_M", "repo_id": "city96/HiDream-I1-Fast-gguf", "filename_in_repo": "hidream-i1-fast-Q5_K_M.gguf", "save_filename": "HiDream_I1_Fast_GGUF_Q5_K_M.gguf"},
                     {"name": "HiDream-I1 Fast GGUF Q5_K_S", "repo_id": "city96/HiDream-I1-Fast-gguf", "filename_in_repo": "hidream-i1-fast-Q5_K_S.gguf", "save_filename": "HiDream_I1_Fast_GGUF_Q5_K_S.gguf"},
                     {"name": "HiDream-I1 Fast GGUF Q5_1", "repo_id": "city96/HiDream-I1-Fast-gguf", "filename_in_repo": "hidream-i1-fast-Q5_1.gguf", "save_filename": "HiDream_I1_Fast_GGUF_Q5_1.gguf"},
                     {"name": "HiDream-I1 Fast GGUF Q5_0", "repo_id": "city96/HiDream-I1-Fast-gguf", "filename_in_repo": "hidream-i1-fast-Q5_0.gguf", "save_filename": "HiDream_I1_Fast_GGUF_Q5_0.gguf"},
                     {"name": "HiDream-I1 Fast GGUF Q4_K_M", "repo_id": "city96/HiDream-I1-Fast-gguf", "filename_in_repo": "hidream-i1-fast-Q4_K_M.gguf", "save_filename": "HiDream_I1_Fast_GGUF_Q4_K_M.gguf"},
                     {"name": "HiDream-I1 Fast GGUF Q4_K_S", "repo_id": "city96/HiDream-I1-Fast-gguf", "filename_in_repo": "hidream-i1-fast-Q4_K_S.gguf", "save_filename": "HiDream_I1_Fast_GGUF_Q4_K_S.gguf"},
                     {"name": "HiDream-I1 Fast GGUF Q4_1", "repo_id": "city96/HiDream-I1-Fast-gguf", "filename_in_repo": "hidream-i1-fast-Q4_1.gguf", "save_filename": "HiDream_I1_Fast_GGUF_Q4_1.gguf"},
                     {"name": "HiDream-I1 Fast GGUF Q4_0", "repo_id": "city96/HiDream-I1-Fast-gguf", "filename_in_repo": "hidream-i1-fast-Q4_0.gguf", "save_filename": "HiDream_I1_Fast_GGUF_Q4_0.gguf"},
                     {"name": "HiDream-I1 Fast GGUF Q3_K_M", "repo_id": "city96/HiDream-I1-Fast-gguf", "filename_in_repo": "hidream-i1-fast-Q3_K_M.gguf", "save_filename": "HiDream_I1_Fast_GGUF_Q3_K_M.gguf"},
                     {"name": "HiDream-I1 Fast GGUF Q3_K_S", "repo_id": "city96/HiDream-I1-Fast-gguf", "filename_in_repo": "hidream-i1-fast-Q3_K_S.gguf", "save_filename": "HiDream_I1_Fast_GGUF_Q3_K_S.gguf"},
                     {"name": "HiDream-I1 Fast GGUF Q2_K", "repo_id": "city96/HiDream-I1-Fast-gguf", "filename_in_repo": "hidream-i1-fast-Q2_K.gguf", "save_filename": "HiDream_I1_Fast_GGUF_Q2_K.gguf"},
                ]
            },
            "Stable Diffusion 1.5 Models": {
                 "info": "Popular fine-tuned models based on Stable Diffusion 1.5.",
                 "target_dir_key": "Stable-Diffusion",
                 "models": [
                    {"name": "Realistic Vision V6", "repo_id": "SG161222/Realistic_Vision_V6.0_B1_noVAE", "filename_in_repo": "Realistic_Vision_V6.0_NV_B1.safetensors", "save_filename": "SD1.5_Realistic_Vision_V6.safetensors"},
                    {"name": "RealCartoon3D V18", "repo_id": "OwlMaster/Some_best_SDXL", "filename_in_repo": "realcartoon3dv18.safetensors", "save_filename": "SD1.5_RealCartoon3D_V18.safetensors"},
                    {"name": "CyberRealistic V8", "repo_id": "OwlMaster/Some_best_SDXL", "filename_in_repo": "cyberrealistic_v80.safetensors", "save_filename": "SD1.5_CyberRealistic_V8.safetensors"},
                    {"name": "epiCPhotoGasm Ultimate Fidelity", "repo_id": "OwlMaster/Some_best_SDXL", "filename_in_repo": "epicphotogasm_ultimateFidelity.safetensors", "save_filename": "epiCPhotoGasm_Ultimate_Fidelity.safetensors"},
                    {"name": "HyperRealism V3", "repo_id": "OwlMaster/Some_best_SDXL", "filename_in_repo": "SD1.5_HyperRealism_v3.safetensors", "save_filename": "SD1.5_HyperRealism_V3.safetensors"},
                 ]
            },
            "Stable Diffusion XL (SDXL) Models": {
                 "info": "Models based on the Stable Diffusion XL architecture.",
                 "target_dir_key": "Stable-Diffusion",
                 "models": [
                    {"name": "SDXL Base 1.0 (Official)", "repo_id": "OwlMaster/Some_best_SDXL", "filename_in_repo": "sd_xl_base_1.0_0.9vae.safetensors", "save_filename": "SDXL_Base_1_0.safetensors"},
                    {"name": "Juggernaut XL V11", "repo_id": "OwlMaster/Some_best_SDXL", "filename_in_repo": "Juggernaut-XI-byRunDiffusion.safetensors", "save_filename": "SDXL_Juggernaut_V11.safetensors"},
                    {"name": "epiCRealism XL LastFame", "repo_id": "OwlMaster/Some_best_SDXL", "filename_in_repo": "epicrealismXL_vxviLastfameRealism.safetensors", "save_filename": "SDXL_epiCRealism_Last_LastFame.safetensors"},
                    {"name": "RealVisXL V5", "repo_id": "OwlMaster/Some_best_SDXL", "filename_in_repo": "realvisxlV50_v50Bakedvae.safetensors", "save_filename": "SDXL_RealVisXL_V5.safetensors"},
                    {"name": "Real Dream SDXL 5", "repo_id": "OwlMaster/Some_best_SDXL", "filename_in_repo": "realDream_sdxl5.safetensors", "save_filename": "SDXL_RealDream_5.safetensors"},
                    {"name": "Eldritch Photography V1", "repo_id": "OwlMaster/Some_best_SDXL", "filename_in_repo": "eldritchPhotography_v1.safetensors", "save_filename": "SDXL_Eldritch_Photography_V1.safetensors"},
                 ]
            },
            "Stable Diffusion 3.5 Large Models": {
                "info": "Official Stable Diffusion 3.5 Large models and variants. GGUF Quality: Q8 > Q6 > Q5 > Q4 (K_M > K_S > K > 1 > 0).",
                "target_dir_key": "diffusion_models",
                "models": [
                     {"name": "Stable Diffusion 3.5 Large (Official) - FP16", "repo_id": "OwlMaster/SD3New", "filename_in_repo": "sd3.5_large.safetensors", "save_filename": "SD3.5_Official_Large.safetensors"},
                     {"name": "Stable Diffusion 3.5 Large (Official) - FP8 Scaled", "repo_id": "OwlMaster/SD3New", "filename_in_repo": "sd3.5_large_fp8_scaled.safetensors", "save_filename": "SD3.5_Official_Large_FP8_Scaled.safetensors", "target_dir_key": "Stable-Diffusion"},
                     {"name": "Stable Diffusion 3.5 Large (Official) - GGUF Q8", "repo_id": "city96/stable-diffusion-3.5-large-gguf", "filename_in_repo": "sd3.5_large-Q8_0.gguf", "save_filename": "SD3.5_Official_Large_GGUF_Q8.gguf"},
                     {"name": "Stable Diffusion 3.5 Large (Official) - GGUF Q5_1", "repo_id": "city96/stable-diffusion-3.5-large-gguf", "filename_in_repo": "sd3.5_large-Q5_1.gguf", "save_filename": "SD3.5_Official_Large_GGUF_Q5_1.gguf"},
                     {"name": "Stable Diffusion 3.5 Large (Official) - GGUF Q4_1", "repo_id": "city96/stable-diffusion-3.5-large-gguf", "filename_in_repo": "sd3.5_large-Q4_1.gguf", "save_filename": "SD3.5_Official_Large_GGUF_Q4_1.gguf"},
                ]
            }
        }
    }, "Other Models (e.g. Yolo Face Segment, Image Upscaling)": {
        "info": "Utility models like upscalers and segmentation models.",
        "sub_categories": {
            "Image Upscaling Models": {
                "info": "High-quality deterministic image upscaling models (from OpenModelDB and other sources).",
                "target_dir_key": "upscale_models",
                "models": [
                    {"name": "Best Upscaler Models (Full Set Snapshot)", "repo_id": "OwlMaster/best_upscaler_models", "is_snapshot": True},
                    {"name": "LTX Spatial Upscaler 0.9.7 (Lightricks)", "repo_id": "Lightricks/LTX-Video", "filename_in_repo": "ltxv-spatial-upscaler-0.9.7.safetensors", "save_filename": "LTX_Spatial_Upscaler_0_9_7.safetensors"},
                    {"name": "LTX Temporal Upscaler 0.9.7 (Lightricks)", "repo_id": "Lightricks/LTX-Video", "filename_in_repo": "ltxv-temporal-upscaler-0.9.7.safetensors", "save_filename": "LTX_Temporal_Upscaler_0_9_7.safetensors"},
                ]
            },
            "Auto Yolo Masking/Segment Models": {
                 "info": "YOLO-based models for automatic face segmentation/masking (from MonsterMMORPG), useful for inpainting.",
                 "target_dir_key": "yolov8",
                 "models": [
                     {"name": "Face Segment/Masking Models (Full Set Snapshot)", "repo_id": "MonsterMMORPG/FaceSegments", "is_snapshot": True},
                 ]
             }
        }
    }, "Text Encoder Models": {
         "info": "Text encoder models used by various generation models.",
         "sub_categories": {
            "T5 XXL Models": {
                "info": "T5 XXL variants used by FLUX, SD 3.5, Hunyuan, etc. GGUF Quality: Q8 > Q6 > Q5 > Q4 (K_M > K_S > K > 1 > 0).",
                "target_dir_key": "clip",
                "models": [
                    {"name": "T5 XXL FP16", "repo_id": "OwlMaster/SD3New", "filename_in_repo": "t5xxl_fp16.safetensors", "save_filename": "t5xxl_fp16.safetensors"},
                    {"name": "T5 XXL FP8 (e4m3fn)", "repo_id": "OwlMaster/SD3New", "filename_in_repo": "t5xxl_fp8_e4m3fn.safetensors", "save_filename": "t5xxl_fp8_e4m3fn.safetensors"},
                    {"name": "T5 XXL FP8 Scaled (e4m3fn)", "repo_id": "OwlMaster/SD3New", "filename_in_repo": "t5xxl_fp8_e4m3fn_scaled.safetensors", "save_filename": "t5xxl_fp8_e4m3fn_scaled.safetensors"},
                    {"name": "T5 XXL FP16 (Save As t5xxl_enconly for SwarmUI default name)", "repo_id": "OwlMaster/SD3New", "filename_in_repo": "t5xxl_fp16.safetensors", "save_filename": "t5xxl_enconly.safetensors"},
                    {"name": "T5 XXL GGUF Q8", "repo_id": "calcuis/mochi", "filename_in_repo": "t5xxl_fp16-q8_0.gguf", "save_filename": "t5xxl_GGUF_Q8.gguf"},
                    {"name": "T5 XXL GGUF Q4_0", "repo_id": "calcuis/mochi", "filename_in_repo": "t5xxl_fp16-q4_0.gguf", "save_filename": "t5xxl_GGUF_Q4_0.gguf"},
                ]
            },
            "UMT5 XXL Models": {
                "info": "UMT5 XXL variants used by Wan 2.1. GGUF Quality: Q8 > Q6 > Q5 > Q4 (K_M > K_S > K > 1 > 0). Select non-GGUF FP16/BF16/FP8 based on your Wan model choice, or use GGUF if preferred (manual setup needed in SwarmUI).",
                "target_dir_key": "clip",
                "models": [
                    {"name": "UMT5 XXL BF16 (Used by Wan 2.1)", "repo_id": "Kijai/WanVideo_comfy", "filename_in_repo": "umt5-xxl-enc-bf16.safetensors", "save_filename": "umt5-xxl-enc-bf16.safetensors"},
                    # These save the same file, choose one or rename target
                    {"name": "UMT5 XXL BF16 (Save As default for SwarmUI)", "repo_id": "Kijai/WanVideo_comfy", "filename_in_repo": "umt5-xxl-enc-bf16.safetensors", "save_filename": "umt5_xxl_fp8_e4m3fn_scaled.safetensors", "target_dir_key": "clip", "allow_overwrite": True},
                    {"name": "UMT5 XXL FP16 (Save As default for SwarmUI)", "repo_id": "Comfy-Org/Wan_2.1_ComfyUI_repackaged", "filename_in_repo": "split_files/text_encoders/umt5_xxl_fp16.safetensors", "save_filename": "umt5_xxl_fp8_e4m3fn_scaled.safetensors", "target_dir_key": "clip", "allow_overwrite": True},
                    {"name": "UMT5 XXL FP8 Scaled (Default for SwarmUI)", "repo_id": "Comfy-Org/Wan_2.1_ComfyUI_repackaged", "filename_in_repo": "split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors", "save_filename": "umt5_xxl_fp8_e4m3fn_scaled.safetensors", "target_dir_key": "clip", "allow_overwrite": True},
                    # GGUF models
                    {"name": "UMT5 XXL GGUF Q8 (Manual Setup)", "repo_id": "city96/umt5-xxl-encoder-gguf", "filename_in_repo": "umt5-xxl-encoder-Q8_0.gguf", "save_filename": "umt5-xxl-encoder-Q8_0.gguf"},
                    {"name": "UMT5 XXL GGUF Q6_K (Manual Setup)", "repo_id": "city96/umt5-xxl-encoder-gguf", "filename_in_repo": "umt5-xxl-encoder-Q6_K.gguf", "save_filename": "umt5-xxl-encoder-Q6_K.gguf"},
                    {"name": "UMT5 XXL GGUF Q5_K_M (Manual Setup)", "repo_id": "city96/umt5-xxl-encoder-gguf", "filename_in_repo": "umt5-xxl-encoder-Q5_K_M.gguf", "save_filename": "umt5-xxl-encoder-Q5_K_M.gguf"},
                    {"name": "UMT5 XXL GGUF Q4_K_M (Manual Setup)", "repo_id": "city96/umt5-xxl-encoder-gguf", "filename_in_repo": "umt5-xxl-encoder-Q4_K_M.gguf", "save_filename": "umt5-xxl-encoder-Q4_K_M.gguf"},
                ]
            },
            "Clip Models": {
                "info": "CLIP models (L and G variants) used by many models.",
                "target_dir_key": "clip",
                "models": [
                    {"name": "CLIP-SAE-ViT-L-14 (Save As clip_l.safetensors - SwarmUI default name)", "repo_id": "OwlMaster/zer0int-CLIP-SAE-ViT-L-14", "filename_in_repo": "clip_l.safetensors", "save_filename": "clip_l.safetensors", "pre_delete_target": True},
                    {"name": "CLIP-SAE-ViT-L-14 (Save As CLIP_SAE_ViT_L_14)", "repo_id": "OwlMaster/zer0int-CLIP-SAE-ViT-L-14", "filename_in_repo": "clip_l.safetensors", "save_filename": "CLIP_SAE_ViT_L_14.safetensors"},
                    {"name": "Default Clip L", "repo_id": "MonsterMMORPG/Kohya_Train", "filename_in_repo": "clip_l.safetensors", "save_filename": "clip_l.safetensors"}, # Use specific save name
                    {"name": "Clip G", "repo_id": "OwlMaster/SD3New", "filename_in_repo": "clip_g.safetensors", "save_filename": "clip_g.safetensors"},
                    {"name": "Long Clip L for HiDream-I1", "repo_id": "Comfy-Org/HiDream-I1_ComfyUI", "filename_in_repo": "split_files/text_encoders/clip_l_hidream.safetensors", "save_filename": "long_clip_l_hi_dream.safetensors"},
                    {"name": "Long Clip G for HiDream-I1", "repo_id": "Comfy-Org/HiDream-I1_ComfyUI", "filename_in_repo": "split_files/text_encoders/clip_g_hidream.safetensors", "save_filename": "long_clip_g_hi_dream.safetensors"},
                ]
            },
            "LLM Text Encoders": {
                 "info": "Large Language Model based text encoders, currently used by HiDream-I1.",
                 "target_dir_key": "clip",
                 "models": [
                     {"name": "LLAMA 3.1 8b Instruct FP8 Scaled for HiDream-I1", "repo_id": "Comfy-Org/HiDream-I1_ComfyUI", "filename_in_repo": "split_files/text_encoders/llama_3.1_8b_instruct_fp8_scaled.safetensors", "save_filename": "llama_3.1_8b_instruct_fp8_scaled.safetensors"},
                 ]
             },
         }
    },
    "Video Generation Models": {
        "info": "Models for generating videos from text or images.",
        "sub_categories": {
            "Wan 2.1 Models": {
                 "info": ("Wan 2.1 text-to-video and image-to-video models. GGUF Quality: Q8 > Q6 > Q5 > Q4 (K_M > K_S > K > 1 > 0).\n\n"
                          "**Extremely Important How To Use Parameters and Guide:** [Wan 2.1 Parameters](https://github.com/mcmonkeyprojects/SwarmUI/blob/master/docs/Video%20Model%20Support.md#wan-21-parameters)"),
                 "target_dir_key": "diffusion_models",
                 "models": [
                    {"name": "Wan 2.1 T2V 1.3B FP16", "repo_id": "Comfy-Org/Wan_2.1_ComfyUI_repackaged", "filename_in_repo": "split_files/diffusion_models/wan2.1_t2v_1.3B_fp16.safetensors", "save_filename": "Wan2.1_1.3b_Text_to_Video.safetensors"},
                    {"name": "Wan 2.1 T2V 14B 720p FP16", "repo_id": "Comfy-Org/Wan_2.1_ComfyUI_repackaged", "filename_in_repo": "split_files/diffusion_models/wan2.1_t2v_14B_fp16.safetensors", "save_filename": "Wan2.1_14b_Text_to_Video.safetensors"},
                    {"name": "Wan 2.1 T2V 14B 720p FP8", "repo_id": "Kijai/WanVideo_comfy", "filename_in_repo": "Wan2_1-T2V-14B_fp8_e4m3fn.safetensors", "save_filename": "Wan2.1_14b_Text_to_Video_FP8.safetensors"},
                    wan_causvid_14b_lora_entry,
                    wan_causvid_1_3b_lora_entry,
                    {"name": "Wan 2.1 I2V 14B 480p FP16", "repo_id": "Comfy-Org/Wan_2.1_ComfyUI_repackaged", "filename_in_repo": "split_files/diffusion_models/wan2.1_i2v_480p_14B_fp16.safetensors", "save_filename": "Wan2.1_14b_Image_to_Video_480p.safetensors"},
                    {"name": "Wan 2.1 I2V 14B 480p FP8", "repo_id": "Kijai/WanVideo_comfy", "filename_in_repo": "Wan2_1-I2V-14B-480P_fp8_e4m3fn.safetensors", "save_filename": "Wan2.1_14b_Image_to_Video_480p_FP8.safetensors"},
                    {"name": "Wan 2.1 I2V 14B 720p FP16", "repo_id": "Comfy-Org/Wan_2.1_ComfyUI_repackaged", "filename_in_repo": "split_files/diffusion_models/wan2.1_i2v_720p_14B_fp16.safetensors", "save_filename": "Wan2.1_14b_Image_to_Video_720p.safetensors"}, # Corrected save name
                    {"name": "Wan 2.1 I2V 14B 720p FP8", "repo_id": "Kijai/WanVideo_comfy", "filename_in_repo": "Wan2_1-I2V-14B-720P_fp8_e4m3fn.safetensors", "save_filename": "Wan2.1_14b_Image_to_Video_720p_FP8.safetensors"},
                    {"name": "Wan 2.1 T2V 14B 720p GGUF Q8", "repo_id": "city96/Wan2.1-T2V-14B-gguf", "filename_in_repo": "wan2.1-t2v-14b-Q8_0.gguf", "save_filename": "Wan2.1_14b_Text_to_Video_GGUF_Q8.gguf"},
                    {"name": "Wan 2.1 T2V 14B 720p GGUF Q6_K", "repo_id": "city96/Wan2.1-T2V-14B-gguf", "filename_in_repo": "wan2.1-t2v-14b-Q6_K.gguf", "save_filename": "Wan2.1_14b_Text_to_Video_GGUF_Q6_K.gguf"},
                    {"name": "Wan 2.1 T2V 14B 720p GGUF Q5_K_M", "repo_id": "city96/Wan2.1-T2V-14B-gguf", "filename_in_repo": "wan2.1-t2v-14b-Q5_K_M.gguf", "save_filename": "Wan2.1_14b_Text_to_Video_GGUF_Q5_K_M.gguf"},
                    {"name": "Wan 2.1 T2V 14B 720p GGUF Q4_K_M", "repo_id": "city96/Wan2.1-T2V-14B-gguf", "filename_in_repo": "wan2.1-t2v-14b-Q4_K_M.gguf", "save_filename": "Wan2.1_14b_Text_to_Video_GGUF_Q4_K_M.gguf"},
                    {"name": "Wan 2.1 I2V 14B 480p GGUF Q8", "repo_id": "city96/Wan2.1-I2V-14B-480P-gguf", "filename_in_repo": "wan2.1-i2v-14b-480p-Q8_0.gguf", "save_filename": "Wan2.1_14b_Image_to_Video_480p_GGUF_Q8.gguf"},
                    {"name": "Wan 2.1 I2V 14B 480p GGUF Q6_K", "repo_id": "city96/Wan2.1-I2V-14B-480P-gguf", "filename_in_repo": "wan2.1-i2v-14b-480p-Q6_K.gguf", "save_filename": "Wan2.1_14b_Image_to_Video_480p_GGUF_Q6_K.gguf"},
                    {"name": "Wan 2.1 I2V 14B 480p GGUF Q5_K_M", "repo_id": "city96/Wan2.1-I2V-14B-480P-gguf", "filename_in_repo": "wan2.1-i2v-14b-480p-Q5_K_M.gguf", "save_filename": "Wan2.1_14b_Image_to_Video_480p_GGUF_Q5_K_M.gguf"},
                    {"name": "Wan 2.1 I2V 14B 480p GGUF Q4_K_M", "repo_id": "city96/Wan2.1-I2V-14B-480P-gguf", "filename_in_repo": "wan2.1-i2v-14b-480p-Q4_K_M.gguf", "save_filename": "Wan2.1_14b_Image_to_Video_480p_GGUF_Q4_K_M.gguf"},
                    {"name": "Wan 2.1 I2V 14B 720p GGUF Q8", "repo_id": "city96/Wan2.1-I2V-14B-720P-gguf", "filename_in_repo": "wan2.1-i2v-14b-720p-Q8_0.gguf", "save_filename": "Wan2.1_14b_Image_to_Video_720p_GGUF_Q8.gguf"}, # Corrected repo file name
                    {"name": "Wan 2.1 I2V 14B 720p GGUF Q6_K", "repo_id": "city96/Wan2.1-I2V-14B-720P-gguf", "filename_in_repo": "wan2.1-i2v-14b-720p-Q6_K.gguf", "save_filename": "Wan2.1_14b_Image_to_Video_720p_GGUF_Q6_K.gguf"},
                    {"name": "Wan 2.1 I2V 14B 720p GGUF Q5_K_M", "repo_id": "city96/Wan2.1-I2V-14B-720P-gguf", "filename_in_repo": "wan2.1-i2v-14b-720p-Q5_K_M.gguf", "save_filename": "Wan2.1_14b_Image_to_Video_720p_GGUF_Q5_K_M.gguf"},
                    {"name": "Wan 2.1 I2V 14B 720p GGUF Q4_K_M", "repo_id": "city96/Wan2.1-I2V-14B-720P-gguf", "filename_in_repo": "wan2.1-i2v-14b-720p-Q4_K_M.gguf", "save_filename": "Wan2.1_14b_Image_to_Video_720p_GGUF_Q4_K_M.gguf"},
                 ]
             },
            "Hunyuan Models": {
                "info": ("Hunyuan text-to-video and image-to-video models. GGUF Quality: Q8 > Q6 > Q5 > Q4 (K_M > K_S > K > 1 > 0).\n\n"
                         "**Extremely Important How To Use Parameters and Guide:** [Hunyuan Video Parameters](https://github.com/mcmonkeyprojects/SwarmUI/blob/master/docs/Video%20Model%20Support.md#hunyuan-video-parameters)"),
                "target_dir_key": "diffusion_models",
                "models": [
                    {"name": "HunYuan T2V 720p BF16", "repo_id": "Comfy-Org/HunyuanVideo_repackaged", "filename_in_repo": "hunyuan_video_t2v_720p_bf16.safetensors", "save_filename": "HunYuan_Text_to_Video.safetensors"},
                    {"name": "HunYuan I2V 720p BF16", "repo_id": "Kijai/HunyuanVideo_comfy", "filename_in_repo": "hunyuan_video_I2V_720_fixed_bf16.safetensors", "save_filename": "HunYuan_Image_to_Video.safetensors"},
                    {"name": "HunYuan T2V 720p CFG Distill BF16", "repo_id": "Kijai/HunyuanVideo_comfy", "filename_in_repo": "hunyuan_video_720_cfgdistill_bf16.safetensors", "save_filename": "HunYuan_Text_to_Video_CFG_Distill.safetensors"},
                    {"name": "HunYuan T2V 720p CFG Distill FP8 Scaled", "repo_id": "Kijai/HunyuanVideo_comfy", "filename_in_repo": "hunyuan_video_720_cfgdistill_fp8_e4m3fn.safetensors", "save_filename": "HunYuan_Text_to_Video_CFG_Distill_FP8_Scaled.safetensors"},
                    {"name": "HunYuan I2V 720p FP8 Scaled", "repo_id": "Kijai/HunyuanVideo_comfy", "filename_in_repo": "hunyuan_video_I2V_720_fixed_fp8_e4m3fn.safetensors", "save_filename": "HunYuan_Image_to_Video_FP8_Scaled.safetensors"},
                    {"name": "HunYuan I2V 720p GGUF Q8", "repo_id": "Kijai/HunyuanVideo_comfy", "filename_in_repo": "hunyuan_video_I2V-Q8_0.gguf", "save_filename": "HunYuan_Image_to_Video_GGUF_Q8.gguf"},
                    {"name": "HunYuan I2V 720p GGUF Q6_K", "repo_id": "Kijai/HunyuanVideo_comfy", "filename_in_repo": "hunyuan_video_I2V-Q6_K.gguf", "save_filename": "HunYuan_Image_to_Video_GGUF_Q6_K.gguf"},
                    {"name": "HunYuan I2V 720p GGUF Q4_K_S", "repo_id": "Kijai/HunyuanVideo_comfy", "filename_in_repo": "hunyuan_video_I2V-Q4_K_S.gguf", "save_filename": "HunYuan_Image_to_Video_GGUF_Q4_K_S.gguf"},
                ]
            },
            "Fast Hunyuan Models - 6 Steps": {
                "info": ("Faster distilled Hunyuan text-to-video models (6 steps). GGUF Quality: Q8 > Q6 > Q5 > Q4 (K_M > K_S > K > 1 > 0).\n\n"
                         "**Extremely Important How To Use Parameters and Guide:** [FastVideo Parameters](https://github.com/mcmonkeyprojects/SwarmUI/blob/master/docs/Video%20Model%20Support.md#fastvideo)"),
                "target_dir_key": "diffusion_models",
                "models": [
                    {"name": "FAST HunYuan T2V 720p GGUF BF16", "repo_id": "city96/FastHunyuan-gguf", "filename_in_repo": "fast-hunyuan-video-t2v-720p-BF16.gguf", "save_filename": "FAST_HunYuan_Text_to_Video_GGUF_BF16.gguf"},
                    {"name": "FAST HunYuan T2V 720p FP8", "repo_id": "Kijai/HunyuanVideo_comfy", "filename_in_repo": "hunyuan_video_FastVideo_720_fp8_e4m3fn.safetensors", "save_filename": "FAST_HunYuan_Text_to_Video_FP8.safetensors"},
                    {"name": "FAST HunYuan T2V 720p GGUF Q8", "repo_id": "city96/FastHunyuan-gguf", "filename_in_repo": "fast-hunyuan-video-t2v-720p-Q8_0.gguf", "save_filename": "FAST_HunYuan_Text_to_Video_GGUF_Q8.gguf"},
                    {"name": "FAST HunYuan T2V 720p GGUF Q6_K", "repo_id": "city96/FastHunyuan-gguf", "filename_in_repo": "fast-hunyuan-video-t2v-720p-Q6_K.gguf", "save_filename": "FAST_HunYuan_Text_to_Video_GGUF_Q6_K.gguf"},
                    {"name": "FAST HunYuan T2V 720p GGUF Q5_K_M", "repo_id": "city96/FastHunyuan-gguf", "filename_in_repo": "fast-hunyuan-video-t2v-720p-Q5_K_M.gguf", "save_filename": "FAST_HunYuan_Text_to_Video_GGUF_Q5_K_M.gguf"},
                    {"name": "FAST HunYuan T2V 720p GGUF Q4_K_M", "repo_id": "city96/FastHunyuan-gguf", "filename_in_repo": "fast-hunyuan-video-t2v-720p-Q4_K_M.gguf", "save_filename": "FAST_HunYuan_Text_to_Video_GGUF_Q4_K_M.gguf"},
                ]
            },
             "SkyReels HunYuan Models": {
                "info": ("SkyReels fine-tuned Hunyuan models. GGUF Quality: Q8 > Q6 > Q5 > Q4 (K_M > K_S > K > 1 > 0).\n\n"
                         "**Extremely Important How To Use Parameters and Guide:** [SkyReels Text2Video Parameters](https://github.com/mcmonkeyprojects/SwarmUI/blob/master/docs/Video%20Model%20Support.md#skyreels-text2video)"),
                "target_dir_key": "diffusion_models",
                "models": [
                    {"name": "SkyReels HunYuan T2V 720p BF16", "repo_id": "Kijai/SkyReels-V1-Hunyuan_comfy", "filename_in_repo": "skyreels_hunyuan_t2v_bf16.safetensors", "save_filename": "SkyReels_Text_to_Video.safetensors"},
                    {"name": "SkyReels HunYuan I2V 720p BF16", "repo_id": "Kijai/SkyReels-V1-Hunyuan_comfy", "filename_in_repo": "skyreels_hunyuan_i2v_bf16.safetensors", "save_filename": "SkyReels_Image_to_Video.safetensors"},
                    {"name": "SkyReels HunYuan T2V 720p FP8", "repo_id": "Kijai/SkyReels-V1-Hunyuan_comfy", "filename_in_repo": "skyreels_hunyuan_t2v_fp8_e4m3fn.safetensors", "save_filename": "SkyReels_Text_to_Video_FP8.safetensors"},
                    {"name": "SkyReels HunYuan I2V 720p FP8", "repo_id": "Kijai/SkyReels-V1-Hunyuan_comfy", "filename_in_repo": "skyreels_hunyuan_i2v_fp8_e4m3fn.safetensors", "save_filename": "SkyReels_Image_to_Video_FP8.safetensors"},
                    {"name": "SkyReels HunYuan I2V 720p GGUF Q8", "repo_id": "Kijai/SkyReels-V1-Hunyuan_comfy", "filename_in_repo": "skyreels-hunyuan-I2V-Q8_0.gguf", "save_filename": "SkyReels_Image_to_Video_GGUF_Q8.gguf"},
                    {"name": "SkyReels HunYuan I2V 720p GGUF Q6_K", "repo_id": "Kijai/SkyReels-V1-Hunyuan_comfy", "filename_in_repo": "skyreels-hunyuan-I2V-Q6_K.gguf", "save_filename": "SkyReels_Image_to_Video_GGUF_Q6_K.gguf"},
                    {"name": "SkyReels HunYuan I2V 720p GGUF Q5_K_M", "repo_id": "Kijai/SkyReels-V1-Hunyuan_comfy", "filename_in_repo": "skyreels-hunyuan-I2V-Q5_K_M.gguf", "save_filename": "SkyReels_Image_to_Video_GGUF_Q5_K_M.gguf"},
                    {"name": "SkyReels HunYuan I2V 720p GGUF Q4_K_S", "repo_id": "Kijai/SkyReels-V1-Hunyuan_comfy", "filename_in_repo": "skyreels-hunyuan-I2V-Q4_K_S.gguf", "save_filename": "SkyReels_Image_to_Video_GGUF_Q4_K_S.gguf"},
                ]
            },
            "Genmo Mochi 1 Models": {
                "info": ("Preview release of Genmo Mochi 1 text-to-video model.\n\n"
                         "**Extremely Important How To Use Parameters and Guide:** [Genmo Mochi 1 Text2Video Parameters](https://github.com/mcmonkeyprojects/SwarmUI/blob/master/docs/Video%20Model%20Support.md#genmo-mochi-1-text2video)"),
                "target_dir_key": "diffusion_models",
                "models": [
                    {"name": "Genmo Mochi 1 Preview T2V BF16", "repo_id": "Comfy-Org/mochi_preview_repackaged", "filename_in_repo": "mochi_preview_bf16.safetensors", "save_filename": "Genmo_Mochi_1_Text_to_Video.safetensors"},
                    {"name": "Genmo Mochi 1 Preview T2V FP8 Scaled", "repo_id": "Comfy-Org/mochi_preview_repackaged", "filename_in_repo": "mochi_preview_fp8_scaled.safetensors", "save_filename": "Genmo_Mochi_1_Text_to_Video_FP8_Scaled.safetensors"},
                ]
            },
             "Lightricks LTX Video Models - Ultra Fast": {
                 "info": (f"Ultra-fast text-to-video and image-to-video models from Lightricks. "
                          f"The companion 'LTX VAE (BF16)' is listed below and also in the VAEs section; it's recommended for the 13B Dev models. "
                          f"{GGUF_QUALITY_INFO} (for GGUF variants)\n\n"
                          "**Extremely Important How To Use Parameters and Guide:** [LTX Video Installation/Usage](https://github.com/mcmonkeyprojects/SwarmUI/blob/master/docs/Video%20Model%20Support.md#ltxv-install)"),
                 "target_dir_key": "diffusion_models", # Default for this sub-category (will be used by GGUFs)
                 "models": [
                    {"name": "LTX 2b T2V+I2V 768x512 v0.9.5", "repo_id": "Lightricks/LTX-Video", "filename_in_repo": "ltx-video-2b-v0.9.5.safetensors", "save_filename": "LTX_2b_V_0_9_5.safetensors", "target_dir_key": "Stable-Diffusion"},
                    {"name": "LTX 13B Dev T2V+I2V 0.9.7 (FP16/BF16)", "repo_id": "Lightricks/LTX-Video", "filename_in_repo": "ltxv-13b-0.9.7-dev.safetensors", "save_filename": "LTX_13B_Dev_V_0_9_7.safetensors", "target_dir_key": "Stable-Diffusion"},
                    {"name": "LTX 13B Dev T2V+I2V 0.9.7 FP8", "repo_id": "Lightricks/LTX-Video", "filename_in_repo": "ltxv-13b-0.9.7-dev-fp8.safetensors", "save_filename": "LTX_13B_Dev_V_0_9_7_FP8.safetensors", "target_dir_key": "Stable-Diffusion"},
                    # GGUF models will use the sub-category's default target_dir_key: "diffusion_models"
                    {"name": "LTX 13B Dev T2V+I2V 0.9.7 GGUF Q8_0", "repo_id": "wsbagnsv1/ltxv-13b-0.9.7-dev-GGUF", "filename_in_repo": "ltxv-13b-0.9.7-dev-Q8_0.gguf", "save_filename": "LTX_13B_Dev_V_0_9_7_GGUF_Q8_0.gguf"},
                    {"name": "LTX 13B Dev T2V+I2V 0.9.7 GGUF Q6_K", "repo_id": "wsbagnsv1/ltxv-13b-0.9.7-dev-GGUF", "filename_in_repo": "ltxv-13b-0.9.7-dev-Q6_K.gguf", "save_filename": "LTX_13B_Dev_V_0_9_7_GGUF_Q6_K.gguf"},
                    {"name": "LTX 13B Dev T2V+I2V 0.9.7 GGUF Q5_K_M", "repo_id": "wsbagnsv1/ltxv-13b-0.9.7-dev-GGUF", "filename_in_repo": "ltxv-13b-0.9.7-dev-Q5_K_M.gguf", "save_filename": "LTX_13B_Dev_V_0_9_7_GGUF_Q5_K_M.gguf"},
                    {"name": "LTX 13B Dev T2V+I2V 0.9.7 GGUF Q4_K_M", "repo_id": "wsbagnsv1/ltxv-13b-0.9.7-dev-GGUF", "filename_in_repo": "ltxv-13b-0.9.7-dev-Q4_K_M.gguf", "save_filename": "LTX_13B_Dev_V_0_9_7_GGUF_Q4_K_M.gguf"},
                    ltx_vae_companion_entry, # This entry has its own target_dir_key: "vae"
                 ]
             },
        }
    },
    "LoRA Models": {
        "info": "Readme for Wan 2.1 CausVid LoRA to Speed Up : [LoRA Models](https://github.com/mcmonkeyprojects/SwarmUI/blob/master/docs/Video%20Model%20Support.md#wan-causvid---high-speed-14b)",
        "sub_categories": {
            "Various LoRAs": {
                "info": "A collection of LoRA models.",
                "target_dir_key": "Lora",
                "models": [
                    {"name": "Migration LoRA Cloth (TTPlanet)", "repo_id": "TTPlanet/Migration_Lora_flux", "filename_in_repo": "Migration_Lora_cloth.safetensors", "save_filename": "Migration_Lora_cloth.safetensors"},
                    {"name": "Figures TTP Migration LoRA (TTPlanet)", "repo_id": "TTPlanet/Migration_Lora_flux", "filename_in_repo": "figures_TTP_Migration.safetensors", "save_filename": "figures_TTP_Migration.safetensors"},
                    wan_causvid_14b_lora_entry,
                    wan_causvid_1_3b_lora_entry,
                ]
            }
        }
    },
    "LLM Models": {
        "info": "Large Language Models (LLMs) used for various purposes, such as advanced text encoders or other functionalities.",
        "sub_categories": {
            "General LLMs": {
                "info": "Full LLM model repositories.",
                "target_dir_key": "LLM", # General target for this sub_category
                "models": [
                    {"name": "Meta-Llama-3.1-8B-Instruct (Full Repo)", "repo_id": "unsloth/Meta-Llama-3.1-8B-Instruct", "is_snapshot": True, "target_dir_key": "LLM_unsloth_llama"}
                ]
            }
        }
    },
    "VAE Models": {
        "info": "Variational Autoencoder models, used to improve image quality and details.",
        "sub_categories": {
            "Most Common VAEs (e.g. FLUX and HiDream-I1)": {
                "info": "VAEs commonly used with various models like FLUX and HiDream.",
                "target_dir_key": "vae", # Correct target directory
                "models": [
                    {"name": "FLUX VAE as FLUX_VAE.safetensors (Used by FLUX, HiDream, etc.)", "repo_id": "MonsterMMORPG/Kohya_Train", "filename_in_repo": "ae.safetensors", "save_filename": "FLUX_VAE.safetensors"},
                    {"name": "FLUX VAE as ae.safetensors", "repo_id": "MonsterMMORPG/Kohya_Train", "filename_in_repo": "ae.safetensors", "save_filename": "ae.safetensors"},
                    ltx_vae_companion_entry, # Added the VAE companion here
                ]
            },
        }
    },
    "Clip Vision Models": {
        "info": "Vision encoder models, e.g., for image understanding or as part of larger multi-modal systems.",
        "sub_categories": {
            "SigLIP Vision Models": {
                "info": "Sigmoid-Loss for Language-Image Pre-Training (SigLIP) vision encoders. These are typically used by specific model architectures that require them.",
                "target_dir_key": "clip_vision",
                "models": [
                    {
                        "name": "SigLIP Vision Patch14 384px",
                        "repo_id": "Comfy-Org/sigclip_vision_384",
                        "filename_in_repo": "sigclip_vision_patch14_384.safetensors",
                        "save_filename": "sigclip_vision_patch14_384.safetensors"
                    },
                    {
                        "name": "SigLIP SO400M Patch14 384px (Full Repo)",
                        "repo_id": "google/siglip-so400m-patch14-384",
                        "is_snapshot": True,
                        "target_dir_key": "clip_vision_google_siglip"
                    }
                ]
            }
        }
    },
    "ComfyUI Workflows": {
        "info": "Downloadable ComfyUI workflow JSON files or related assets.",
        "sub_categories": {
            "Captioning Workflows": {
                "info": "Workflows and assets related to image captioning.",
                "target_dir_key": "Joy_caption", # General target for this sub_category
                "models": [
                    {"name": "Joy Caption Alpha Two (Full Repo)", "repo_id": "MonsterMMORPG/joy-caption-alpha-two", "is_snapshot": True, "target_dir_key": "Joy_caption_monster_joy"}
                ]
            }
        }
    },
    "ComfyUI Workflows Bundles": {
        "info": "Download pre-defined bundles for specific ComfyUI workflows, including models and related assets.",
        "bundles": [
            {
                "name": "Clothing Migration Workflow Bundle",
                "info": (
                    "Downloads all necessary models and assets for the Clothing Migration workflow in ComfyUI (SwarmUI backend).\n\n"
                    "**Includes:**\n"
                    "- Joy Caption Alpha Two (Captioning Assets)\n"
                    "- Migration LoRA Cloth (TTPlanet)\n"
                    "- Figures TTP Migration LoRA (TTPlanet)\n"
                    "- SigLIP SO400M Patch14 384px (Full Repo)\n"
                    "- Meta-Llama-3.1-8B-Instruct (LLM for advanced text processing if needed by workflow)\n"
                    "- FLUX VAE (Standard VAE, saved as ae.safetensors)\n"
                    "- FLUX DEV ControlNet Inpainting Beta (Alimama) (ControlNet for inpainting)\n"
                    "- T5 XXL FP16 (Text Encoder)\n"
                    "- CLIP-SAE-ViT-L-14 (CLIP L Text Encoder, saved as clip_l.safetensors)\n"
                    "\n"
                    "**Important:** Ensure your ComfyUI setup and the specific workflow are configured to use these models in their respective SwarmUI model paths. "
                    "This bundle downloads models to their default SwarmUI locations (e.g., Models/Lora, Models/LLM, Models/controlnet, etc.)."
                ),
                "models_to_download": [
                    ("ComfyUI Workflows", "Captioning Workflows", "Joy Caption Alpha Two (Full Repo)"),
                    ("LoRA Models", "Various LoRAs", "Migration LoRA Cloth (TTPlanet)"),
                    ("LoRA Models", "Various LoRAs", "Figures TTP Migration LoRA (TTPlanet)"),
                    ("Clip Vision Models", "SigLIP Vision Models", "SigLIP SO400M Patch14 384px (Full Repo)"),
                    ("LLM Models", "General LLMs", "Meta-Llama-3.1-8B-Instruct (Full Repo)"),
                    ("VAE Models", "Most Common VAEs (e.g. FLUX and HiDream-I1)", "FLUX VAE as ae.safetensors"),
                    ("Image Generation Models", "FLUX Models", "FLUX DEV ControlNet Inpainting Beta (Alimama)"),
                    ("Text Encoder Models", "T5 XXL Models", "T5 XXL FP16"),
                    ("Text Encoder Models", "Clip Models", "CLIP-SAE-ViT-L-14 (Save As clip_l.safetensors - SwarmUI default name)"),
                ]
            },
        ]
    },
}


def get_default_base_path():
    """Determines the default base path based on the OS and known paths."""
    system = platform.system()
    if system == "Windows":
        swarm_path = os.environ.get("SWARM_MODEL_PATH")
        if swarm_path and os.path.isdir(swarm_path): return swarm_path
        return os.path.join(os.getcwd(), "SwarmUI", "Models")
    else:  # Linux/Unix systems
        swarm_path = os.environ.get("SWARM_MODEL_PATH")
        if swarm_path and os.path.isdir(swarm_path): return swarm_path
        if os.path.exists("/home/Ubuntu/apps/StableSwarmUI"):
            return "/home/Ubuntu/apps/StableSwarmUI/Models"
        elif os.path.exists("/workspace/SwarmUI"):
            return "/workspace/SwarmUI/Models"
        else:
            return os.path.join(os.getcwd(), "SwarmUI", "Models")

DEFAULT_BASE_PATH = get_default_base_path()

BASE_SUBDIRS = { # Renamed from SUBDIRS
    "vae": "vae",
    "diffusion_models": "diffusion_models",
    "Stable-Diffusion": "Stable-Diffusion",
    "clip": "clip",
    "clip_vision": "clip_vision",
    "yolov8": "yolov8",
    "style_models": "style_models",
    "Lora": "Lora", # Default Lora, will be changed if ComfyUI mode is on
    "upscale_models": "upscale_models",
    "LLM": "LLM",
    "Joy_caption": "Joy_caption",
    "clip_vision_google_siglip": "clip_vision/google--siglip-so400m-patch14-384",
    "LLM_unsloth_llama": "LLM/unsloth--Meta-Llama-3.1-8B-Instruct",
    "Joy_caption_monster_joy": "Joy_caption/cgrkzexw-599808",
    "controlnet": "controlnet",
}

def get_current_subdirs(is_comfy_ui_structure: bool):
    """Returns the subdirectory mapping based on ComfyUI structure flag."""
    current_s = BASE_SUBDIRS.copy()
    if is_comfy_ui_structure:
        current_s["Lora"] = "loras" # Change Lora to loras for ComfyUI
    return current_s

def find_actual_cased_directory_component(parent_dir: str, component_name: str) -> str | None:
    """
    Finds an existing directory component case-insensitively within parent_dir.
    Returns the actual cased name if found as a directory, otherwise None.
    """
    if not os.path.isdir(parent_dir):
        return None
    name_lower = component_name.lower()
    try:
        for item in os.listdir(parent_dir):
            if item.lower() == name_lower:
                if os.path.isdir(os.path.join(parent_dir, item)):
                    return item
    except OSError: # Permission denied, etc.
        pass
    return None

def resolve_target_directory(base_dir: str, relative_path_str: str) -> str:
    """
    Resolves/constructs a target directory path. On non-Windows systems,
    it attempts to find existing path components case-insensitively.
    The returned path is what should be used for os.makedirs().
    """
    # Normalize relative_path_str once
    normalized_relative_path = os.path.normpath(relative_path_str)

    if platform.system() == "Windows":
        return os.path.join(base_dir, normalized_relative_path)

    # Linux/Mac
    current_path = base_dir
    # Split normalized_relative_path into components
    components = []
    head, tail = os.path.split(normalized_relative_path)
    while tail:
        components.insert(0, tail)
        head, tail = os.path.split(head)
    if head: # If there's a remaining head (e.g. from an absolute path, though not expected here)
        components.insert(0, head)
    
    # Filter out empty or "." components that might result from normpath or splitting
    components = [comp for comp in components if comp and comp != '.']


    for component in components:
        actual_cased_comp = None
        if os.path.isdir(current_path): # Only scan if parent is an existing directory
             actual_cased_comp = find_actual_cased_directory_component(current_path, component)

        if actual_cased_comp:
            current_path = os.path.join(current_path, actual_cased_comp)
        else:
            current_path = os.path.join(current_path, component)
            
    return current_path


def ensure_directories_exist(base_path: str, is_comfy_ui_structure: bool):
    """Creates the base Models directory and all predefined subdirectories, respecting ComfyUI structure if enabled."""
    if not base_path:
        print("ERROR: Base path is empty, cannot ensure directories.")
        return "Error: Base path is empty.", ["Base path is empty"]

    subdirs_to_use = get_current_subdirs(is_comfy_ui_structure)
    
    all_dirs_to_ensure = [base_path]
    for subdir_value in subdirs_to_use.values():
        resolved_full_path = resolve_target_directory(base_path, subdir_value)
        all_dirs_to_ensure.append(resolved_full_path)
    
    # Remove duplicates that might arise from resolve_target_directory if paths already exist with different casing
    all_dirs_to_ensure = sorted(list(set(all_dirs_to_ensure)))


    created_count = 0
    verified_count = 0
    errors = []

    for directory_path_str in all_dirs_to_ensure:
        try:
            # resolve_target_directory already gives the path to be created or that exists
            norm_dir = os.path.normpath(directory_path_str)
            if not os.path.exists(norm_dir):
                os.makedirs(norm_dir, exist_ok=True)
                print(f"Created directory: {norm_dir}")
                created_count += 1
            else:
                verified_count += 1
        except OSError as e:
            error_msg = f"ERROR creating directory {directory_path_str} (normalized: {norm_dir}): {str(e)}"
            print(error_msg)
            errors.append(error_msg)
        except Exception as e:
            error_msg = f"UNEXPECTED ERROR with directory {directory_path_str}: {str(e)}"
            print(error_msg)
            errors.append(error_msg)

    status = f"Directory check complete for '{base_path}' (ComfyUI mode: {is_comfy_ui_structure}). Created: {created_count}, Verified Existing: {verified_count}."
    if errors:
        status += f" Errors: {len(errors)} (see console)."
    print(status)
    return status, errors

# --- Download Queue and Worker ---

download_queue = queue.Queue()
status_updates = queue.Queue()
stop_worker = threading.Event()
log_history = []
log_lock = threading.Lock()

def add_log(message):
    """Adds a message to the log history and prints it."""
    print(message)
    with log_lock:
        log_history.append(f"[{time.strftime('%H:%M:%S')}] {message}")
        if len(log_history) > 100:
            log_history.pop(0)
    if status_updates:
        try:
            log_str = "\n".join(map(str, log_history))
            status_updates.put_nowait(log_str) 
        except queue.Full:
            print("Warning: Status update queue is full, skipping update.") 
        except Exception as e:
            print(f"Error putting log update to queue: {e}")


def get_target_path(base_path: str, model_info: dict, sub_category_info: dict, is_comfy_ui_structure: bool) -> str:
    """Determines the full target directory path for a model, respecting ComfyUI structure."""
    subdirs_to_use = get_current_subdirs(is_comfy_ui_structure)
    target_key = model_info.get("target_dir_key") or sub_category_info.get("target_dir_key")

    if not target_key or target_key not in subdirs_to_use: # Check against current subdirs
        model_name = model_info.get('name', 'Unknown Model')
        sub_cat_name = sub_category_info.get('name', 'Unknown SubCategory') 
        if target_key:
            add_log(f"WARNING: Invalid 'target_dir_key' ('{target_key}') for {model_name} in {sub_cat_name}. Using default 'diffusion_models'.")
        else:
            add_log(f"WARNING: Missing 'target_dir_key' for {model_name} in {sub_cat_name}. Using default 'diffusion_models'.")
        target_key = "diffusion_models" 

    target_subdir_name = subdirs_to_use.get(target_key, "diffusion_models") # Get from current subdirs
    
    # Resolve the actual target directory, handling case insensitivity on Linux
    target_dir = resolve_target_directory(base_path, target_subdir_name)

    try:
        os.makedirs(target_dir, exist_ok=True)
    except Exception as e:
        add_log(f"ERROR: Could not ensure target directory {target_dir} exists: {e}")
    return target_dir

def _download_model_internal(model_info, sub_category_info, base_path, use_hf_transfer, is_comfy_ui_structure):
    """Handles the download of a single model or snapshot directly to the target folder."""
    model_name = model_info.get('name', model_info.get('repo_id'))
    repo_id = model_info.get('repo_id')
    filename = model_info.get('filename_in_repo') 
    save_filename = model_info.get('save_filename') 
    is_snapshot = model_info.get('is_snapshot', False)
    allow_patterns = model_info.get('allow_patterns')
    pre_delete = model_info.get('pre_delete_target', False)
    allow_overwrite = model_info.get('allow_overwrite', False)

    if not repo_id:
        add_log(f"ERROR: Missing 'repo_id' for model {model_name}. Skipping.")
        return
    if not base_path:
        add_log(f"ERROR: Missing 'base_path' for model {model_name}. Skipping.")
        return

    target_dir = get_target_path(base_path, model_info, sub_category_info, is_comfy_ui_structure)
    if not os.path.isdir(target_dir): # Re-check after get_target_path's makedirs attempt
         add_log(f"ERROR: Target directory {target_dir} could not be confirmed for {model_name}. Skipping.")
         return

    final_target_path = os.path.join(target_dir, save_filename) if save_filename else None

    if pre_delete and final_target_path and os.path.exists(final_target_path):
        try:
            if os.path.isfile(final_target_path):
                 os.remove(final_target_path)
                 add_log(f"INFO: Pre-deleted existing final target file: {final_target_path}")
            else:
                 add_log(f"WARNING: Pre-delete requested, but final target path is not a file: {final_target_path}")
        except OSError as e:
            add_log(f"WARNING: Could not pre-delete existing final target file {final_target_path}: {e}. Proceeding download attempt.")

    if not is_snapshot and final_target_path and os.path.exists(final_target_path) and not allow_overwrite and not pre_delete: # Added not pre_delete condition
        add_log(f"INFO: Final target file '{final_target_path}' already exists and overwrite/pre-delete not allowed. Skipping download for '{model_name}'.")
        return

    if is_snapshot:
        snapshot_target_dir_exists = os.path.exists(target_dir)
        snapshot_target_dir_populated = snapshot_target_dir_exists and len(os.listdir(target_dir)) > 0 # Use os.listdir on resolved target_dir
        if snapshot_target_dir_populated and not allow_overwrite:
             add_log(f"INFO: Snapshot target directory '{target_dir}' exists and seems populated. Skipping snapshot download for '{repo_id}' as overwrite not allowed.")
             return

    add_log(f"Starting download: {model_name}...")
    try:
        start_time = time.time()
        actual_downloaded_path = None 

        if is_snapshot:
            add_log(f" -> Downloading snapshot from {repo_id} directly to {target_dir}...")
            actual_downloaded_path = snapshot_download(
                repo_id=repo_id,
                local_dir=target_dir, # Use resolved target_dir
                local_dir_use_symlinks=False,
                allow_patterns=allow_patterns,
                force_download=allow_overwrite, 
            )
            add_log(f" -> Snapshot download complete for {repo_id} into {actual_downloaded_path}.")
            final_target_path = actual_downloaded_path

        elif filename and save_filename and final_target_path:
            add_log(f" -> Downloading file '{filename}' from {repo_id} into '{target_dir}' (preserving structure from filename)...")

            force_the_download = allow_overwrite or pre_delete 

            actual_downloaded_path = hf_hub_download(
                repo_id=repo_id,
                filename=filename,
                local_dir=target_dir, # Use resolved target_dir
                local_dir_use_symlinks=False, 
                force_download=force_the_download, 
            )
            add_log(f" -> File downloaded to actual path: {actual_downloaded_path}")

            if actual_downloaded_path != final_target_path:
                add_log(f" -> Renaming '{actual_downloaded_path}' to '{final_target_path}'...")

                os.makedirs(os.path.dirname(final_target_path), exist_ok=True)

                if os.path.exists(final_target_path):
                    if allow_overwrite or pre_delete:
                        add_log(f" -> Final target path {final_target_path} exists. Removing before rename...")
                        try:
                            if os.path.isfile(final_target_path):
                                os.remove(final_target_path)
                            else:
                                add_log(f" -> WARNING: Cannot remove final target path as it's not a file: {final_target_path}")
                                raise OSError(f"Target path for rename is not a file: {final_target_path}")
                        except OSError as e:
                            add_log(f"ERROR: Failed to remove existing file at final path '{final_target_path}' before rename: {e}. Aborting rename.")
                            raise e 
                    else:
                        add_log(f"ERROR: Final target path {final_target_path} exists and overwrite not allowed. Cannot rename. Downloaded file remains at '{actual_downloaded_path}'.")
                        return 
                try:
                    os.rename(actual_downloaded_path, final_target_path)
                    add_log(f" -> Successfully renamed to: {final_target_path}")
                except OSError as e:
                    add_log(f"ERROR: Failed to rename '{actual_downloaded_path}' to '{final_target_path}': {e}")
                    add_log(f" -> The originally downloaded file likely remains at: {actual_downloaded_path}")
                    raise e 
            else:
                add_log(f" -> Actual download path matches desired final path. No rename needed.")

        else:
             if is_snapshot: 
                 add_log(f"ERROR: Internal logic error for snapshot {model_name}. Skipping.")
             elif not filename:
                  add_log(f"ERROR: Invalid configuration for model {model_name}. Missing 'filename_in_repo'. Skipping.")
             elif not save_filename:
                  add_log(f"ERROR: Invalid configuration for model {model_name}. Missing 'save_filename'. Skipping.")
             else:
                  add_log(f"ERROR: Invalid configuration for model {model_name}. Path issue? Skipping.")
             return 

        end_time = time.time()
        success_path = final_target_path if not is_snapshot else actual_downloaded_path 
        add_log(f"SUCCESS: Downloaded and processed {model_name} in {end_time - start_time:.2f} seconds. Final location: {success_path}")

    except (HfHubHTTPError, HFValidationError) as e:
        add_log(f"ERROR downloading {model_name} (HF Hub): {type(e).__name__} - {str(e)}")
    except FileNotFoundError as e:
         add_log(f"ERROR during file operation for {model_name} (File System): {type(e).__name__} - {str(e)}")
    except OSError as e:
         add_log(f"ERROR during file operation (rename/delete) for {model_name} (OS Error/Permissions): {type(e).__name__} - {str(e)}")
    except Exception as e:
        add_log(f"UNEXPECTED ERROR during download/process for {model_name}: {type(e).__name__} - {str(e)}")
        if 'actual_downloaded_path' in locals() and actual_downloaded_path:
             add_log(f" -> State before error: actual_downloaded_path='{actual_downloaded_path}'")
        if 'final_target_path' in locals() and final_target_path:
             add_log(f" -> State before error: final_target_path='{final_target_path}'")

def download_worker():
    """Worker thread function to process the download queue."""
    print("Download worker thread started.")
    while not stop_worker.is_set():
        try:
            task = download_queue.get(timeout=1)
        except queue.Empty:
            continue

        model_info, sub_category_info, base_path, use_hf_transfer, is_comfy_ui_structure = task # Added is_comfy_ui_structure
        original_hf_transfer_env = None
        try:
            original_hf_transfer_env = os.environ.get('HF_HUB_ENABLE_HF_TRANSFER')
            transfer_env_value = '1' if use_hf_transfer and HF_TRANSFER_AVAILABLE else '0'
            os.environ['HF_HUB_ENABLE_HF_TRANSFER'] = transfer_env_value
            
            _download_model_internal(model_info, sub_category_info, base_path, use_hf_transfer, is_comfy_ui_structure) # Pass is_comfy_ui_structure

        except Exception as e:
            model_name_for_log = model_info.get('name', 'unknown task')
            add_log(f"CRITICAL WORKER ERROR processing '{model_name_for_log}': {type(e).__name__} - {e}")
        finally:
            if original_hf_transfer_env is None:
                if 'HF_HUB_ENABLE_HF_TRANSFER' in os.environ:
                    del os.environ['HF_HUB_ENABLE_HF_TRANSFER']
            else:
                os.environ['HF_HUB_ENABLE_HF_TRANSFER'] = original_hf_transfer_env
            download_queue.task_done()
    print("Download worker thread stopped.")


# --- Filtering Logic ---
# No changes needed in filter_models for this request.
def filter_models(structure, search_term):
    search_term = search_term.lower().strip()
    visibility = {} 
    if not search_term:
        for cat_name, cat_data in structure.items():
            cat_key = f"cat_{cat_name}"
            visibility[cat_key] = True
            if "sub_categories" in cat_data:
                for sub_cat_name in cat_data["sub_categories"]:
                    sub_cat_key = f"subcat_{cat_name}_{sub_cat_name}"
                    visibility[sub_cat_key] = True
            elif "bundles" in cat_data:
                for i, bundle_data in enumerate(cat_data["bundles"]):
                     bundle_key = f"bundle_{cat_name}_{i}"
                     visibility[bundle_key] = True
                     bundle_button_key = f"bundlebutton_{cat_name}_{i}"
                     visibility[bundle_button_key] = True
        return visibility
    for cat_name, cat_data in structure.items():
        cat_key = f"cat_{cat_name}"
        visibility[cat_key] = False 
        if "sub_categories" in cat_data:
            for sub_cat_name in cat_data["sub_categories"]:
                sub_cat_key = f"subcat_{cat_name}_{sub_cat_name}"
                visibility[sub_cat_key] = False
        elif "bundles" in cat_data:
             for i, bundle_data in enumerate(cat_data["bundles"]):
                 bundle_key = f"bundle_{cat_name}_{i}"
                 visibility[bundle_key] = False
                 bundle_button_key = f"bundlebutton_{cat_name}_{i}"
                 visibility[bundle_button_key] = False
    for cat_name, cat_data in structure.items():
        cat_key = f"cat_{cat_name}"
        cat_match = search_term in cat_name.lower()
        cat_becomes_visible = cat_match 
        if "sub_categories" in cat_data:
            for sub_cat_name, sub_cat_data in cat_data["sub_categories"].items():
                sub_cat_key = f"subcat_{cat_name}_{sub_cat_name}"
                sub_cat_match = search_term in sub_cat_name.lower()
                sub_cat_becomes_visible = sub_cat_match 
                model_match_found = False
                for model_info in sub_cat_data.get("models", []):
                    model_name = model_info.get("name", "").lower()
                    if search_term in model_name:
                        model_match_found = True
                        break 
                if model_match_found or sub_cat_match:
                    visibility[sub_cat_key] = True 
                    cat_becomes_visible = True 
            if cat_becomes_visible:
                 visibility[cat_key] = True 
        elif "bundles" in cat_data:
             bundle_match_found_in_cat = False
             for i, bundle_data in enumerate(cat_data["bundles"]):
                 bundle_key = f"bundle_{cat_name}_{i}"
                 bundle_button_key = f"bundlebutton_{cat_name}_{i}"
                 bundle_name = bundle_data.get("name", "").lower()
                 bundle_info = bundle_data.get("info", "").lower() 
                 if search_term in bundle_name or search_term in bundle_info:
                     visibility[bundle_key] = True
                     visibility[bundle_button_key] = True
                     bundle_match_found_in_cat = True
             if bundle_match_found_in_cat or cat_match: 
                 visibility[cat_key] = True
    return visibility

# --- Bundle Helper ---
# No changes needed in find_model_by_key for this request.
def find_model_by_key(category_name, sub_category_name, model_name):
    try:
        category_data = models_structure[category_name]
        sub_category_data = category_data["sub_categories"][sub_category_name]
        for model_info in sub_category_data["models"]:
            if model_info["name"] == model_name:
                return model_info, sub_category_data
        add_log(f"ERROR: Model '{model_name}' not found in '{category_name}' -> '{sub_category_name}'.")
        return None, None
    except KeyError:
        add_log(f"ERROR: Category '{category_name}' or Sub-category '{sub_category_name}' not found while searching for model '{model_name}'.")
        return None, None
    except Exception as e:
        add_log(f"ERROR: Unexpected error finding model '{model_name}': {e}")
        return None, None


# --- Gradio UI Builder ---

def create_ui(default_base_path):
    """Creates the Gradio interface."""
    tracked_components = {}

    with gr.Blocks(theme=gr.themes.Soft(), title=APP_TITLE) as app:
        gr.Markdown(f"## {APP_TITLE} V40 > Source : https://www.patreon.com/posts/114517862")
        gr.Markdown(f"### ComfyUI Installer for SwarmUI's Back-End > https://www.patreon.com/posts/105023709")
        gr.Markdown(f"### 5 May 2025 Main How To Install & Use Tutorial : https://youtu.be/fTzlQ0tjxj0")
        gr.Markdown(f"### 19 May 2025 Wan 2.1 I2V & T2V With CausVid LoRA Tutorial : https://youtu.be/fTzlQ0tjxj0")
        gr.Markdown("### Select models or bundles to download. Downloads will be added to a queue. Use the search bar to filter.")

        log_output = gr.Textbox(label="Download Status / Log - Watch CMD / Terminal To See Download Status & Speed", lines=10, max_lines=20, interactive=False, value="Welcome! Logs will appear here.")
        queue_status_label = gr.Markdown(f"Queue Size: {download_queue.qsize()}")

        with gr.Row():
             search_box = gr.Textbox(placeholder="Search models or bundles...", label="Search", scale=2, interactive=True)
             use_hf_transfer_checkbox = gr.Checkbox(label="Enable hf_transfer (Faster Downloads)", value=HF_TRANSFER_AVAILABLE, scale=1)
        
        with gr.Row():
             base_path_input = gr.Textbox(label="Base Download Path (SwarmUI/Models)", value=default_base_path, scale=3)
             comfy_ui_structure_checkbox = gr.Checkbox(label="ComfyUI Folder Structure (e.g. 'loras' folder)", value=False, scale=1)


        # Initial directory check with default ComfyUI structure (False)
        initial_dir_status, _ = ensure_directories_exist(default_base_path, False) # Pass comfy_ui_structure_checkbox.value (default False)
        add_log(f"Initial directory check: {initial_dir_status}")

        def update_hf_transfer_setting(value):
            add_log(f"User {'enabled' if value else 'disabled'} hf_transfer checkbox.")

        use_hf_transfer_checkbox.change(fn=update_hf_transfer_setting, inputs=use_hf_transfer_checkbox, outputs=None)

        def handle_dir_structure_change(current_base_path, is_comfy_checked):
            status_msg, _ = ensure_directories_exist(current_base_path, is_comfy_checked)
            add_log(f"Directory structure updated due to change: {status_msg}")
            # No direct output to UI component from here, log is sufficient.
            # Or return status_msg to a dedicated status gr.Markdown if needed.

        comfy_ui_structure_checkbox.change(
            fn=handle_dir_structure_change,
            inputs=[base_path_input, comfy_ui_structure_checkbox],
            outputs=None # Log output is handled by add_log
        )
        base_path_input.change( # Assuming base_path_input doesn't have other .change events that would conflict. If so, combine logic.
            fn=handle_dir_structure_change,
            inputs=[base_path_input, comfy_ui_structure_checkbox],
            outputs=None # Log output is handled by add_log
        )


        def enqueue_download(model_info, sub_category_info, current_base_path, hf_transfer_enabled, is_comfy_checked):
            if not current_base_path:
                 add_log("ERROR: Cannot queue download, base path input is empty.")
                 return f"Queue Size: {download_queue.qsize()}"
            if not isinstance(sub_category_info, dict):
                add_log(f"ERROR: Invalid sub_category_info type ({type(sub_category_info)}) for model {model_info.get('name')}. Skipping queue.")
                return f"Queue Size: {download_queue.qsize()}"

            download_queue.put((model_info, sub_category_info, current_base_path, hf_transfer_enabled, is_comfy_checked))
            add_log(f"Queued: {model_info.get('name', model_info.get('repo_id'))}")
            return f"Queue Size: {download_queue.qsize()}"

        def enqueue_bulk_download(models_list, sub_category_info, current_base_path, hf_transfer_enabled, is_comfy_checked):
            if not current_base_path:
                 add_log("ERROR: Cannot queue bulk download, base path input is empty.")
                 return f"Queue Size: {download_queue.qsize()}"
            if not isinstance(sub_category_info, dict):
                add_log(f"ERROR: Invalid sub_category_info type ({type(sub_category_info)}) for bulk download. Skipping queue.")
                return f"Queue Size: {download_queue.qsize()}"

            count = 0
            sub_cat_name = sub_category_info.get("name", "Group") 
            for model_info in models_list:
                 download_queue.put((model_info, sub_category_info, current_base_path, hf_transfer_enabled, is_comfy_checked))
                 count += 1
            add_log(f"Queued {count} models from '{sub_cat_name}'.")
            return f"Queue Size: {download_queue.qsize()}"

        def enqueue_bundle_download(bundle_definition, current_base_path, hf_transfer_enabled, is_comfy_checked):
            if not current_base_path:
                add_log("ERROR: Cannot queue bundle download, base path input is empty.")
                return f"Queue Size: {download_queue.qsize()}"

            bundle_name = bundle_definition.get("name", "Unnamed Bundle")
            model_keys = bundle_definition.get("models_to_download", [])
            queued_count = 0
            errors = 0

            add_log(f"Queueing bundle: '{bundle_name}'...")
            for cat_name, sub_cat_name, model_name in model_keys:
                model_info, sub_cat_info = find_model_by_key(cat_name, sub_cat_name, model_name)
                if model_info and sub_cat_info:
                    # Use the standard enqueue function, passing comfy_checked state
                    enqueue_download(model_info, sub_cat_info, current_base_path, hf_transfer_enabled, is_comfy_checked)
                    queued_count += 1
                else:
                    errors += 1
                    add_log(f"  -> ERROR: Could not find model '{model_name}' for bundle. Skipping.")

            add_log(f"Bundle '{bundle_name}' processed. Queued: {queued_count}, Errors: {errors}.")
            return f"Queue Size: {download_queue.qsize()}"

        for cat_name, cat_data in models_structure.items():
            cat_key = f"cat_{cat_name}"
            with gr.Accordion(cat_name, open=False, visible=True) as cat_accordion: 
                tracked_components[cat_key] = cat_accordion 
                if "bundles" in cat_data:
                    gr.Markdown(cat_data.get("info", ""))
                    for i, bundle_info in enumerate(cat_data.get("bundles", [])):
                        bundle_key = f"bundle_{cat_name}_{i}"
                        bundle_button_key = f"bundlebutton_{cat_name}_{i}"
                        bundle_display_name = bundle_info.get("name", f"Bundle {i+1}")
                        with gr.Column(variant="panel", visible=True) as bundle_container:
                            tracked_components[bundle_key] = bundle_container 
                            gr.Markdown(f"**{bundle_display_name}**")
                            gr.Markdown(bundle_info.get("info", "*No description provided.*"))
                            download_bundle_button = gr.Button(f"Download {bundle_display_name}")
                            tracked_components[bundle_button_key] = download_bundle_button 
                            download_bundle_button.click(
                                fn=enqueue_bundle_download,
                                inputs=[
                                    gr.State(bundle_info), 
                                    base_path_input,
                                    use_hf_transfer_checkbox,
                                    comfy_ui_structure_checkbox # Pass new checkbox state
                                ],
                                outputs=[queue_status_label]
                             )
                elif "sub_categories" in cat_data:
                    gr.Markdown(cat_data.get("info", ""))
                    for sub_cat_name, sub_cat_data in cat_data.get("sub_categories", {}).items():
                        sub_cat_key = f"subcat_{cat_name}_{sub_cat_name}"
                        with gr.Column(variant="panel", elem_classes="sub-category-panel", visible=True) as subcat_container: 
                            tracked_components[sub_cat_key] = subcat_container 
                            with gr.Accordion(sub_cat_name, open=False): 
                                gr.Markdown(sub_cat_data.get("info", ""))
                                models_in_subcat = sub_cat_data.get("models", [])
                                if not models_in_subcat:
                                    gr.Markdown("*No models listed in this sub-category yet.*")
                                    continue
                                for model_info in models_in_subcat:
                                    model_display_name = model_info.get("name", "Unknown Model")
                                    display_text = f"- {model_display_name}"
                                    with gr.Row():
                                        gr.Markdown(display_text)
                                        download_button = gr.Button("Download")
                                        sub_cat_state_data = sub_cat_data.copy()
                                        if 'name' not in sub_cat_state_data:
                                            sub_cat_state_data['name'] = sub_cat_name
                                        download_button.click(
                                            fn=enqueue_download,
                                            inputs=[
                                                gr.State(model_info),
                                                gr.State(sub_cat_state_data), 
                                                base_path_input,
                                                use_hf_transfer_checkbox,
                                                comfy_ui_structure_checkbox # Pass new checkbox state
                                            ],
                                            outputs=[queue_status_label]
                                        )
                                if models_in_subcat:
                                     with gr.Row():
                                         gr.Markdown("---")
                                     with gr.Row():
                                         download_all_button = gr.Button(f"Download All {sub_cat_name}")
                                         sub_cat_state_data_all = sub_cat_data.copy()
                                         if 'name' not in sub_cat_state_data_all:
                                             sub_cat_state_data_all['name'] = sub_cat_name
                                         download_all_button.click(
                                             fn=enqueue_bulk_download,
                                             inputs=[
                                                 gr.State(models_in_subcat),
                                                 gr.State(sub_cat_state_data_all), 
                                                 base_path_input,
                                                 use_hf_transfer_checkbox,
                                                 comfy_ui_structure_checkbox # Pass new checkbox state
                                             ],
                                             outputs=[queue_status_label]
                                         )
                else:
                     gr.Markdown(cat_data.get("info", "*No sub-categories or bundles defined.*"))

        def update_model_visibility(search_term: str):
            visibility_flags = filter_models(models_structure, search_term)
            updates = {}
            for key, component in tracked_components.items():
                should_be_visible = visibility_flags.get(key, False)
                updates[component] = gr.update(visible=should_be_visible)
            return updates

        search_box.change(
            fn=update_model_visibility,
            inputs=[search_box],
            outputs=list(tracked_components.values()) 
        )

        try:
            timer = gr.Timer(1, active=True) 
            def update_log_display():
                log_update = gr.update() 
                queue_update = gr.update() 
                new_log_available = False
                try:
                    latest_log = status_updates.get_nowait()
                    log_update = latest_log 
                    new_log_available = True
                except queue.Empty:
                    pass 
                q_size = download_queue.qsize()
                queue_update = f"Queue Size: {q_size}"
                return log_update, queue_update
            timer.tick(update_log_display, None, [log_output, queue_status_label])
            add_log("Using gr.Timer for UI updates.")
        except AttributeError:
            add_log("gr.Timer not found, falling back to deprecated app.load(every=1) for UI updates.")
            def update_log_display_legacy():
                 log_update = gr.update()
                 queue_update = gr.update()
                 try:
                     latest_log = status_updates.get_nowait()
                     log_update = latest_log
                 except queue.Empty:
                     pass
                 q_size = download_queue.qsize()
                 queue_update = f"Queue Size: {q_size}"
                 return {log_output: log_update, queue_status_label: queue_update}
            app.load(update_log_display_legacy, None, [log_output, queue_status_label], every=1)
    return app

# --- Main Execution ---

def get_available_drives():
    """Detect available drives on the system regardless of OS"""
    available_paths = []
    if platform.system() == "Windows":
        import string
        from ctypes import windll
        drives = []
        try:
            bitmask = windll.kernel32.GetLogicalDrives()
            for letter in string.ascii_uppercase:
                if bitmask & 1: drives.append(f"{letter}:\\")
                bitmask >>= 1
            available_paths = drives
        except Exception as e:
            print(f"Warning: Could not get Windows drives via ctypes: {e}")
            available_paths = ["C:\\"] # Fallback
    elif platform.system() == "Darwin":
         available_paths = ["/", "/Volumes"]
    else: # Linux/Other
        available_paths = ["/", "/mnt", "/media", "/run/media"] 

    existing_paths = [p for p in available_paths if os.path.isdir(p)]
    try:
        home_dir = os.path.expanduser("~")
        if os.path.isdir(home_dir) and home_dir not in existing_paths:
            is_sub = False
            for p in existing_paths:
                try:
                    norm_p = os.path.normpath(p)
                    norm_home = os.path.normpath(home_dir)
                    if os.path.commonpath([norm_p, norm_home]) == norm_p:
                        is_sub = True
                        break
                except ValueError: pass 
                except Exception: pass 
            if not is_sub:
                existing_paths.append(home_dir)
    except Exception as e:
        print(f"Warning: Could not reliably determine home directory: {e}")
    try:
        cwd = os.getcwd()
        is_subpath = False
        for p in existing_paths:
            try:
                norm_p = os.path.normpath(p)
                norm_cwd = os.path.normpath(cwd)
                if os.path.commonpath([norm_p, norm_cwd]) == norm_p:
                     is_subpath = True
                     break
            except ValueError: pass 
            except Exception as e:
                 print(f"Warning: Error checking common path for {p} and {cwd}: {e}")
        if not is_subpath and os.path.isdir(cwd) and cwd not in existing_paths:
             existing_paths.append(cwd)
    except Exception as e:
        print(f"Warning: Could not reliably determine current working directory: {e}")
    print(f"Detected potential root paths: {existing_paths}")
    return existing_paths

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="SwarmUI Model Downloader - Direct Download Version with Search and Bundles")
    parser.add_argument("--share", action="store_true", help="Enable Gradio sharing link")
    parser.add_argument("--model-path", type=str, default=None, help="Override default SwarmUI Models path")
    args = parser.parse_args()

    if args.model_path:
        current_base_path = os.path.abspath(args.model_path)
        print(f"Using base path from command line: {current_base_path}")
    else:
        current_base_path = os.path.abspath(DEFAULT_BASE_PATH) 
        print(f"Using determined base path: {current_base_path}")

    # Ensure Base Dirs Exist Early (default ComfyUI mode to False for this initial call)
    ensure_directories_exist(current_base_path, False) 

    worker_thread = threading.Thread(target=download_worker, daemon=True)
    worker_thread.start()

    gradio_app = create_ui(current_base_path)
    allowed_paths_list = get_available_drives()
    try:
        base_dir_norm = os.path.normpath(current_base_path)
        parent_dir_norm = os.path.normpath(os.path.dirname(base_dir_norm))
        def is_subpath_of_allowed(path_to_check, allowed_list):
            norm_check = os.path.normpath(path_to_check)
            for allowed in allowed_list:
                norm_allowed = os.path.normpath(allowed)
                try:
                    if os.path.commonpath([norm_allowed, norm_check]) == norm_allowed:
                        return True
                except ValueError: 
                    pass
                except Exception as e:
                    print(f"Warning: Error checking common path for {norm_allowed} and {norm_check}: {e}")
            return False
        if os.path.isdir(base_dir_norm) and not is_subpath_of_allowed(base_dir_norm, allowed_paths_list):
            allowed_paths_list.append(base_dir_norm)
        if os.path.isdir(parent_dir_norm) and parent_dir_norm != base_dir_norm and not is_subpath_of_allowed(parent_dir_norm, allowed_paths_list):
            allowed_paths_list.append(parent_dir_norm)
    except Exception as e:
        print(f"Warning: Error processing base/parent paths for Gradio allowed_paths: {e}")
        if os.path.isdir(current_base_path) and current_base_path not in allowed_paths_list:
             allowed_paths_list.append(current_base_path)
    print(f"Final allowed Gradio paths for launch: {allowed_paths_list}")

    try:
        gradio_app.launch(
            inbrowser=True,
            share=args.share,
            allowed_paths=allowed_paths_list
        )
    except KeyboardInterrupt:
        print("\nCtrl+C received. Shutting down...")
    except Exception as e:
         print(f"ERROR launching Gradio: {e}")
         print("Please ensure Gradio is installed correctly (`pip install gradio`) and that the specified port is available.")
    finally:
        stop_worker.set()
        print("Waiting for download worker to finish current task (up to 5s)...")
        worker_thread.join(timeout=5.0) 
        if worker_thread.is_alive():
            print("Worker thread did not finish cleanly after 5 seconds.")
        else:
            print("Download worker stopped.")
        if status_updates is not None:
             status_updates.put(None) 
             status_updates = None
    print("Gradio app closed.")