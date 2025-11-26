#!/usr/bin/env bash

# --- Configuration ---
TARGET_HOST="homelab" 
FLAKE=".#homelab"
# ---------------------

set -e

# Function to print usage
usage() {
    echo "Usage: $0 [option]"
    echo "Options:"
    echo "  (no option)   Update the server (nixos-rebuild switch)"
    echo "  --install     Wipe and Re-install (nixos-anywhere)"
    exit 1
}

# Check arguments
MODE="update"
if [[ "$1" == "--install" ]]; then
    MODE="install"
    echo "⚠️  WARNING: You are about to WIPE and RE-INSTALL $TARGET_HOST."
    read -p "Are you sure? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
    fi
elif [[ -n "$1" ]]; then
    usage
fi

echo "🚀 Starting Deployment Container..."

# CHANGE: We mount keys to /mnt/ssh_keys (RO) instead of directly to /root/.ssh
podman run --rm -it \
  --security-opt label=disable \
  -v "$(pwd):/work:Z" \
  -v "$HOME/.ssh:/mnt/ssh_keys:ro" \
  -w /work \
  --net=host \
  nixos/nix \
  bash -c "
    # 1. Setup Writable SSH Environment
    # We copy keys from the read-only mount to the writable container home
    mkdir -p /root/.ssh
    cp -r /mnt/ssh_keys/* /root/.ssh/ 2>/dev/null || true
    chmod 700 /root/.ssh
    chmod 600 /root/.ssh/*
    
    # 2. Configure Nix
    mkdir -p ~/.config/nix
    echo 'experimental-features = nix-command flakes' >> ~/.config/nix/nix.conf

    # 3. Configure SSH to ignore known_hosts collisions
    export NIX_SSHOPTS='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'

    # 4. Execute Command (With Retry Loop)
    while true; do
        if [ \"$MODE\" == \"install\" ]; then
            echo '🔥 Nuking and Installing NixOS...'
            # Note: We explicitly point to the copied config file
            if nix run github:nix-community/nixos-anywhere -- --flake $FLAKE $TARGET_HOST; then
                echo '✅ Installation Complete!'
                break
            fi
        else
            echo '🔄 Updating Configuration...'
            if nix run nixpkgs#nixos-rebuild -- switch --flake $FLAKE --target-host $TARGET_HOST --use-remote-sudo; then
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
"

echo "✅ Done!"