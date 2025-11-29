{
  description = "Proxmox Homelab Server";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11"; # Stable NixOS release
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable"; # For latest packages if needed
    disko.url = "github:nix-community/disko"; # Disk partitioning module
    disko.inputs.nixpkgs.follows = "nixpkgs"; # Ensure disko uses the same nixpkgs
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, disko, ... }: {
    # Homelab Server Configuration
    nixosConfigurations.homelab = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        disko.nixosModules.disko
        ./disko-config.nix
        ./configuration.nix
      ];
    };    

    # Oracle VPS Proxy Configuration
    nixosConfigurations.vps-proxy = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { # Provide access to unstable packages
        pkgs-unstable = import nixpkgs-unstable {
          system = "x86_64-linux";
          config.allowUnfree = true;
        };
      };
      modules = [
        disko.nixosModules.disko
        ./vps/disko.nix
        ./vps/configuration.nix
      ];
    };
  };
}