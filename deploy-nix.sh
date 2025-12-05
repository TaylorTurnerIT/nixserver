#!/usr/bin/env bash

# --- Configuration ---
TARGET_HOST="homelab" 
FLAKE=".#homelab"
DEPLOYER_IMAGE="homelab-deployer:latest"
CACHE_VOLUME="nix-cache"
# ---------------------

set -e

# Function to print usage
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  (no option)   Update the server (nixos-rebuild switch)"
    echo "  --dry-run     Build the configuration locally to check for errors, but do not deploy"
    echo "  --install     Wipe and Re-install (nixos-anywhere)"
    echo "  --rebuild     Rebuild the deployment container"
    exit 1
}

MODE="update"
DRY_RUN="false"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --install)
            MODE="install"
            shift
            ;;
        --dry-run)
            DRY_RUN="true"
            shift
            ;;
        --rebuild)
            echo "🔨 Rebuilding deployment container..."
            podman build -t "$DEPLOYER_IMAGE" -f Containerfile .
            echo "✅ Container rebuilt!"
            exit 0
            ;;
        *)
            usage
            ;;
    esac
done

# Safety check for install mode (only if not a dry run)
if [[ "$MODE" == "install" && "$DRY_RUN" == "false" ]]; then
    echo "⚠️  WARNING: You are about to WIPE and RE-INSTALL $TARGET_HOST."
    read -p "Are you sure? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
    fi
fi

# Check if image exists
if ! podman image exists "$DEPLOYER_IMAGE"; then
    echo "❌ Deployer image not found. Building it now..."
    podman build -t "$DEPLOYER_IMAGE" -f Containerfile .
fi

# Ensure the cache volume exists. If not, create it.
if ! podman volume inspect "$CACHE_VOLUME" >/dev/null 2>&1; then
    echo "📦 Creating persistent Nix cache volume ($CACHE_VOLUME)..."
    podman volume create "$CACHE_VOLUME"
fi

if [[ "$DRY_RUN" == "true" ]]; then
    echo "🧪 Starting DRY RUN (Build check only)..."
else
    echo "🚀 Starting Deployment (using $DEPLOYER_IMAGE)..."
fi

podman run --rm -it \
  --security-opt label=disable \
  -e MODE="$MODE" \
  -e DRY_RUN="$DRY_RUN" \
  -e TARGET_HOST="$TARGET_HOST" \
  -e FLAKE="$FLAKE" \
  -v "$CACHE_VOLUME:/nix" \
  -v "$(pwd):/work:Z" \
  -v "$HOME/.ssh:/mnt/ssh_keys:ro" \
  -w /work \
  --net=host \
  "$DEPLOYER_IMAGE" \
  bash -c "
    # 1. Setup Writable SSH Environment
    # Copy keys from read-only mount to writable container location
    mkdir -p /root/.ssh
    cp -r /mnt/ssh_keys/* /root/.ssh/ 2>/dev/null || true
    chmod 700 /root/.ssh
    chmod 600 /root/.ssh/* 2>/dev/null || true

    # 2. Execute Command (With Retry Loop)
    while true; do
        if [ \"\$DRY_RUN\" == \"true\" ]; then
            echo '🧪 DRY RUN: Building configuration...'
            # We use nixos-rebuild build to verify the flake compiles correctly.
            # We do NOT pass --target-host, keeping the build local to the container.
            if nixos-rebuild build --flake \"\$FLAKE\"; then
                echo '✅ Dry Run Successful: Configuration builds without errors.'
                break
            fi
        elif [ \"\$MODE\" == \"install\" ]; then
            echo '🔥 Nuking and Installing NixOS...'
            if nixos-anywhere --flake \"\$FLAKE\" \"\$TARGET_HOST\"; then
                echo '✅ Installation Complete!'
                break
            fi
        else
            echo '🔄 Updating Configuration...'
            if nixos-rebuild switch --flake \"\$FLAKE\" --target-host \"\$TARGET_HOST\" --use-remote-sudo; then
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