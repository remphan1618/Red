chmod +x /tmp/prov.sh && bash /tmp/prov.sh
fi

# Set up X server environment
export DISPLAY=:0
export XAUTHORITY=/root/.Xauthority
export NO_AT_BRIDGE=1

# Create logs directory and start logging
mkdir -p /logs
exec > >(tee -a /logs/onstart_$(date +"%Y%m%d_%H%M%S").log) 2>&1
echo "Starting onstart script at $(date)"

# Start X server if not already running
if ! pgrep Xvfb > /dev/null; then
  echo "Starting Xvfb server"
  Xvfb :0 -screen 0 1280x800x24 &
  sleep 2
  echo "Xvfb started with DISPLAY=:0"
fi

# Ensure VisoMaster directory exists with proper structure
echo "Creating VisoMaster directory structure"
mkdir -p /VisoMaster/{models,Images,Videos,Output,model_assets}
echo "Directory structure created:"
ls -la /VisoMaster

# Run environment setup script if present
if [ -f "/src/setup_environment.sh" ]; then
  echo "Running environment setup script"
  bash /src/setup_environment.sh 2>&1 | tee -a /logs/setup_environment.log
fi

for s in /vast_ai_provisioning_script.sh /src/provisioning_script.sh; do
  if [ -f "$s" ]; then 
    echo "Running: $s"
    bash "$s" 2>&1 | tee -a /logs/${s##*/}.log
  fi
done

# Set permissions to ensure accessibility
chmod -R 755 /VisoMaster
echo "Set permissions on /VisoMaster"

# Start supervisord if not running
if [ ! -f "/tmp/supervisord.pid" ]; then
  echo "Starting supervisord"
  supervisord -c /src/supervisord.conf
  echo "supervisord started"
fi

echo "onstart script completed at $(date)"
