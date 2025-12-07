{ config, pkgs, ... }:

{
    virtualisation.oci-containers.containers.foundryvtt = {
        # Container image
        image = "felddy/foundryvtt:13";
        
        # Auto start container on boot
        autoStart = true;
        
        # Map ports: Host:Container
        ports = [ "30001:30001" ];

        # Persistent Storage
        volumes = [
            "/var/lib/foundry/chef:/app/data"
        ];

        # Environment Variables
        environment = {
            # Handle using an injected secrets.json
            # FOUNDRY_USERNAME = ""
            # FOUNDRY_PASSWORD = ""
            # FOUNDRY_ADMIN_KEY = ""

            # Disable telemetry data collection
            FOUNDRY_TELEMETRY = "false"

            # Disable IP discovery, this will likely timeout and delay startup
            FOUNDRY_IP_DISCOVERY = "false"
            FOUNDRY_HOSTNAME = "foundry.tongatime.us"
            FOUNDRY_ROUTE_PREFIX = "/chef"
            
            # Foundry optimizations 
            FOUNDRY_COMPRESS_WEBSOCKET = "true"
            FOUNDRY
            };
        };
}



