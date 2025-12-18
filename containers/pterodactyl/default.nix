{ config, pkgs, lib, ... }:

let
  podmanNetwork = "pterodactyl_net";
  dataDir = "/var/lib/pterodactyl";
  
  images = {
    panel = "ghcr.io/pterodactyl/panel:latest";
    wings = "ghcr.io/pterodactyl/wings:latest";
    mariadb = "mariadb:10.11";
    redis = "redis:alpine";
  };

  # --- SCRIPTS ---
  # We define the scripts here and mount them later. 
  # We use writeText to avoid Nix-specific shebangs that break inside Alpine containers.

  panelEntrypoint = pkgs.writeText "panel-entrypoint.sh" ''
    #!/bin/sh
    set -e
    
    echo "--> Injecting secrets..."
    cp /tmp/.env.sops /app/.env
    
    echo "--> Waiting for Database..."
    # Alpine's nc syntax is slightly different, checking if port is open
    until nc -z pterodactyl-db 3306; do 
      echo "Waiting for database..."
      sleep 2
    done

    # Check for First Run
    if [ ! -f /app/var/.installed ]; then
        echo "--> FIRST RUN: Initializing..."
        
        echo "--> Running Migrations..."
        php artisan migrate --seed --force

        echo "--> Creating Admin User..."
        # Read password from secret
        ADMIN_PASS=$(cat /run/secrets/admin_password)
        
        php artisan p:user:make \
          --email="admin@tongatime.us" \
          --username="admin" \
          --name_first="Admin" \
          --name_last="User" \
          --password="$ADMIN_PASS" \
          --admin=1

        echo "--> Setup Complete."
        touch /app/var/.installed
    else
        echo "--> Existing installation found."
        echo "--> Running migrations on boot..."
        php artisan migrate --force
    fi

    echo "--> Starting Panel..."
    /usr/sbin/php-fpm8.3 --daemonize
    nginx -g "daemon off;"
  '';

  workerEntrypoint = pkgs.writeText "worker-entrypoint.sh" ''
    #!/bin/sh
    set -e
    cp /tmp/.env.sops /app/.env
    php artisan queue:work --sleep=3 --tries=3
  '';

in {
  # --- Secrets Management ---
  sops.secrets = {
    "pterodactyl/app_key" = { owner = "root"; };
    "pterodactyl/db_password" = { owner = "root"; };
    "pterodactyl/admin_password" = { owner = "root"; };
    "pterodactyl/wings_uuid" = { owner = "root"; };
    "pterodactyl/wings_token" = { owner = "root"; };
  };

  # --- Configuration Templates ---
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

  sops.templates."pterodactyl-wings.yml" = {
    content = builtins.toJSON {
      debug = false;
      uuid = "${config.sops.placeholder."pterodactyl/wings_uuid"}";
      token_id = "SET_IN_PANEL_IF_NEEDED";
      token = "${config.sops.placeholder."pterodactyl/wings_token"}";
      
      api = {
        host = "0.0.0.0";
        port = 8080;
        ssl = { enabled = false; };
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
        "${panelEntrypoint}:/entrypoint.sh:ro"
      ];
      
      entrypoint = "/bin/sh";
      cmd = [ "/entrypoint.sh" ];
      
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
        "${workerEntrypoint}:/entrypoint.sh:ro"
      ];
      entrypoint = "/bin/sh /entrypoint.sh";
    
      # Define a simple entrypoint that runs the script
      entrypoint = "/bin/sh";
      cmd = [ "/entrypoint.sh" ];

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
  
  # --- Permissions ---
  # We must create every directory that is volume-mapped on the host.
  systemd.tmpfiles.rules = [
    # --- Database (MariaDB) ---
    # UID 999 is commonly used by mysql/mariadb in containers
    "d ${dataDir}/mysql 0700 999 999 - -"

    # --- Redis ---
    # UID 999 is standard for Redis Alpine
    "d ${dataDir}/redis 0700 999 999 - -"

    # --- Panel (Runs as www-data: 33) ---
    "d ${dataDir}/var 0755 33 33 - -"
    "d ${dataDir}/logs 0755 33 33 - -"
    "d ${dataDir}/nginx 0755 33 33 - -"
    "d ${dataDir}/certs 0755 33 33 - -"

    # --- Wings (Runs as root) ---
    "d /var/lib/pterodactyl-wings/data 0700 0 0 - -"
    "d /var/lib/pterodactyl-wings/logs 0700 0 0 - -"
    "d /tmp/pterodactyl-wings 0700 0 0 - -" # Temp dir for Wings
  ];
}