{ config, pkgs, ... }:

{
  /*
    Configuration Imports
    Import configurations for specific services.

    Each imported file contains the Caddy configuration for a specific service, such as a homepage or a Minecraft server.
  */
  imports = [
    ./homepage.nix
    # ./minecraft.nix
    ./foundryvtt/foundry_portal.nix
    ./foundryvtt/foundry_chef.nix
    ./observability.nix
    ./gitea.nix
    ./act_runner.nix
    ./pterodactyl/default.nix
  ];

  # Global Podman Configuration
  virtualisation.oci-containers.backend = "podman";
}