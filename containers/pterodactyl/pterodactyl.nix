{ config, pkgs, lib, ... }:

let
  podmanNetwork = "pterodactyl_net";
  dataDir = "/var/lib/pterodactyl";
  
  # Define images here for easy updates
  images = {
    panel = "ghcr.io/pterodactyl/panel:latest";
    wings = "ghcr.io/pterodactyl/wings:latest";
    mariadb = "mariadb:10.11";
    redis = "redis:alpine";
  };
in {
  # --- Secrets Management ---
  # We only define the distinct secret values here, not the whole files.
  sops.secrets = {
    "pterodactyl/app_key" = { owner = "root"; };
    "pterodactyl/db_password" = { owner = "root"; };
    "pterodactyl/admin_password" = { owner = "root"; }; # New: for auto-creating the user
    # Secrets for Wings (You get these from the Panel after creating a node)
    "pterodactyl/wings_uuid" = { owner = "root"; };
    "pterodactyl/wings_token" = { owner = "root"; };
  };

  # --- Configuration Templates ---

  # Panel Environment (.env)
  sops.templates."pterodactyl-panel.env" = {
    content = ''
      APP_ENV=production
      APP_DEBUG=false
      APP_KEY=${config.sops.placeholder."pterodactyl/app_key"}
      APP_URL=https://panel.tongatime.us
      APP_TIMEZONE=UTC
      APP_SERVICE_AUTHOR=admin@tongatime.us
      TRUSTED_PROXIES=*
      
      DB_HOST=pterodactyl-db
      DB_PORT=3306
      DB_DATABASE=panel
      DB_USERNAME=pterodactyl
      DB_PASSWORD=${config.sops.placeholder."pterodactyl/db_password"}
      
      REDIS_HOST=pterodactyl-redis
      REDIS_PASSWORD=
      REDIS_PORT=6379
      
      CACHE_DRIVER=redis
      SESSION_DRIVER=redis
      QUEUE_CONNECTION=redis
    '';
    owner = "root";
  };

  # Wings Configuration (config.yml)
  # This replaces the binary secret. We construct the YAML structure here.
  sops.templates."pterodactyl-wings.yml" = {
    content = builtins.toJSON {
      debug = false;
      # We inject the UUID and Token from secrets
      uuid = "${config.sops.placeholder."pterodactyl/wings_uuid"}";
      token_id = "SET_IN_PANEL_IF_NEEDED"; # Usually handled by the full token below
      token = "${config.sops.placeholder."pterodactyl/wings_token"}";
      
      api = {
        host = "0.0.0.0";
        port = 8080;
        ssl = { enabled = false; }; # Caddy handles SSL
        upload_limit = 100;
      };
      
      system = {
        data = "/var/lib/pterodactyl/volumes";
        sftp = { bind_port = 2022; };
      };
      
      allowed_mounts = [];
      remote = "https://panel.tongatime.us";
    };
    owner = "root";
  };

  # --- Networking ---
  systemd.services."create-${podmanNetwork}-network" = {
    script = "${pkgs.podman}/bin/podman network create ${podmanNetwork} || true";
    wantedBy = [ "multi-user.target" ];
  };

  # --- Container Definitions ---
  virtualisation.oci-containers.containers = {

    # --- Database ---
    pterodactyl-db = {
      image = images.mariadb;
      extraOptions = [ "--network=${podmanNetwork}" "--hostname=pterodactyl-db" ];
      environment = {
        MYSQL_DATABASE = "panel";
        MYSQL_USER = "pterodactyl";
        MYSQL_PASSWORD_FILE = "/run/secrets/pterodactyl_db_password";
        MYSQL_RANDOM_ROOT_PASSWORD = "true";
      };
      volumes = [
        "${dataDir}/mysql:/var/lib/mysql"
        "${config.sops.secrets."pterodactyl/db_password".path}:/run/secrets/pterodactyl_db_password:ro"
      ];
    };

    # --- Redis ---
    pterodactyl-redis = {
      image = images.redis;
      extraOptions = [ "--network=${podmanNetwork}" "--hostname=pterodactyl-redis" ];
      volumes = [ "${dataDir}/redis:/data" ];
    };

    # --- Panel ---
    pterodactyl-panel = {
      image = images.panel;
      extraOptions = [ "--network=${podmanNetwork}" ];
      ports = [ "8081:80" ];
      volumes = [
        "${dataDir}/var:/app/var"
        "${dataDir}/nginx:/etc/nginx/http.d"
        "${dataDir}/logs:/app/storage/logs"
        "${dataDir}/certs:/etc/letsencrypt"
        "${config.sops.templates."pterodactyl-panel.env".path}:/tmp/.env.sops:ro"
        "${config.sops.secrets."pterodactyl/admin_password".path}:/run/secrets/admin_password:ro"
      ];
      
      # --- DECLARATIVE SETUP SCRIPT ---
      # This entrypoint checks for .installed flag to run initial setup only once.
      entrypoint = "${pkgs.writeShellScript "panel-entrypoint.sh" ''
        #!/bin/sh
        set -e
        
        # 1. Inject Secrets
        cp /tmp/.env.sops /app/.env
        
        # 2. Wait for DB
        echo "--> Waiting for Database..."
        until nc -z -v -w30 pterodactyl-db 3306; do 
          sleep 5 
        done

        # 3. Check for First Run
        if [ ! -f /app/var/.installed ]; then
            echo "--> FIRST RUN DETECTED: Initializing..."
            
            echo "--> Running Migrations..."
            php artisan migrate --seed --force

            echo "--> Creating Admin User..."
            # We read the password from the secret file
            ADMIN_PASS=$(cat /run/secrets/admin_password)
            
            php artisan p:user:make \
              --email="admin@tongatime.us" \
              --username="admin" \
              --name_first="Admin" \
              --name_last="User" \
              --password="$ADMIN_PASS" \
              --admin=1

            echo "--> Marking installation as complete."
            touch /app/var/.installed
        else
            echo "--> Installation found. Skipping setup."
            # Still run migrations on restart to handle updates
            php artisan migrate --force
        fi

        echo "--> Starting Panel..."
        /usr/sbin/php-fpm8.3 --daemonize
        nginx -g "daemon off;"
      ''}";
      
      dependsOn = [ "pterodactyl-db" "pterodactyl-redis" ];
    };

    # --- Worker ---
    pterodactyl-worker = {
      image = images.panel;
      extraOptions = [ "--network=${podmanNetwork}" ];
      volumes = [
        "${dataDir}/var:/app/var"
        "${dataDir}/logs:/app/storage/logs"
        "${config.sops.templates."pterodactyl-panel.env".path}:/tmp/.env.sops:ro"
      ];
      entrypoint = "${pkgs.writeShellScript "worker.sh" ''
        #!/bin/sh
        cp /tmp/.env.sops /app/.env
        php artisan queue:work --sleep=3 --tries=3
      ''}";
      dependsOn = [ "pterodactyl-panel" ];
    };

    # --- Wings ---
    pterodactyl-wings = {
      image = images.wings;
      autoStart = true;
      ports = [ "8082:8080" "2022:2022" ];
      volumes = [
        "/var/run/podman/podman.sock:/var/run/docker.sock"
        "/var/lib/pterodactyl-wings/data:/var/lib/pterodactyl"
        "/var/lib/pterodactyl-wings/logs:/var/log/pterodactyl"
        "/tmp/pterodactyl-wings:/tmp/pterodactyl"
        # Mount the generated config template
        "${config.sops.templates."pterodactyl-wings.yml".path}:/etc/pterodactyl/config.yml:ro"
      ];
      environment = {
        TZ = "UTC";
        WINGS_UID = "0";
        WINGS_GID = "0";
        WINGS_USERNAME = "root";
      };
      extraOptions = [ "--privileged" ];
    };
  };
  
  # --- 5. Permissions ---
  systemd.tmpfiles.rules = [
    "d ${dataDir}/mysql 0700 1000 1000 - -"
    "d ${dataDir}/var 0755 33 33 - -"
    "d ${dataDir}/logs 0755 33 33 - -"
    "d /var/lib/pterodactyl-wings/data 0700 root root - -"
  ];
}