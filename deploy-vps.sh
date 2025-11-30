#!/usr/bin/env bash

# --- Configuration ---
DEFAULT_HOST="vps-gateway"
FLAKE=".#vps-proxy"
DEPLOYER_IMAGE="homelab-deployer:latest"
LOG_DIR="logs"
SSH_KEY_NAME="homelab" 
# ---------------------

set -e

# Ensure log directory exists
mkdir -p "$LOG_DIR"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
LOG_FILE="$LOG_DIR/deploy_vps_$TIMESTAMP.log"

# Check for SSH Key locally
if [[ ! -f "$HOME/.ssh/$SSH_KEY_NAME" ]]; then
    echo "❌ CRITICAL ERROR: SSH Key '$HOME/.ssh/$SSH_KEY_NAME' not found!"
    echo "   The deployment container needs this specific key to connect."
    exit 1
fi

# Function to print usage
usage() {
    echo "Usage: $0 [option] [target]"
    echo "Options:"
    echo "  (no option)   Update the server (nixos-rebuild switch)"
    echo "  --install     Wipe and Re-install (nixos-anywhere)"
    echo "  --rebuild     Rebuild the deployment container"
    exit 1
}

# Check if we need to rebuild the image
if [[ "$1" == "--rebuild" ]]; then
    echo "🔨 Rebuilding deployment container..." | tee -a "$LOG_FILE"
    podman build -t "$DEPLOYER_IMAGE" -f Containerfile . 2>&1 | tee -a "$LOG_FILE"
    echo "✅ Container rebuilt!"
    exit 0
fi

# Determine Mode and Target
MODE="update"
TARGET="$DEFAULT_HOST"

if [[ "$1" == "--install" ]]; then
    MODE="install"
    if [[ -n "$2" ]]; then TARGET="$2"; fi
    
    echo "⚠️  WARNING: You are about to WIPE and RE-INSTALL $TARGET."
    echo "    (This assumes the remote user is 'ubuntu' with sudo access)"
    read -p "Are you sure? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
    fi
elif [[ -n "$1" ]]; then
    TARGET="$1"
fi

# Check if image exists
if ! podman image exists "$DEPLOYER_IMAGE"; then
    echo "❌ Deployer image not found. Building it now..." | tee -a "$LOG_FILE"
    podman build -t "$DEPLOYER_IMAGE" -f Containerfile . 2>&1 | tee -a "$LOG_FILE"
fi

echo "🚀 Starting Deployment to $TARGET..." | tee -a "$LOG_FILE"
echo "📄 Logging to $LOG_FILE"

# Run the container
podman run --rm -it \
  --security-opt label=disable \
  -v "$(pwd):/work:Z" \
  -v "$HOME/.ssh:/mnt/ssh_keys:ro" \
  -w /work \
  --net=host \
  -e MODE="$MODE" \
  -e TARGET="$TARGET" \
  -e FLAKE="$FLAKE" \
  -e SSH_KEY_NAME="$SSH_KEY_NAME" \
  "$DEPLOYER_IMAGE" \
  bash -c "
    # 1. Setup Writable SSH Environment
    mkdir -p /root/.ssh
    cp -r /mnt/ssh_keys/* /root/.ssh/ 2>/dev/null || true
    
    # FIX: SSH keys MUST have strict permissions or SSH ignores them
    chmod 700 /root/.ssh
    chmod 600 /root/.ssh/* 2>/dev/null || true
    
    # Configure SSH Defaults
    echo 'Host $TARGET' >> /root/.ssh/config
    echo '    StrictHostKeyChecking no' >> /root/.ssh/config
    echo '    UserKnownHostsFile /dev/null' >> /root/.ssh/config
    # Note: We still add this to config, but we ALSO pass it via CLI below
    echo '    IdentityFile /root/.ssh/$SSH_KEY_NAME' >> /root/.ssh/config

    # 2. Execute Command
    while true; do
        if [ \"\$MODE\" == \"install\" ]; then
            echo '🔥 Nuking and Installing NixOS on $TARGET...'
            
            # FIX: We explicitly pass the IdentityFile via --ssh-option
            # This ensures ssh-copy-id (which nixos-anywhere calls) uses the right key
            if nixos-anywhere \
                --flake \"\$FLAKE\" \
                --build-on remote \
                --ssh-option \"IdentityFile=/root/.ssh/\$SSH_KEY_NAME\" \
                ubuntu@\"\$TARGET\"; then
                
                echo '✅ Installation Complete!'
                break
            fi
        else
            echo '🔄 Updating Configuration on $TARGET...'
            
            # FIX: Also pass identity file to rebuild switch
            # -N = no config file (prevents conflicts), but we use config for HostName
            if nixos-rebuild switch \
                --flake \"\$FLAKE\" \
                --target-host \"root@\$TARGET\" \
                --use-remote-sudo \
                --option \"IdentityFile=/root/.ssh/\$SSH_KEY_NAME\"; then
                
                echo '✅ Update Complete!'
                break
            fi
        fi

        echo 
        echo '❌ Command failed.'
        read -p 'Retry? (y/N) ' -n 1 -r REPLY
        echo
        if [[ ! \$REPLY =~ ^[Yy]$ ]]; then
            echo 'Exiting.'
            exit 1
        fi
        echo '🔄 Retrying...'
    done
" 2>&1 | tee -a "$LOG_FILE"

echo "✅ Done!" | tee -a "$LOG_FILE"