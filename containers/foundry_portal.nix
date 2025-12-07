{ config, pkgs, ... }:

let
  # --- Configuration ---
  # Define your portal configuration here using Nix syntax.
  # This will be converted to the required config.yaml automatically.
  portalConfig = {
    shared_data_mode = false;
    instances = [
      {
        name = "In Golden Flame";
        url = "https://foundry.tongatime.us/crunch/ingoldenflame"; # Example URL
      }
      {
        name = "Genesis";
        url = "https://foundry.tongatime.us/chef/genesis";        # Example URL
      }
    ];
  };

  # Generate the configuration file in the Nix Store.
  configYaml = pkgs.writeText "foundry-portal-config.yaml" (builtins.toJSON portalConfig);
in
{
    virtualisation.oci-containers.containers.foundry-portal = {
        /*
            Foundry Portal Container
            This container runs Foundry Portal, a web frontend for managing multiple Foundry Virtual Tabletop (VTT) instances.

            Configuration:
            - Image:
                - Uses daxiongmao87/foundry-portal:latest from Docker Hub
            - Ports:
                - Maps port 5000 on the host to port 5000 in the container.
                - Host: 5000 <--> Container: 5000
            - Volumes:
                - Maps /var/lib/foundry-portal/config.yaml to /app/config.yaml in the container
                - Host:/var/lib/foundry-portal/config.yaml <--> Container:/app/config.yaml
            - Auto Start:
                - Container starts automatically on boot

            Setup Instructions:
            1. Create the config directory: sudo mkdir -p /var/lib/foundry-portal
            2. Create your config.yaml at /var/lib/foundry-portal/config.yaml
            3. Example config.yaml:
                shared_data_mode: false
                instances:
                  - name: "In Golden Flame"
                    url: "https://foundry.tongatime.us/crunch/ingoldenflame"
                  - name: "Genesis"
                    url: "https://foundry.tongatime.us/chef/genesis"

            Reference:
            https://github.com/daxiongmao87/foundry-portal
        */

        # Container image
        image = "daxiongmao87/foundry-portal:latest";

        # Auto start container on boot
        autoStart = true;

        # Map ports: Host:Container
        ports = [ "5000:5000" ];

        # Persistent Storage - mount config file
        volumes = [
            "${configYaml}:/app/config.yaml:ro"
        ];
    };

    # Ensure the Foundry Portal config directory exists with correct permissions
    systemd.tmpfiles.rules = [
        "d /var/lib/foundry-portal 0755 root root - -"
    ];
}