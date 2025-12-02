{ config, pkgs, ... }:

{
    virtualisation.oci-containers.containers.minecraft = {
        /*
            Minecraft Server Container
            This container runs a Minecraft server using the itzg/minecraft-server image.
        
            Configuration:
            - Image: 
                - Uses the latest itzg/minecraft-server image from Docker Hub.
            - Ports: 
                - Maps port 25565 on the host to port 25565 in the container.
                - Host: 25565 <--> Container: 25565
            - Volumes: 
                - Maps /var/lib/minecraft on the host to /data in the container for persistent storage.
                - Host:/var/lib/minecraft <--> Container:/data
            - Environment Variables: 
                - EULA: Accepts the Minecraft EULA.
                - MEMORY: Allocates 6GB of RAM to the server.
                - MAX_PLAYERS: Sets the maximum number of players to 8.
                - MOTD: Custom message of the day with colors and formatting.
                - ICON: URL to a custom server icon.
                - USE_MEOWICE_FLAGS: Enables custom performance flags for better performance.
                - DIFFICULTY, PVP, SPAWN_PROTECTION: Configures game settings.
                - OPS and WHITELIST: Sets up server operators and whitelist for player access.
                - RCON_CMDS: Commands to run at various server events for world pre-generation.

            Reference:
            https://setupmc.com/java-server/

            ### NOTE:
            This is running root, this will need to be changed to a non-root user for security.
        */
        image = "itzg/minecraft-server:latest";
        autoStart = true;
        
        # Map ports: Host:Container
        ports = [ "25565:25565" ];

        # Persistent Storage
        # We map a folder on the host (/var/lib/minecraft) to /data in the container
        volumes = [
        "/var/lib/minecraft:/data"
        ];

        # Environment Variables
        environment = {
        EULA = "TRUE";
        MEMORY = "6G";
        MAX_PLAYERS = "8";
        MOTD = ''§6✦ §l§6TONGA§eTIME§r §6✦ §r§7tongatime.us §b▸ §fIs it Tonga Time?§7§o[1.20+]'';
        ICON = "https://icons.iconarchive.com/icons/chrisl21/minecraft/48/Computer-icon.png";
        USE_MEOWICE_FLAGS = "true"; 
        DIFFICULTY = "2";
        PVP = "false";
        SPAWN_PROTECTION = "1";
        
        # OPS and WHITELIST
        OPS = "NVMGamer";
        ENABLE_WHITELIST = "true";
        WHITELIST = "NVMGamer";
        
        # RCON Commands
        RCON_CMDS_STARTUP = "pregen start 200";
        RCON_CMDS_FIRST_CONNECT = "pregen stop";
        RCON_CMDS_LAST_DISCONNECT = "pregen start 200";
        };
    };

    # Open internal port 25565 for Minecraft server 
    networking.firewall = {
    allowedTCPPorts = [ 25565 ];
    allowedUDPPorts = [ 25565 ];
    };

    # Ensure the Minecraft data directory exists with correct permissions
    # 07551 = drwxr-xr-x, 1000 = uid for 'minecraft' user, 1000 = gid for 'minecraft' group
    systemd.tmpfiles.rules = [
    "d /var/lib/minecraft 0755 1000 1000 - -"
    ];
}


