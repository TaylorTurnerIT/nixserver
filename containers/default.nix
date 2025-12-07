{ config, pkgs, ... }:

{
  /*
    Configuration Imports
    Import configurations for specific services.

    Each imported file contains the Caddy configuration for a specific service, such as a homepage or a Minecraft server.
  */
  imports = [
    ./homepage.nix
    ./minecraft.nix
    ./foundryvtt/foundry_portal.nix
    ./foundryvtt/foundryvtt.nix
  ];

  # Global Podman Configuration
  virtualisation.oci-containers.backend = "podman";
}