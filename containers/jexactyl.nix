{ config, pkgs, lib, inputs, ... }:

let
    # Constants
    podmanNetwork = "jexactyl_net";
    dataDir = "/var/lib/jexactyl";
    src = inputs.jexactyl-src;

    # --- 1. CLEAN CADDYFILE (Fixes Protocol Error) ---
    caddyFile = pkgs.writeText "Caddyfile" ''
    {
        admin 127.0.0.1:2024
    }

    :8081 {
        root * /var/www/pterodactyl/public
        file_server
        php_fastcgi 127.0.0.1:9000
        
        header X-Content-Type-Options nosniff
        header X-XSS-Protection "1; mode=block"
        header X-Robots-Tag none
        header Content-Security-Policy "frame-ancestors 'self'"
        header X-Frame-Options DENY
        header Referrer-Policy same-origin
        
        request_body {
            max_size 100m
        }
    }
    '';

    # --- 2. RUNTIME ENTRYPOINT (Fixes /tmp Permission Error) ---
    # This script runs every time the container starts.
    # It forces the /tmp directories to exist with wide-open permissions
    # so both the web server and console user can write to them.
    entrypointScript = pkgs.writeText "entrypoint.sh" ''
        #!/bin/sh
        echo "Initializing Jexactyl temp directories..."
        mkdir -p /tmp/pterodactyl/framework/views
        mkdir -p /tmp/pterodactyl/framework/cache
        mkdir -p /tmp/pterodactyl/framework/sessions
        
        # Set permission to 777 so root, nginx, and jexactyl users can all write
        chmod -R 777 /tmp/pterodactyl
        
        echo "Starting Supervisord..."
        exec supervisord -n -c /etc/supervisord.conf
    '';
in
{
    # ---------------------------------------------------------
    # PRE-FLIGHT: Filesystem & Network
    # ---------------------------------------------------------
    
    systemd.tmpfiles.rules = [
        "d ${dataDir}/mariadb 0700 999 999 -"
        "d ${dataDir}/redis 0700 999 999 -"
        "d ${dataDir}/panel/storage 0755 1000 1000 -"
        "d ${dataDir}/panel/logs 0755 1000 1000 -"
        "d ${dataDir}/wings/config 0700 0 0 -"
        "d ${dataDir}/wings/data 0700 0 0 -"
    ];

    # ---------------------------------------------------------
    # BUILDER SERVICE: Jexactyl Panel Image
    # ---------------------------------------------------------
    systemd.services.build-jexactyl-image = {
    description = "Build Jexactyl Panel Image from Flake Source";
    after = [ "podman.service" ];
    requires = [ "podman.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      TimeoutStartSec = 900;
    };
    script = ''
        STATE_FILE="${dataDir}/.built_hash"
        CURRENT_HASH="${src}"

      # Always rebuild if hash changed or explicitly forced
      if [ ! -f "$STATE_FILE" ] || [ "$(cat $STATE_FILE)" != "$CURRENT_HASH" ]; then
        echo "Source changed. Building Jexactyl container..."
        BUILD_DIR=$(mktemp -d)
        trap "rm -rf $BUILD_DIR" EXIT
        cp -r ${src}/. $BUILD_DIR/

        # Create basic files
        touch $BUILD_DIR/.npmrc
        touch $BUILD_DIR/CHANGELOG.md
        touch $BUILD_DIR/SECURITY.md
        [ -f $BUILD_DIR/LICENSE.md ] || echo "MIT License" > $BUILD_DIR/LICENSE.md
        [ -f $BUILD_DIR/README.md ] || echo "# Jexactyl" > $BUILD_DIR/README.md

        # --- PATCH: Install Python & Yacron ---
        echo "" >> $BUILD_DIR/Containerfile
        echo "USER root" >> $BUILD_DIR/Containerfile
        
        # Install Dependencies
        echo "RUN set -e; \\" >> $BUILD_DIR/Containerfile
        echo "    if command -v apk >/dev/null; then apk add --no-cache python3 py3-pip; \\" >> $BUILD_DIR/Containerfile
        echo "    elif command -v apt-get >/dev/null; then apt-get update && apt-get install -y python3 python3-pip && apt-get clean && rm -rf /var/lib/apt/lists/*; \\" >> $BUILD_DIR/Containerfile
        echo "    else echo 'Error: No supported package manager found.'; exit 1; fi" >> $BUILD_DIR/Containerfile
        
        # Install Yacron
        echo "RUN rm -f /usr/local/bin/yacron && \\" >> $BUILD_DIR/Containerfile
        echo "    pip3 install yacron --break-system-packages || pip3 install yacron" >> $BUILD_DIR/Containerfile
        
        # Fix Storage Permissions
        echo "RUN chmod -R 777 /var/www/pterodactyl/bootstrap/cache /var/www/pterodactyl/storage" >> $BUILD_DIR/Containerfile

        # --- INJECT CONFIGS ---
        
        # 1. Caddyfile
        echo "Injecting declarative Caddyfile..."
        cp ${caddyFile} $BUILD_DIR/Caddyfile
        echo "COPY Caddyfile /etc/caddy/Caddyfile" >> $BUILD_DIR/Containerfile

        # 2. Entrypoint Script
        echo "Injecting runtime entrypoint..."
        cp ${entrypointScript} $BUILD_DIR/entrypoint.sh
        echo "COPY entrypoint.sh /entrypoint.sh" >> $BUILD_DIR/Containerfile
        echo "RUN chmod +x /entrypoint.sh" >> $BUILD_DIR/Containerfile
        
        # Set new Entrypoint
        echo "ENTRYPOINT [\"/entrypoint.sh\"]" >> $BUILD_DIR/Containerfile
        
        # ---------------------------------------

        ${pkgs.podman}/bin/podman build \
          -t jexactyl-panel:local \
          -f $BUILD_DIR/Containerfile \
          $BUILD_DIR

        echo "$CURRENT_HASH" > "$STATE_FILE"
        echo "Build complete."
      else
        echo "Source unchanged. Using existing image."
      fi
    '';
    };

    # ---------------------------------------------------------
    # CONTAINER DEFINITIONS
    # ---------------------------------------------------------

    virtualisation.oci-containers.containers = {
  
    jexactyl-socket-proxy = {
        image = "tecnativa/docker-socket-proxy:latest";
        environment = {
            CONTAINERS = "1";
            IMAGES = "1";
            NETWORKS = "1";
            POST = "1";
            BUILD = "0";
            COMMIT = "0";
            SWARM = "0";
            SYSTEM = "0";
        };
        volumes = [ "/run/podman/podman.sock:/var/run/docker.sock:ro" ];
        extraOptions = [ "--network=host" ];
    };

    jexactyl-mariadb = {
        image = "mariadb:10.5";
        environment = {
            MYSQL_DATABASE = "panel";
            MYSQL_USER = "jexactyl";
            MYSQL_PASSWORD_FILE = "/run/secrets/jexactyl_db_password";
            MYSQL_ROOT_PASSWORD_FILE = "/run/secrets/jexactyl_db_root_password";
        };
        volumes = [
            "${dataDir}/mariadb:/var/lib/mysql"
            "${config.sops.secrets.jexactyl_db_password.path}:/run/secrets/jexactyl_db_password:ro"
            "${config.sops.secrets.jexactyl_db_root_password.path}:/run/secrets/jexactyl_db_root_password:ro"
        ];
        extraOptions = [ "--network=host" ];
    };

    jexactyl-redis = {
        image = "redis:alpine";
        volumes = [ "${dataDir}/redis:/data" ];
        extraOptions = [ "--network=host" ];
    };

    jexactyl-panel = {
        image = "jexactyl-panel:local";
        dependsOn = [ "jexactyl-mariadb" "jexactyl-redis" ];
        environment = {
            APP_URL = "https://panel.tongatime.us";
            APP_ENV = "production";
            APP_ENVIRONMENT_ONLY = "false";
            DB_HOST = "127.0.0.1";
            DB_PORT = "3306";
            DB_DATABASE = "panel";
            DB_USERNAME = "jexactyl";
            CACHE_DRIVER = "redis";
            SESSION_DRIVER = "redis";
            QUEUE_DRIVER = "redis";
            REDIS_HOST = "127.0.0.1";
        };

        volumes = [
            "${dataDir}/panel/storage:/var/www/pterodactyl/storage"
            "${dataDir}/panel/logs:/var/www/pterodactyl/storage/logs"
            "${config.sops.templates."jexactyl.env".path}:/var/www/pterodactyl/.env"
        ];

        extraOptions = [ "--network=host" ];
    };

    jexactyl-wings = {
        image = "ghcr.io/pterodactyl/wings:latest";
        dependsOn = [ "jexactyl-panel" "jexactyl-socket-proxy" ];
        environment = {
            TZ = "UTC";
            WINGS_UID = "0";
            WINGS_GID = "0";
            DOCKER_HOST = "tcp://127.0.0.1:2375";
        };
        volumes = [
            "${dataDir}/wings/config:/etc/pterodactyl"
            "${dataDir}/wings/data:/var/lib/pterodactyl"
        ];
        extraOptions = [
            "--network=host"
            "--privileged"
        ];
    };
    };
    
    systemd.services.podman-jexactyl-panel.after = [ "build-jexactyl-image.service" ];
    systemd.services.podman-jexactyl-panel.requires = [ "build-jexactyl-image.service" ];

    systemd.services.jexactyl-queue = {
        description = "Jexactyl Queue Worker";
        after = [ "podman-jexactyl-panel.service" ];
        requires = [ "podman-jexactyl-panel.service" ];
        serviceConfig = {
        ExecStart = "${pkgs.podman}/bin/podman exec -i jexactyl-panel php artisan queue:work --queue=high,standard,low --sleep=3 --tries=3";
        Restart = "always";
        };
    };
}