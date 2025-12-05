#!/usr/bin/env bash
set -e

# --- Configuration ---
DEPLOYER_IMAGE="homelab-deployer:latest"
SECRETS_FILE="secrets/secrets.yaml"
ZONES_FILE="network/dns_zones.enc.yaml"
# ---------------------

echo "🚀 Starting DNS Deployment..."

# Check for Deployer Image
if ! podman image exists "$DEPLOYER_IMAGE"; then
    echo "⚠️  Deployer image not found. Please run ./build-deployer.sh first."
    exit 1
fi

# Extract Cloudflare Token (On Host)
echo "🔓 Decrypting Cloudflare Token..."
# Check if sops is available on host, otherwise warn user
if command -v sops &> /dev/null; then
    export CF_TOKEN=$(sops -d --extract '["cloudflare_token"]' "$SECRETS_FILE")
else
    echo "❌ 'sops' not found on host. Cannot decrypt token."
    exit 1
fi

# Run Container with In-Memory Decryption
podman run --rm -it \
  --security-opt label=disable \
  -v "$(pwd):/work:Z" \
  -v "$HOME/.ssh:/root/.ssh:ro" \
  -v "$HOME/.config/sops:/root/.config/sops:ro" \
  -w /work \
  -e CLOUDFLARE_API_TOKEN="$CF_TOKEN" \
  "$DEPLOYER_IMAGE" \
  bash -c "
    set -e
    
    echo '🔓 Decrypting Zones YAML in memory...'
    # Decrypt YAML -> Convert to JSON -> Store in ENV
    # This pipeline ensures plaintext never touches the disk
    export DNS_ZONES_JSON=\$(sops -d \"$ZONES_FILE\" | yq -o=json)

    echo '🔍 Checking Configuration...'
    dnscontrol check --creds network/creds.json --config network/dnsconfig.js

    echo '----------------------------------------'
    echo '🔮 PREVIEWING CHANGES'
    echo '----------------------------------------'
    dnscontrol preview --creds network/creds.json --config network/dnsconfig.js

    echo '----------------------------------------'
    read -p '⚠️  Apply these changes to Cloudflare? (y/N) ' -n 1 -r
    echo
    if [[ \$REPLY =~ ^[Yy]$ ]]; then
        echo '🚀 Pushing changes...'
        dnscontrol push --creds network/creds.json --config network/dnsconfig.js
    else
        echo '🚫 Aborted.'
    fi
"