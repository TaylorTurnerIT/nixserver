{ config, pkgs, pkgs-unstable, ... }:

let
  caddyPackage = pkgs-unstable.caddy.withPlugins {
    plugins = [ "github.com/mholt/caddy-l4@v0.0.0-20251124224044-66170bec9f4d" ];
    hash = "sha256-g3Ca24Boxb9VkSCrNvy1+n5Dfd2n4qEpi2bIOxyNc6g="; 
  };

  # Use JSON for Layer 4 configuration (It is much more reliable for plugins)
  caddyConfig = builtins.toJSON {
    apps = {
      layer4 = {
        servers = {
          minecraft = {
            listen = [ ":25565" ];
            routes = [
              {
                handle = [
                  {
                    handler = "proxy";
                    upstreams = [
                      { dial = ["100.73.119.72:25565"]; } # <--- Verify this is correct
                    ];
                  }
                ];
              }
            ];
          };
        };
      };
    };
  };
in
{
  home.username = "ubuntu";
  home.homeDirectory = "/home/ubuntu";
  home.stateVersion = "24.11";

  home.packages = [ caddyPackage ];

  # Write config to ~/.config/caddy/config.json
  xdg.configFile."caddy/config.json".text = caddyConfig;

  systemd.user.services.caddy = {
    Unit = {
      Description = "Caddy Layer 4 Proxy";
      After = [ "network-online.target" ];
    };
    Service = {
      # Use --adapter json explicitly
      ExecStart = "${caddyPackage}/bin/caddy run --config %h/.config/caddy/config.json --adapter json";
      Restart = "always";
      RestartSec = "10s";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  programs.home-manager.enable = true;
}