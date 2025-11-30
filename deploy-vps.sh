#!/usr/bin/env bash

TARGET_HOST="129.153.13.212"
TARGET_USER="ubuntu"
# FIX: Explicitly point to the homeConfiguration output
FLAKE=".#homeConfigurations.ubuntu"
SSH_KEY_NAME="homelab"
DEPLOYER_IMAGE="homelab-deployer:latest"

set -e

# Check for SSH Key locally
if [[ ! -f "$HOME/.ssh/$SSH_KEY_NAME" ]]; then
    echo "❌ CRITICAL ERROR: SSH Key '$HOME/.ssh/$SSH_KEY_NAME' not found!"
    exit 1
fi

echo "🚀 Starting Deployment to $TARGET_USER@$TARGET_HOST..."

# Run the deployment INSIDE the container
podman run --rm -it \
  --security-opt label=disable \
  -v "$(pwd):/work:Z" \
  -v "$HOME/.ssh:/mnt/ssh_keys:ro" \
  -w /work \
  --net=host \
  -e TARGET_HOST="$TARGET_HOST" \
  -e TARGET_USER="$TARGET_USER" \
  -e FLAKE="$FLAKE" \
  -e SSH_KEY_NAME="$SSH_KEY_NAME" \
  "$DEPLOYER_IMAGE" \
  bash -c "
    # --- Setup SSH ---
    mkdir -p /root/.ssh
    cp -r /mnt/ssh_keys/* /root/.ssh/ 2>/dev/null || true
    chmod 700 /root/.ssh
    chmod 600 /root/.ssh/* 2>/dev/null || true
    
    echo 'Host $TARGET_HOST' >> /root/.ssh/config
    echo '    StrictHostKeyChecking no' >> /root/.ssh/config
    echo '    UserKnownHostsFile /dev/null' >> /root/.ssh/config
    echo '    IdentityFile /root/.ssh/$SSH_KEY_NAME' >> /root/.ssh/config

    SSH_CMD=\"ssh -i /root/.ssh/$SSH_KEY_NAME $TARGET_USER@$TARGET_HOST\"

    # --- 1. Bootstrap Nix & Lingering ---
    echo '🔍 Checking remote setup...'
    if ! \$SSH_CMD \"command -v nix-env &> /dev/null\"; then
        echo '📦 Installing Nix...'
        \$SSH_CMD \"curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install --no-confirm\"
    fi

    # CRITICAL: Enable lingering so services run after disconnect
    echo '⏳ Enabling Systemd Lingering...'
    \$SSH_CMD \"loginctl enable-linger $TARGET_USER\"

    # --- 2. Build Configuration ---
    echo '🔨 Building Home Manager configuration...'
    # FIX: Build the specific activation package
    DRV=\$(nix build --no-link --print-out-paths \"\${FLAKE}.activationPackage\" --extra-experimental-features 'nix-command flakes')
    
    if [ -z \"\$DRV\" ]; then
        echo '❌ Build failed.'
        exit 1
    fi
    echo \"✅ Build successful: \$DRV\"

    # --- 3. Copy & Activate ---
    echo 'Ns Copying closure to remote...'
    export NIX_SSHOPTS=\"-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i /root/.ssh/$SSH_KEY_NAME\"
    nix copy --to \"ssh://$TARGET_USER@$TARGET_HOST\" \"\$DRV\" --extra-experimental-features 'nix-command flakes'

    echo '🔄 Activating configuration...'
    \$SSH_CMD \"\$DRV/activate\"

    echo '✅ Deployment Complete!'
"