{ config, pkgs, lib, ... }:

let
    # --- Declarative Configuration ---
    # We define the config here, and Nix writes it to the store.
    portalConfig = {
        shared_data_mode = false;
        instances = [
            {
                name = "Chef's Games";
                url = "https://foundry.tongatime.us/chef";
            }
            # {
            #     name = "Crunch's Games";
            #     url = "https://foundry.tongatime.us/crunch";
            # }
            # {
            #     name = "ColossusDirge's Games";
            #     url = "https://foundry.tongatime.us/colossusdirge";
            # }
            # {
            #     name = "Laz's Games";
            #     url = "https://foundry.tongatime.us/laz";
            # }
        ];
    };

    # Convert the set to YAML and write it to the Nix Store
    configYaml = pkgs.writeText "foundry-portal-config.yaml" (lib.generators.toYAML {} portalConfig);

    in {
    # --- Build Service ---
    # Since Foundry Portal does not have an official docker image, we build it from source using Podman.
    # This service ensures the image exists before the container starts.
    systemd.services.build-foundry-portal = {
        description = "Build Foundry Portal Docker Image";
        path = [ pkgs.git pkgs.podman ]; # Tools needed for the script
        script = ''
        set -e
        WORK_DIR="/var/lib/foundry-portal/source"
        
        # Ensure directory exists
        mkdir -p "$WORK_DIR"
        cd "$WORK_DIR"
        if [ -d ".git" ]; then
            output=$(git pull)
            # Only build if git pull reported changes or if the image doesn't exist
            if [[ "$output" != *"Already up to date."* ]] || ! podman image exists foundry-portal:latest; then
                podman build -t foundry-portal:latest .
            fi
        else
            git clone https://github.com/TaylorTurnerIT/foundry-portal.git .
            podman build -t foundry-portal:latest .
        fi

        # Build the image using Podman
        # We tag it as 'foundry-portal:latest' so the container service can find it.
        echo "Building Podman image..."
        podman build -t foundry-portal:latest .
        '';
        serviceConfig = {
        Type = "oneshot";
        TimeoutStartSec = "300"; # Allow 5 minutes for the build
        };
    };
    virtualisation.oci-containers.containers.foundry-portal = {
        image = "foundry-portal:latest";
        autoStart = true;
        extraOptions = [ "--network=host" ]; # Host networking for port 30000 access
        
        volumes = [
            "${configYaml}:/app/config_declarative.yaml:ro"
            "${config.sops.secrets.foundry_admin_hash.path}:/run/secrets/foundry_admin_hash:ro"
            # Mount the host's persistent directory to /data inside the container
            "/var/lib/foundry-portal:/data:rw" 
        ];

        # Startup Script:
        # 1. Checks for persistent files in /data.
        # 2. Initializes them if missing.
        # 3. Symlinks them to /app so the application can read/write them.
        cmd = [ 
            "/bin/sh" 
            "-c" 
            ''
                # --- Handle config.yaml ---
                if [ ! -f /data/config.yaml ]; then
                    echo "Initializing config.yaml from declarative defaults..."
                    cp /app/config_declarative.yaml /data/config.yaml
                fi
                # Remove default/ephemeral file and link to persistent one
                rm -f /app/config.yaml
                ln -sf /data/config.yaml /app/config.yaml

                # --- Handle worlds.json ---
                if [ ! -f /data/worlds.json ]; then
                    echo "Initializing worlds.json..."
                    # Initialize with empty schema to prevent startup errors
                    echo '{"worlds": {}, "schema_version": 1}' > /data/worlds.json
                fi
                # Link to persistent file
                rm -f /app/worlds.json
                ln -sf /data/worlds.json /app/worlds.json

                # --- Inject Secrets & Start ---
                # Inject admin hash into the persistent config without breaking other fields
                python -c "import yaml; conf=yaml.safe_load(open('/app/config.yaml')); conf['admin_password_hash']=open('/run/secrets/foundry_admin_hash').read().strip(); yaml.dump(conf, open('/app/config.yaml','w'))" && \
                
                python app.py
            ''
        ];
    };

    systemd.services.podman-foundry-portal = {
        requires = [ "build-foundry-portal.service" ];
        after = [ "build-foundry-portal.service" ];
    };

    # Ensure the Foundry Portal config directory exists with correct permissions
    systemd.tmpfiles.rules = [
        "d /var/lib/foundry-portal 0755 root root - -"
    ];
}