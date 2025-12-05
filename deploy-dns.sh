#!/usr/bin/env bash
set -e

# --- Configuration ---
DEPLOYER_IMAGE="homelab-deployer:latest"
DEFAULT_ZONES_YAML="network/dns_zones.yaml"
ZONES_JSON="network/dns_zones.json"
BACKUP_DIR="backups"
# ---------------------

# Function to print usage
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  (no option)       Deploy from $DEFAULT_ZONES_YAML"
    echo "  --revert <file>   Deploy using a specific backup file as the source"
    exit 1
}

# Default source is the current working file
SOURCE_YAML="$DEFAULT_ZONES_YAML"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --revert)
            if [[ -n "$2" && -f "$2" ]]; then
                SOURCE_YAML="$2"
                echo "Start Revert: Using $SOURCE_YAML as source configuration."
                shift 2
            else
                echo "❌ Error: --revert requires a valid file path."
                usage
            fi
            ;;
        *)
            usage
            ;;
    esac
done

# Prepare Backup
# We create a backup regardless of whether it's a new deploy or a revert, 
# ensuring we always have a history of what was pushed.
mkdir -p "$BACKUP_DIR"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="$BACKUP_DIR/dns_zones_$TIMESTAMP.yaml"

echo "📦 Creating backup of configuration..."
cp "$SOURCE_YAML" "$BACKUP_FILE"
echo "   ↳ Saved to: $BACKUP_FILE"

# Check for Deployer Image
if ! podman image exists "$DEPLOYER_IMAGE"; then
    echo "⚠️  Deployer image not found. Please run ./build-deployer.sh first."
    exit 1
fi

echo "🚀 Starting DNS Deployment..."

# Run Container
# We mount everything needed. The script inside handles the lifecycle of the JSON file.
# We pass SOURCE_YAML as an environment variable or interpolated string.
podman run --rm -it \
  --security-opt label=disable \
  -v "$(pwd):/work:Z" \
  -v "$HOME/.config/sops:/root/.config/sops:ro" \
  -v "$HOME/.ssh:/root/.ssh:ro" \
  -w /work \
  "$DEPLOYER_IMAGE" \
  bash -c "
    set -e
    
    # --- 1. PREPARE ---
    # Ensure we clean up the JSON file when this script exits (success or failure)
    trap 'rm -f $ZONES_JSON' EXIT

    echo '📝 Converting YAML to JSON...'
    echo '   Source: $SOURCE_YAML'
    
    # Convert the selected source YAML (current or backup) to the artifact JSON
    yq -o=json '$SOURCE_YAML' > '$ZONES_JSON'

    # --- 2. CHECK ---
    echo '🔍 Checking Configuration...'
    dnscontrol check --config network/dnsconfig.js

    # --- 3. PREVIEW ---
    echo '----------------------------------------'
    echo '🔮 PREVIEWING CHANGES'
    echo '----------------------------------------'
    # Use sops to inject credentials on-the-fly
    dnscontrol preview --creds !./secrets/cat-creds.sh --config network/dnsconfig.js

    # --- 4. CONFIRM & PUSH ---
    echo '----------------------------------------'
    read -p '⚠️  Apply these changes to Cloudflare? (y/N) ' -n 1 -r
    echo
    if [[ \$REPLY =~ ^[Yy]$ ]]; then
        echo '🚀 Pushing changes...'
        dnscontrol push --creds !./secrets/cat-creds.sh --config network/dnsconfig.js
    else
        echo '🚫 Aborted.'
    fi
"