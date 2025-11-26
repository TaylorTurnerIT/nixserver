#!/usr/bin/env bash

# --- Configuration ---
TARGET_HOST="homelab" # Aliased in ~/.ssh/config
FLAKE=".#homelab"
# ---------------------

set -e # Exit immediately if a command exits with a non-zero status.

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

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "This script requires sudo privileges."
    echo "Please enter your password:"
    
    # Re-run the script with sudo
    exec sudo "$0" "$@"
fi

# Script runs as root from here
echo "Running with sudo privileges..."

echo "🚀 Starting Deployment Container..."

# We run an ephemeral container with:
# -v $(pwd):/work:Z       -> Mounts current folder. :Z fixes SELinux on Bazzite/Fedora.
# -v $HOME/.ssh:...       -> Mounts your SSH keys so you can connect to the server.
# --net=host              -> Uses host networking to avoid DNS/IP issues.
podman run --rm -it \
  -v "$(pwd):/work:Z" \
  -v "$HOME/.ssh:/root/.ssh:ro" \
  -v "$HOME/.ssh/config:/root/.ssh/config:ro" \
  -w /work \
  --net=host \
  nixos/nix \
  bash -c "
    # 1. Configure Nix (Enable Flakes) inside the container
    mkdir -p ~/.config/nix
    echo 'experimental-features = nix-command flakes' >> ~/.config/nix/nix.conf

    # 2. Execute the requested command
    if [ \"$MODE\" == \"install\" ]; then
        echo '🔥 Nuking and Installing NixOS...'
        nix run github:nix-community/nixos-anywhere -- --flake $FLAKE $TARGET_HOST
    else
        echo '🔄 Updating Configuration...'
        # FIX: Run nixos-rebuild via 'nix run' since it isn't installed in the container by default
        nix run nixpkgs#nixos-rebuild -- switch --flake $FLAKE --target-host $TARGET_HOST --use-remote-sudo
    fi
"

echo "✅ Done!"