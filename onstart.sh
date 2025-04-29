chmod +x /tmp/prov.sh && bash /tmp/prov.sh
fi

# Set up X server environment
export DISPLAY=:1
export XAUTHORITY=/root/.Xauthority
export NO_AT_BRIDGE=1

# Start X server if not already running
if ! pgrep Xvfb > /dev/null; then
  Xvfb :1 -screen 0 1280x800x24 &
  sleep 2
fi

for s in /vast_ai_provisioning_script.sh /src/provisioning_script.sh; do
  if [ -f "$s" ]; then 
    echo "Running: $s" | tee -a /logs/onstart.log
    bash "$s" 2>&1 | tee -a /logs/${s##*/}.log
  fi
done

# Ensure VisoMaster directory exists (referenced in supervisord.conf)
mkdir -p /VisoMaster/models /VisoMaster/model_assets

# Start supervisord if not running
if [ ! -f "/tmp/supervisord.pid" ]; then
  supervisord -c /src/supervisord.conf
fi
