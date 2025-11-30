{ config, pkgs, pkgs-unstable, ... }:

let
  # Define the package with the Layer 4 plugin
  caddyPackage = pkgs-unstable.caddy.withPlugins {
    plugins = [ "github.com/mholt/caddy-l4" ];
    hash = "sha256-k1eU+rOq3uvy6t9qKCXw0C514X447F0e8q0XsswF9X8="; 
  };

  # Define the Caddyfile content
  caddyConfig = ''
    {
      # Global options (optional)
      # debug
    }

    layer4 {
      :25565 {
        route {
          proxy {
            # Homelab's Tailscale IP
            upstream 100.73.119.72:25565 
          }
        }
      }
    }
  '';
in
{
  home.username = "ubuntu";
  home.homeDirectory = "/home/ubuntu";
  home.stateVersion = "24.11";

  # Install Caddy in the user profile so you can run 'caddy' manually if needed
  home.packages = [ caddyPackage ];

  # 1. Write the configuration file to ~/.config/caddy/Caddyfile
  xdg.configFile."caddy/Caddyfile".text = caddyConfig;

  # 2. Create the Systemd User Service
  systemd.user.services.caddy = {
    Unit = {
      Description = "Caddy Layer 4 Proxy";
      After = [ "network.target" ];
    };
    Service = {
      # %h resolves to the home directory
      ExecStart = "${caddyPackage}/bin/caddy run --config %h/.config/caddy/Caddyfile --adapter caddyfile";
      Restart = "always";
      RestartSec = "5s";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  programs.home-manager.enable = true;
}