{ config, pkgs, lib, ... }:

let
  user = "jexactyl";
  group = "users";
  uid = 1001; 
  dataDir = "/var/lib/jexactyl";
in {
	# --- Secrets ---
	sops.secrets.jexactyl_admin_password = { owner = "root"; }; # Only read by the init script
	sops.secrets.jexactyl_db_password = { owner = user; };
	sops.secrets.jexactyl_redis_password = { owner = user; };
	sops.secrets.jexactyl_app_key = { owner = user; };
	sops.secrets.jexactyl_app_url = { owner = user; };
	# --- Create the Restricted User ---
	users.users.${user} = {
		isNormalUser = true;
		description = "Jexactyl Game Server User";
		extraGroups = [ "podman" ];
		linger = true; # Keeps the rootless socket alive
		home = dataDir;
		createHome = true;
		uid = uid; # Explicit UID required for string interpolation
	};

	# --- Data Directories ---
	systemd.tmpfiles.rules = [
		"d ${dataDir}/wings         0755 ${user} ${group} - -"
		"d ${dataDir}/wings/config  0755 ${user} ${group} - -"
		"d ${dataDir}/wings/data    0755 ${user} ${group} - -"
		"d ${dataDir}/wings/backups 0755 ${user} ${group} - -"
		
		"d ${dataDir}/panel         0755 ${user} ${group} - -"
		"d ${dataDir}/panel/var     0755 ${user} ${group} - -"
		"d ${dataDir}/panel/logs    0755 ${user} ${group} - -"
		"d ${dataDir}/panel/nginx   0755 ${user} ${group} - -"
		
		"d ${dataDir}/database      0755 ${user} ${group} - -"
		"d ${dataDir}/redis         0755 ${user} ${group} - -"
  	];

	# --- Panel Environment Secrets ---
	sops.templates."jexactyl.env".content = ''
		APP_URL=${config.sops.placeholder.jexactyl_app_url}
		APP_KEY=${config.sops.placeholder.jexactyl_app_key}
		APP_SERVICE_AUTHOR="admin@tongatime.us"
		APP_TIMEZONE="America/Chicago"
		DB_HOST=jexactyl-db
		DB_PORT=3306
		DB_DATABASE=panel
		DB_USERNAME=jexactyl
		DB_PASSWORD=${config.sops.placeholder.jexactyl_db_password}
		REDIS_HOST=jexactyl-redis
		REDIS_PORT=6379
		REDIS_PASSWORD=${config.sops.placeholder.jexactyl_redis_password}
		RECAPTCHA_ENABLED=false
	'';

	# --- The Web Stack (Panel + DB + Redis) ---
	# These are low-risk web apps, so running them via standard OCI is fine.
	# We use a dedicated network for them.

	virtualisation.oci-containers.containers = {
		jexactyl-db = {
		image = "mariadb:10.11";
		autoStart = true;
		environment = {
			MYSQL_DATABASE = "panel";
			MYSQL_USER = "jexactyl";
			MYSQL_PASSWORD = "SOPS_PLACEHOLDER"; # Will be handled by panel init
			MYSQL_ROOT_PASSWORD = "${config.sops.placeholder.jexactyl_db_password}";
		};
		environmentFiles = [ config.sops.templates."jexactyl.env".path ];
		volumes = [ "${dataDir}/database:/var/lib/mysql" ];
		extraOptions = [ 
			"--network=jexactyl-net"
			
			# --- HEALTHCHECK CONFIGURATION ---
			# Define the check command (built-in to MariaDB images)
			"--health-cmd=healthcheck.sh --connect --innodb_initialized"
			
			# Start checking after 10 seconds (give it time to boot)
			"--health-start-period=10s"
			
			# Check every 10 seconds
			"--health-interval=10s"
			
			# Mark unhealthy after 3 failures
			"--health-retries=3"
		];
		};

		jexactyl-redis = {
		image = "redis:alpine";
		autoStart = true;
		cmd = [ "redis-server" "--requirepass" "${config.sops.placeholder.jexactyl_redis_password}" ];
		volumes = [ "${dataDir}/redis:/data" ];
		extraOptions = [ "--network=jexactyl-net" ];
		};

		jexactyl-panel = {
		image = "ghcr.io/jexactyl/jexactyl:latest";
		autoStart = true;
		ports = [ "8081:80" ];
		environmentFiles = [ config.sops.templates."jexactyl.env".path ];
		volumes = [
			"${dataDir}/panel/var:/app/var"
			"${dataDir}/panel/logs:/app/storage/logs"
			"${dataDir}/panel/nginx:/etc/nginx/http.d"
		];
		extraOptions = [ "--network=jexactyl-net" ];
		};
	};

	# --- The Critical Component: Wings ---
	# We run this as a Systemd User Service for the 'jexactyl' user.
	# This traps all game servers inside the 'jexactyl' user namespace.

	systemd.services.jexactyl-wings = {
		description = "Jexactyl Wings (Rootless)";
		wantedBy = [ "multi-user.target" ];
		after = [ "network.target" "jexactyl-panel.service" ];
		serviceConfig = {
		User = user;
		Group = "users";
		WorkingDirectory = "${dataDir}/wings";
		Restart = "always";
		# The magic command: We run podman inside the user session.
		# We bind the USER'S rootless socket to where Wings expects the docker socket.
		ExecStart = let
			podman = "${pkgs.podman}/bin/podman";
		in ''
			${podman} run --rm --name jexactyl-wings \
			--privileged \
			--network host \
			-v /run/user/${toString config.users.users.${user}.uid}/podman/podman.sock:/var/run/docker.sock
			-v ${dataDir}/wings/config:/etc/pterodactyl \
			-v ${dataDir}/wings/data:/var/lib/pterodactyl/volumes \
			-v ${dataDir}/wings/backups:/var/lib/pterodactyl/backups \
			ghcr.io/pterodactyl/wings:latest
		'';
		};
	};

	# --- Networking Setup ---
  	systemd.services.init-jexactyl-network = {
	script = "${pkgs.podman}/bin/podman network exists jexactyl-net || ${pkgs.podman}/bin/podman network create jexactyl-net";
	wantedBy = [ "multi-user.target" ];
  	};

	# --- Initialization Service ---
	systemd.services.jexactyl-init = {
	  description = "Initialize Jexactyl Database and Admin User";
	  after = [ "jexactyl-panel.service" "jexactyl-db.service" ]; 
	  requires = [ "jexactyl-panel.service" "jexactyl-db.service" ];
	  wantedBy = [ "multi-user.target" ];
	  
	  serviceConfig = {
		Type = "oneshot";
		ConditionPathExists = "!/var/lib/jexactyl/.setup_complete";
	  };

	  script = ''
		set -e
		
		# This command will hang until the status becomes 'healthy'.
		echo "Waiting for Database to become healthy..."
		${pkgs.podman}/bin/podman wait --condition=healthy jexactyl-db

		echo "Running Migrations..."
		${pkgs.podman}/bin/podman exec jexactyl-panel php artisan migrate --seed --force

		echo "Creating Admin User..."
		ADMIN_PASS=$(cat ${config.sops.secrets.jexactyl_admin_password.path})
		
		${pkgs.podman}/bin/podman exec jexactyl-panel php artisan p:user:make \
		  --email="admin@tongatime.us" \
		  --username="admin" \
		  --name-first="Admin" \
		  --name-last="User" \
		  --password="$ADMIN_PASS" \
		  --admin=1

		# 4. Mark as Complete
		touch /var/lib/jexactyl/.setup_complete
		echo "Jexactyl Initialization Complete."
	  '';
	};
}