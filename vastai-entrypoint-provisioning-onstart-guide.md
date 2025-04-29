# Guide: Understanding Vast.ai Provisioning, Entrypoint, and On-Start Script Options (with Real Project Examples)

Vast.ai provides several mechanisms to configure and initialize your cloud container environments. It's important to know how each option works, what they're best suited for, and how you can leverage them using practical examples—such as those from your own project.

---

## 1. **Provisioning Script (PROVISIONING_SCRIPT Environment Variable)**

### **What is it?**

- A Vast.ai-specific feature.
- Lets you specify a URL (e.g., to a GitHub Gist or raw script) via the `PROVISIONING_SCRIPT` environment variable.
- Vast.ai will **download and execute this script** as soon as the container boots, before any other user-level initialization.

### **How do you use it?**

- In the Vast.ai UI, add an environment variable named `PROVISIONING_SCRIPT` and set its value to a direct URL to your shell script.
- The script can install packages, clone repositories, set up your environment, etc.
- No need to build a custom Docker image if all your setup can be done in the script.

### **Good For:**
- Quick, repeatable setup of standard templates.
- One-off or frequently changing environments.
- When you want to keep your Docker images lightweight and use scripts for customization.

### **Example from your project:**  
(Snippet from `provisioning_script.sh`)

```bash
#!/bin/bash
# This script clones the repo, activates venv, installs TensorRT, and downloads models.

# Clone repo
git clone "https://github.com/remphan1618/VisoMaster.git" "/root/VisoMaster"

# Activate venv
source /opt/venv/bin/activate

# Install dependencies
pip install -r "/root/VisoMaster/requirements_cu124.txt"

# Download models
python "/root/VisoMaster/download_models.py"
```

---

## 2. **Entrypoint (CMD/ENTRYPOINT in Dockerfile)**

### **What is it?**

- Standard Docker feature.
- Specifies the main process or command that runs when the container starts.

### **How do you use it?**

- In your `Dockerfile`, use:
  ```dockerfile
  CMD ["/bin/bash", "/root/startup.sh"]
  ```
  or
  ```dockerfile
  ENTRYPOINT ["/bin/bash", "/root/startup.sh"]
  ```
- This will run your `startup.sh` script automatically when the container is launched.

### **Good For:**
- Defining the main application or long-running process (e.g., a web server, Jupyter notebook, VNC server).
- Ensuring your container keeps running and doesn't exit immediately.
- Cases where you want full control over the container's lifecycle and process management.

### **Example from your project:**  
(Snippet from your `Dockerfile`)

```dockerfile
# Create startup script
RUN echo '#!/bin/bash
/bin/bash /root/provisioning_script.sh
vncserver :1 -depth 24 -geometry 1280x800 -localhost no
websockify 0.0.0.0:6080 localhost:5901 &
tail -f /dev/null
' > /root/startup.sh && chmod +x /root/startup.sh

# Set the startup command
CMD ["/bin/bash", "/root/startup.sh"]
```

---

## 3. **On-Start Script (Vast.ai On-Start Script Text Box)**

### **What is it?**

- A Vast.ai GUI textbox under "On-Start Script" (when launching an instance or editing a template).
- Lets you enter bash commands that run **every time your container starts or restarts** (after any provisioning script, before the main entrypoint).
- Acts like a dynamic, user-editable `CMD`/`ENTRYPOINT`, but is handled "outside" the Dockerfile.

### **How do you use it?**

- Enter bash commands (one per line or a script block) into the On-Start textbox in the Vast.ai UI.
- Common actions: permission fixes, starting background services, patching config files, exporting environment variables.

### **Good For:**
- Tweaking or patching an image at runtime without rebuilding the Dockerfile.
- Running initialization logic that should occur at every container start.
- Quick fixes, testing commands, or chaining to your main process.

### **Example from your project:**

Suppose you want to ensure your `start.sh` runs and patches a config file each time the instance boots:

```bash
# On-Start Script textbox content

chmod +x /usr/local/bin/start.sh
bash /usr/local/bin/start.sh

# Patch a config file at runtime
sed -i 's/-sslOnly//g' /dockerstartup/vnc_startup.sh

# Make a directory as a specific user
sudo -i -u kasm-user mkdir -p /home/kasm-user/Desktop

# Persist environment variables
env >> /etc/environment
```

---

## 4. **How They Work Together**

- **PROVISIONING_SCRIPT**: One-time, first-boot setup. Great for installing packages, downloading models, and initial environment prep.  
- **Entrypoint (CMD/ENTRYPOINT)**: The main process that keeps the container alive and functional.  
- **On-Start Script**: Runs every time an instance spins up or restarts, perfect for runtime tweaks, permission changes, or launching helper scripts.

**In your project, you:**
- Set up everything needed for your workspace and ML models in `provisioning_script.sh`.
- Use a `startup.sh` as your container's main entrypoint to start VNC, websockify, and keep the service running.
- Optionally add more initialization or fixes via the On-Start Script textbox for easy tweaks during testing and deployment.

---

## 5. **Quick Table: When to Use What**

| Feature             | Runs When?        | Where to Configure?   | Good For                                           |
|---------------------|-------------------|-----------------------|----------------------------------------------------|
| PROVISIONING_SCRIPT | First boot only   | Env var in Vast UI    | Initial setup, installs, downloads, repo cloning    |
| Entrypoint/CMD      | Every container start | Dockerfile          | Main application process (e.g. web server, VNC)    |
| On-Start Script     | Every start/restart | Vast UI Text Box    | Runtime tweaks, patching, extra setup, dev testing |

---

## 6. **Best Practices**

- **For reproducibility and speed:** Do heavy setup in PROVISIONING_SCRIPT or the Dockerfile (if stable).
- **For main services:** Use Entrypoint/CMD for your primary server or persistent process.
- **For rapid iteration:** Use On-Start for runtime tweaks, debugging, or when you want to avoid rebuilding images.
- **For version control:** Keep your provisioning and startup scripts in your repo for easy updates and collaboration.

---

## 7. **References**

- [Vast.ai Documentation: Instances](https://docs.vast.ai/instances)
- [Vast.ai Documentation Home](https://docs.vast.ai/)
- Your project files:  
  - [`Dockerfile`](https://github.com/remphan1618/Red/blob/main/Dockerfile)
  - [`provisioning_script.sh`](https://github.com/remphan1618/Red/blob/main/provisioning_script.sh)

---

If you need more real-world templates, or want to see how to combine all three for a specific use case, just ask!