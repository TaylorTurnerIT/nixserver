{ config, pkgs, ... }:

{
    virtualisation.oci-containers.containers.foundry_chef = {
        # Container image
        image = "felddy/foundryvtt:13";
        
        # Auto start container on boot
        autoStart = true;
        
        # Map ports: Host:Container
        ports = [ "30001:30000" ];

        # Persistent Storage
        volumes = [
            "/var/lib/foundry/chef:/data"
            "${config.sops.templates."foundry_secrets.json".path}:/run/secrets/config.json:ro"
        ];

        # Environment Variables
        environment = {
            # Disable telemetry data collection
            FOUNDRY_TELEMETRY = "false";

            # Disable IP discovery, this will likely timeout and delay startup
            FOUNDRY_IP_DISCOVERY = "false";
            FOUNDRY_HOSTNAME = "foundry.tongatime.us";
            FOUNDRY_ROUTE_PREFIX = "/chef";
            
            # Foundry optimizations 
            FOUNDRY_COMPRESS_WEBSOCKET = "true";
        };

        # Ensure the container's data directory exists with proper permissions
        systemd.tmpfiles.rules = [
            "d /var/lib/foundry/chef 0755 root root - -"
        ];
        };
}



