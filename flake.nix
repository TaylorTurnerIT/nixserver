{
  description = "Proxmox Homelab Server";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, disko, ... }: {
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
      modules = [
        disko.nixosModules.disko
        ./vps/disko.nix
        ./vps/configuration.nix
      ];
    };
  };
}