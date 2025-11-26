{ config, pkgs, ... }:

{
  imports = [
    ./homepage.nix
    # ./minecraft.nix
  ];

  # Global Podman Configuration
  virtualisation.oci-containers.backend = "podman";
}