{ config, pkgs, ... }:

{
  virtualisation.oci-containers.containers.act_runner = {
    image = "gitea/act_runner:latest";
    autoStart = true;
    
    # We set the working directory to match the host path
    # This ensures that when the runner requests a volume mount for a job,
    # the path exists on the host system.
    workdir = "/var/lib/gitea-runner";

    volumes = [
      # Data directory (Must match host path for bind-mounts to work in jobs)
      "/var/lib/gitea-runner:/var/lib/gitea-runner"
      
      # Access to Podman socket to spawn job containers
      "/var/run/podman/podman.sock:/var/run/docker.sock"
      
      # Registration Token
      "${config.sops.secrets.gitea_runner_token.path}:/run/secrets/gitea_runner_token:ro"
    ];

    environment = {
      # URL to reach Gitea. 
      # Since we are on the same host, we use the host's Tailscale IP and the mapped port (3001).
      GITEA_INSTANCE_URL = "http://100.73.119.72:3001";
      
      # Read the token from the secret file
      GITEA_RUNNER_REGISTRATION_TOKEN_FILE = "/run/secrets/gitea_runner_token";
      
      GITEA_RUNNER_NAME = "homelab-runner";
      
      # Default labels for jobs
      GITEA_RUNNER_LABELS = "ubuntu-latest:docker://gitea/runner-images:ubuntu-latest,ubuntu-22.04:docker://gitea/runner-images:ubuntu-latest";
    };
  };

  # Define the secret
  sops.secrets.gitea_runner_token = {
    owner = "root"; # Podman containers run as root by default
  };

  # Ensure the data directory exists with correct permissions
  systemd.tmpfiles.rules = [
    "d /var/lib/gitea-runner 0755 root root - -"
  ];
}