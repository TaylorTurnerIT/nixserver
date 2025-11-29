#!/usr/bin/env bash
# deploy-vps.sh
# Usage: ./deploy-vps.sh <target-ip>

TARGET_IP="$1"
FLAKE=".#vps-gateway"

if [ -z "$TARGET_IP" ]; then
    echo "Usage: $0 <target-ip>"
    exit 1
fi

echo "🚀 Deploying Secure NixOS Gateway to $TARGET_IP..."
echo "⚠️  WARNING: This will WIPE the remote server at $TARGET_IP."
read -p "Are you sure? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

# Run NixOS-Anywhere
# We use --build-on-remote to avoid compiling ARM artifacts on your local machine if it's x86
# We assume the remote user has sudo access (standard for cloud images)
nixos-anywhere \
  --flake "$FLAKE" \
  --build-on-remote \
  --extra-files ./vps-secrets \
  "root@$TARGET_IP"

# Note: If the initial SSH user is not root (e.g. ubuntu), usage might be:
# nixos-anywhere --flake ... ubuntu@$TARGET_IP -- --use-remote-sudo