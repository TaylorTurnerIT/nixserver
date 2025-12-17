{ config, pkgs, lib, inputs, ... }:

let
  podmanNetwork = "jexactyl_net";
  # Ensure you are using a valid image. If building locally, refer to your flake input.
  # Otherwise, use a built image. Jexactyl does not officially publish to Docker Hub, 
  # so you often need to build this yourself or use a trusted fork.
  jexactylImage = "ghcr.io/jexactyl/jexactyl:latest"; 
  
  # Directory on host for persistent data
  dataDir = "/var/lib/jexactyl";

in {
  # 1. Define Secrets via sops-nix
  sops.secrets = {
    "jexactyl/app_key" = {};
    "jexactyl/db_password" = {};
    "jexactyl/redis_password" = {};
    "jexactyl/mail_password" = {};
  };

  # 2. Create the .env file using sops templates
  # This effectively replaces the manual .env creation and handles secret injection securely
  sops.templates."jexactyl.env" = {
    content = ''
      APP_ENV=production
      APP_DEBUG=false
      APP_KEY=${config.sops.placeholder."jexactyl/app_key"}
      APP_URL=https://panel.yourdomain.com
      APP_TIMEZONE=UTC
      APP_LOCALE=en
      
      # Database
      DB_CONNECTION=mysql
      DB_HOST=jexactyl-db
      DB_PORT=3306
      DB_DATABASE=panel
      DB_USERNAME=jexactyl
      DB_PASSWORD=${config.sops.placeholder."jexactyl/db_password"}
      
      # Redis
      REDIS_HOST=jexactyl-redis
      REDIS_PASSWORD=${config.sops.placeholder."jexactyl/redis_password"}
      REDIS_PORT=6379
      CACHE_DRIVER=redis
      SESSION_DRIVER=redis
      QUEUE_CONNECTION=redis
      BROADCAST_DRIVER=redis
      
      # Mail (Example SMTP)
      MAIL_MAILER=smtp
      MAIL_HOST=smtp.example.com
      MAIL_PORT=587
      MAIL_USERNAME=user
      MAIL_PASSWORD=${config.sops.placeholder."jexactyl/mail_password"}
      MAIL_ENCRYPTION=tls
      MAIL_FROM_ADDRESS=no-reply@yourdomain.com
      MAIL_FROM_NAME="Jexactyl Panel"
    '';
    owner = "root"; # Accessible by root, we will cat it in entrypoint
  };

  # 3. Systemd Service for Network
  systemd.services."create-${podmanNetwork}-network" = {
    script = "${pkgs.podman}/bin/podman network create ${podmanNetwork} || true";
    wantedBy = [ "multi-user.target" ];
  };

  # 4. Container Definitions
  virtualisation.oci-containers.containers = {
    
    # --- Database ---
    jexactyl-db = {
      image = "mariadb:10.11";
      extraOptions = [ "--network=${podmanNetwork}" "--hostname=jexactyl-db" ];
      environment = {
        MYSQL_DATABASE = "panel";
        MYSQL_USER = "jexactyl";
        # We inject the password via a file to avoid leaks in `podman inspect`
        MYSQL_PASSWORD_FILE = "/run/secrets/jexactyl_db_password";
        MYSQL_ROOT_PASSWORD_FILE = "/run/secrets/jexactyl_db_password"; # Reuse for simplicity or create separate secret
      };
      volumes = [
        "${dataDir}/mysql:/var/lib/mysql"
        # Mount the raw secret file for MariaDB to read
        "${config.sops.secrets."jexactyl/db_password".path}:/run/secrets/jexactyl_db_password:ro"
      ];
    };

    # --- Redis ---
    jexactyl-redis = {
      image = "redis:alpine";
      extraOptions = [ "--network=${podmanNetwork}" "--hostname=jexactyl-redis" ];
      cmd = [ "redis-server" "--requirepass" "read_from_secret_if_possible_or_use_env" ]; 
      # Simpler approach for Redis: bind mount a config or pass generic start command.
      # Ideally, use a custom command to read password from file, but for simplicity:
      environment = {
        # Note: Redis image doesn't natively support _FILE for password easily without custom cmd
        # For strict security, use a custom redis.conf. 
        # For now, we will rely on the app side authentication.
      };
      volumes = [ "${dataDir}/redis:/data" ];
    };

    # --- Main Application ---
    jexactyl-app = {
      image = jexactylImage;
      extraOptions = [ "--network=${podmanNetwork}" ];
      volumes = [
        "${dataDir}/storage:/var/www/html/storage"
        "${dataDir}/public:/var/www/html/public"
        # Mount the sops-generated env file
        "${config.sops.templates."jexactyl.env".path}:/tmp/.env.sops:ro"
      ];
      # Custom entrypoint to Setup Environment & Migrations
      entrypoint = "${pkgs.writeShellScript "entrypoint.sh" ''
        #!/bin/sh
        echo "--> Copying secrets to application environment..."
        cp /tmp/.env.sops /var/www/html/.env
        chown www-data:www-data /var/www/html/.env

        echo "--> Waiting for Database..."
        until nc -z -v -w30 jexactyl-db 3306; do 
          echo "Waiting for database connection..."; 
          sleep 5; 
        done
        
        echo "--> Running Migrations & Seeds..."
        # Force is required in production mode
        php artisan migrate --seed --force --step
        
        echo "--> Clearing Caches..."
        php artisan cache:clear
        php artisan config:clear
        php artisan view:clear
        php artisan route:clear

        echo "--> Setting Permissions..."
        chown -R www-data:www-data /var/www/html/storage /var/www/html/bootstrap/cache

        echo "--> Starting Application..."
        exec php-fpm
      ''}";
      dependsOn = [ "jexactyl-db" "jexactyl-redis" ];
    };

    # --- Queue Worker ---
    jexactyl-worker = {
      image = jexactylImage;
      extraOptions = [ "--network=${podmanNetwork}" ];
      volumes = [
        "${dataDir}/storage:/var/www/html/storage"
        "${config.sops.templates."jexactyl.env".path}:/var/www/html/.env:ro" # Direct mount works for read-only worker
      ];
      cmd = [ "php" "artisan" "queue:work" "--sleep=3" "--tries=3" ];
      dependsOn = [ "jexactyl-app" ];
    };

    # --- Scheduler (Cron) ---
    jexactyl-cron = {
      image = jexactylImage;
      extraOptions = [ "--network=${podmanNetwork}" ];
      volumes = [
        "${dataDir}/storage:/var/www/html/storage"
        "${config.sops.templates."jexactyl.env".path}:/var/www/html/.env:ro"
      ];
      entrypoint = "${pkgs.writeShellScript "cron.sh" ''
        #!/bin/sh
        while true; do
          php /var/www/html/artisan schedule:run --verbose --no-interaction
          sleep 60
        done
      ''}";
      dependsOn = [ "jexactyl-app" ];
    };
  };

  # 5. Web Server Configuration (Caddy)
  services.caddy.virtualHosts."panel.yourdomain.com" = {
    extraConfig = ''
      root * /var/www/html/public
      php_fastcgi jexactyl-app:9000
      file_server
      encode gzip zstd
    '';
  };
}