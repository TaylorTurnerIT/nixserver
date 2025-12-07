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

        # Clone or Pull the latest source
        if [ -d ".git" ]; then
            echo "Updating existing repository..."
            git pull
        else
            echo "Cloning repository..."
            git clone https://github.com/TaylorTurnerIT/foundry-portal.git .
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
        
        # NETWORK FIX: Use host networking to bypass firewall blocks on port 30000
        extraOptions = [ "--network=host" ];

        volumes = [
            "${configYaml}:/app/config_declarative.yaml:ro"
            "${config.sops.secrets.foundry_admin_hash.path}:/run/secrets/foundry_admin_hash:ro"
        ];

        # Overwrite startup command to install config
        # Runtime Injection
        # 1. Copy config
        # 2. Python script: Load yaml -> Read secret -> Inject hash -> Save yaml
        # 3. Run app
        cmd = [ 
            "/bin/sh" 
            "-c" 
            ''
                cp /app/config_declarative.yaml /app/config.yaml && \
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