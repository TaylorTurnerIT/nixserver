{
  description = "Proxmox Homelab & VPS";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    
    # Add Home Manager
    home-manager.url = "github:nix-community/home-manager/release-24.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    # Add sops-nix for managing secrets
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";

    jexactyl-src = {
      url = "github:jexactyl/jexactyl"; 
      flake = false; # It's not a nix flake itself
  };
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, home-manager, disko, sops-nix, ... }: {
    # --- HOME SERVER ---
    nixosConfigurations.homelab = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; }; # Ensure inputs are passed to modules
      modules = [
        disko.nixosModules.disko
        ./disko-config.nix
        ./configuration.nix
        sops-nix.nixosModules.sops
      ];
    };

    # --- UBUNTU VPS CONFIGURATION ---
    homeConfigurations."ubuntu" = home-manager.lib.homeManagerConfiguration {
      # The VPS is x86_64 (AMD/Intel)
      pkgs = import nixpkgs { 
        system = "x86_64-linux"; 
        config.allowUnfree = true; 
      };
      
      # Pass unstable for the Caddy build
      extraSpecialArgs = {
        pkgs-unstable = import nixpkgs-unstable {
          system = "x86_64-linux";
          config.allowUnfree = true;
        };
      };

      modules = [ 
        ./vps/home.nix
        # sops-nix.homeManagerModules.sops 
        ];
    };
  };
}