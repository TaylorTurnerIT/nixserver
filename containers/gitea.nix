{ config, pkgs, ... }:

{
  virtualisation.oci-containers.containers.gitea = {
    /*
      Gitea Container
      Self-hosted Git service with GitHub mirroring support.

      Configuration:
      - Image: Official gitea/gitea:latest from Docker Hub
      - Ports: 3001 (host) <-> 3000 (container)
      - Volumes: /var/lib/gitea <-> /data (SQLite DB, repos, config)
      - Database: SQLite3 at /data/gitea/gitea.db
      - Secrets: gitea_secret_key (encryption), github_mirror_token (mirroring)
    */
    image = "gitea/gitea:latest";
    autoStart = true;

    # Port mapping: Host:Container
    ports = [ 
      "3001:3000" # Gitea web interface
      "2222:22"     # SSH for Git operations
       ];
    

    # Persistent storage - all Gitea data
    volumes = [
      "/var/lib/gitea:/data"
      "${config.sops.secrets.gitea_secret_key.path}:/run/secrets/gitea_secret_key:ro"
      "${config.sops.secrets.github_mirror_token.path}:/run/secrets/github_mirror_token:ro"
    ];

    # Environment variables for configuration
    environment = {
      # User configuration
      USER_UID = "1000";
      USER_GID = "1000";

      # Database
      GITEA__database__DB_TYPE = "sqlite3";
      GITEA__database__PATH = "/data/gitea/gitea.db";

      # Server configuration
      GITEA__server__DOMAIN = "git.tongatime.us";
      GITEA__server__ROOT_URL = "https://git.tongatime.us/";
      GITEA__server__HTTP_PORT = "3000";

      # Security
      GITEA__security__INSTALL_LOCK = "true";
      GITEA__security__SECRET_KEY_FILE = "/run/secrets/gitea_secret_key";

      # Service configuration
      GITEA__service__DISABLE_REGISTRATION = "true";
      GITEA__service__REQUIRE_SIGNIN_VIEW = "false";
      ENABLE_PASSKEY_AUTHENTICATION = "true";

      # Repository settings
      GITEA__repository__ROOT = "/data/git/repositories";
      GITEA__repository__ENABLE_PUSH_CREATE_USER = "true";
    };
  };

  # Create persistent storage directory with correct permissions
  systemd.tmpfiles.rules = [
    "d /var/lib/gitea 0755 1000 1000 - -"
  ];
}
