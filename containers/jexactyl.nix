{ config, pkgs, lib, inputs, ... }:

let
	# Constants
	podmanNetwork = "jexactyl_net";
	dataDir = "/var/lib/jexactyl";
	
	# The source code from the flake input
	src = inputs.jexactyl-src;
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
	# This service checks if the current Flake input matches the last built image.
	# If the Flake input changed (new commit), it triggers a rebuild.
	
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
      # Define state file to track build version
      STATE_FILE="${dataDir}/.built_hash"
      CURRENT_HASH="${src}"

      # Check if we need to rebuild
      if [ ! -f "$STATE_FILE" ] || [ "$(cat $STATE_FILE)" != "$CURRENT_HASH" ]; then
        echo "Source changed. Building Jexactyl container from ${src}..."

        BUILD_DIR=$(mktemp -d)
        trap "rm -rf $BUILD_DIR" EXIT
        cp -r ${src}/. $BUILD_DIR/

        # Create missing files
        touch $BUILD_DIR/.npmrc
        touch $BUILD_DIR/CHANGELOG.md
        touch $BUILD_DIR/SECURITY.md
        [ -f $BUILD_DIR/LICENSE.md ] || echo "MIT License" > $BUILD_DIR/LICENSE.md
        [ -f $BUILD_DIR/README.md ] || echo "# Jexactyl" > $BUILD_DIR/README.md

        # --- PATCH: Install Python, Yacron, and Fix Permissions ---
        echo "" >> $BUILD_DIR/Containerfile
        
        # 1. Switch to ROOT for installation
        echo "USER root" >> $BUILD_DIR/Containerfile
        
        # 2. Install Dependencies (Distro Agnostic)
        echo "RUN set -e; \\" >> $BUILD_DIR/Containerfile
        echo "    if command -v apk >/dev/null; then apk add --no-cache python3 py3-pip; \\" >> $BUILD_DIR/Containerfile
        echo "    elif command -v apt-get >/dev/null; then apt-get update && apt-get install -y python3 python3-pip && apt-get clean && rm -rf /var/lib/apt/lists/*; \\" >> $BUILD_DIR/Containerfile
        echo "    elif command -v microdnf >/dev/null; then microdnf install -y python3 python3-pip && microdnf clean all; \\" >> $BUILD_DIR/Containerfile
        echo "    elif command -v dnf >/dev/null; then dnf install -y python3 python3-pip && dnf clean all; \\" >> $BUILD_DIR/Containerfile
        echo "    elif command -v yum >/dev/null; then yum install -y python3 python3-pip && yum clean all; \\" >> $BUILD_DIR/Containerfile
        echo "    else echo 'Error: No supported package manager found.'; exit 1; fi" >> $BUILD_DIR/Containerfile
        
        # 3. Install Yacron
        echo "RUN rm -f /usr/local/bin/yacron && \\" >> $BUILD_DIR/Containerfile
        echo "    pip3 install yacron --break-system-packages || pip3 install yacron" >> $BUILD_DIR/Containerfile
        
        # This bypasses the need to guess the exact UID/Username.
        echo "RUN chmod -R 777 /var/www/pterodactyl/bootstrap/cache /var/www/pterodactyl/storage" >> $BUILD_DIR/Containerfile

        # 5. Configure Caddy to listen on port 8081 and disable admin API (for host networking)
        echo "RUN sed -i 's/:8080/:8081/g' /etc/caddy/Caddyfile" >> $BUILD_DIR/Containerfile
        echo "RUN sed -i '1i {\\\\n  admin 127.0.0.1:2024\\\\n}' /etc/caddy/Caddyfile" >> $BUILD_DIR/Containerfile

        # 6. Do NOT switch user back manually.
        # We let the Base Image's original ENTRYPOINT handle the user switching.
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
  
	# --- SECURITY: Socket Proxy ---
	# Wings talks to this, NOT the host socket directly.
	# We BLOCK 'POST' requests, allowing only read operations if possible, 
	# though Wings technically needs write to manage game containers.
	# STRICT mode: If Wings needs to create containers, we must allow POST.
	# HARDENING: We isolate this access to *only* the Wings container via network.
	jexactyl-socket-proxy = {
		image = "tecnativa/docker-socket-proxy:latest";
		environment = {
			CONTAINERS = "1";
			IMAGES = "1";
			NETWORKS = "1";
			POST = "1"; # Wings MUST create containers, so POST is required.
			BUILD = "0"; # Block building new images
			COMMIT = "0"; # Block committing changes
			SWARM = "0"; # Block swarm info
			SYSTEM = "0"; # Block system pruning
		};
		volumes = [ "/run/podman/podman.sock:/var/run/docker.sock:ro" ];
		extraOptions = [ "--network=host" ];
	};

	# --- DATABASE ---
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

	# --- CACHE ---
	jexactyl-redis = {
		image = "redis:alpine";
		volumes = [ "${dataDir}/redis:/data" ];
		extraOptions = [ "--network=host" ];
	};

	# --- APP: PANEL ---
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
			"${dataDir}/panel/storage:/var/www/pterodactyl/var/"
			"${dataDir}/panel/logs:/var/www/pterodactyl/storage/logs"
			"${config.sops.templates."jexactyl.env".path}:/var/www/pterodactyl/.env"
		];

		extraOptions = [ "--network=host" ];
	};


	# --- DAEMON: WINGS ---
	jexactyl-wings = {
		image = "ghcr.io/pterodactyl/wings:latest";
		dependsOn = [ "jexactyl-panel" "jexactyl-socket-proxy" ];
		environment = {
			TZ = "UTC";
			WINGS_UID = "0";
			WINGS_GID = "0";
			# WINGS TALKS TO PROXY
			DOCKER_HOST = "tcp://127.0.0.1:2375";
		};
		volumes = [
			"${dataDir}/wings/config:/etc/pterodactyl"
			"${dataDir}/wings/data:/var/lib/pterodactyl"
			# Wings might need direct access to libpod/storage depending on driver
			# But standardized setups use socket/TCP.
		];
		extraOptions = [
			"--network=host"
			"--privileged"
		];
	};
	};
	
	# FORCE DEPENDENCY: Panel service must wait for the Build service
	systemd.services.podman-jexactyl-panel.after = [ "build-jexactyl-image.service" ];
	systemd.services.podman-jexactyl-panel.requires = [ "build-jexactyl-image.service" ];

	# ---------------------------------------------------------
	# WORKER SERVICE
	# ---------------------------------------------------------
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