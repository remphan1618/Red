# Vast.ai Environment Initialization: Provisioning Script, Entrypoint, On-Start Script, and Jupyter Notebook

## Overview

Vast.ai offers multiple ways to initialize, customize, and manage your AI/cloud environments. Knowing when and how to use **Provisioning Scripts**, **Entrypoint/CMD**, **On-Start Script**, and even **Jupyter Notebooks** will make your workflow flexible, reproducible, and efficient.

---

## 1. PROVISIONING_SCRIPT Environment Variable

**What?**  
A Vast.ai-specific feature allowing you to specify a shell script (hosted online) that runs automatically when your instance boots for the first time.

**How?**  
- In Vast.ai's UI, add an environment variable named `PROVISIONING_SCRIPT` with its value set to a direct raw script URL (e.g., from GitHub).
- The script is downloaded and executed at first launch.

**Best For:**  
- Installing packages, cloning repos, downloading datasets/models, initial configuration—all without a custom Docker image.

**Example:**
```bash
#!/bin/bash
git clone "https://github.com/remphan1618/VisoMaster.git" "/VisoMaster"
source /opt/venv/bin/activate
pip install -r "/VisoMaster/requirements_cu124.txt"
python "/VisoMaster/download_models.py"
```

---

## 2. Entrypoint (CMD/ENTRYPOINT in Dockerfile)

**What?**  
The main process or script that runs when your Docker container starts.  
Defined inside your `Dockerfile`.

**How?**  
- `CMD ["/bin/bash", "/root/startup.sh"]` or `ENTRYPOINT ["/bin/bash", "/root/startup.sh"]`
- The referenced script should set up core services (e.g., VNC server) and keep the container alive.

**Best For:**  
- Main application, persistent services (servers, daemons), or scripts that should always run with the container.

**Example:**
```dockerfile
CMD ["/bin/bash", "/root/startup.sh"]
```

---

## 3. On-Start Script (Vast.ai UI Text Box)

**What?**  
A text box in the Vast.ai UI where you enter shell commands to run every time the instance starts or restarts.

**How?**  
- Go to the Vast.ai UI → "On-Start Script" section.
- Enter bash commands, e.g.:
  ```bash
  chmod +x /usr/local/bin/start.sh
  bash /usr/local/bin/start.sh
  sed -i 's/-sslOnly//g' /dockerstartup/vnc_startup.sh
  env >> /etc/environment
  ```

**Best For:**  
- Tweaks, hotfixes, permission adjustments, patching files, quick testing—without rebuilding images.
- Commands that should re-run on every container start.

---

## 4. JupyterLab Notebook-Based Initialization

**What?**  
Use JupyterLab (launched via Vast.ai's "jupyter" mode) to interactively set up, document, and experiment with your environment from a notebook.

**How?**  
1. Launch your Vast.ai instance in "jupyter" mode.
2. Open JupyterLab via the provided URL.
3. Create and run cells in a notebook for setup, installation, downloads, and configuration.

**Best For:**  
- Interactive environment setup, exploratory work, debugging, and real-time documentation.
- When you want step-by-step control, instant feedback, or to share reproducible workflow setups.

**Example Notebook Cells:**
```python
# Install dependencies
!pip install torch==2.0.1+cu118 torchvision matplotlib pandas

# Clone a repo
!git clone https://github.com/remphan1618/VisoMaster.git /workspace/VisoMaster

# Download models
%cd /workspace/VisoMaster
!python download_models.py

# Set environment variables
%env MODEL_PATH=/workspace/VisoMaster/models
```

---

## 5. How They Work Together

- **PROVISIONING_SCRIPT:** One-time, first-boot setup. Good for heavy installs, downloads, and environment prep.
- **Entrypoint (CMD/ENTRYPOINT):** Main process that keeps your container running (server, VNC, etc.).
- **On-Start Script:** Runs every start/restart. Perfect for runtime tweaks, permissions, and hotfixes.
- **Jupyter Notebook:** Manual, interactive setup or iterative development and documentation.

---

## 6. Quick Reference Table

| Feature                | When It Runs           | Where to Configure     | Best Use                                 |
|------------------------|------------------------|-----------------------|------------------------------------------|
| PROVISIONING_SCRIPT    | First boot only        | Env var (Vast.ai UI)  | One-time setup, installs, downloads      |
| Entrypoint/CMD         | Every container start  | Dockerfile            | Main app/server to keep container alive  |
| On-Start Script        | Every start/restart    | Vast.ai UI text box   | Tweaks, hotfixes, runtime customizations |
| Jupyter Notebook       | Manual, interactive    | JupyterLab in browser | Experimentation, step-by-step setup      |

---

## 7. Best Practices

- Use **PROVISIONING_SCRIPT** for major setup tasks that don't need to run every time.
- Use **Entrypoint/CMD** for your main application or server process.
- Use **On-Start** for tweaks and tasks that must persist across container restarts.
- Use **Jupyter Notebooks** for exploratory setup, documentation, and collaborative work.
- Keep scripts and notebooks version-controlled in your repo for reproducibility.

---

## 8. References

- [Vast.ai Instances Documentation](https://docs.vast.ai/instances)
- [Vast.ai Documentation Home](https://docs.vast.ai/)
- Your project: [Dockerfile](https://github.com/remphan1618/Red/blob/main/Dockerfile), [provisioning_script.sh](https://github.com/remphan1618/Red/blob/main/provisioning_script.sh)

---

*For more real-world templates or to see how to combine all methods for a specific use case, just ask!*