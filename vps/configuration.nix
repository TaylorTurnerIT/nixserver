{ config, pkgs, lib, ... }:

/*
    VPS Proxy Server Configuration
    
    This configuration sets up a VPS server to act as a secure proxy gateway to a home server using Tailscale and Caddy's Layer 4 proxy.
    
    Key Components:
        - Security Hardening: Firewall, SSH hardening, Fail2Ban, Auditd
        - Tailscale: Secure tunnel to home server
        - Caddy Layer 4 Proxy: Forward Minecraft traffic over Tailscale
    
    Decisions are documented per component.
*/
{
  imports = [ 
    # Standard Oracle Cloud hardware support
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "vps-gateway";
  networking.networkmanager.enable = true;

  # --- SECURITY HARDENING ---
  
  # 1. Firewall: Deny everything by default
  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [ 
    22    # SSH (We will harden this below)
    25565 # Minecraft Public Access
  ];
  networking.firewall.allowedUDPPorts = [ 25565 ]; # Voice Chat (Simple Voice Chat mod)

  # 2. SSH Hardening
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password"; # Only keys allowed
      PasswordAuthentication = false;        # Disable passwords completely
      KbdInteractiveAuthentication = false;
    };
  };

  # 3. Fail2Ban: Ban IPs that spam SSH or other ports
  services.fail2ban = {
    enable = true;
    maxretry = 8;
    bantime = "24h"; # Ban for 24 hours
    ignoreIP = [
      "100.0.0.0/8"  # Don't ban Tailscale IPs
    ];
  };

  # 4. Auditd: Kernel-level auditing for security monitoring
  security.audit.enable = true;
  security.auditd.enable = true;

  # --- TAILSCALE (The Tunnel) ---
  services.tailscale.enable = true;
  
  # Ensure we trust the tailscale interface for internal routing
  networking.firewall.trustedInterfaces = [ "tailscale0" ];

  # --- CADDY LAYER 4 PROXY ---
  services.caddy = {
    enable = true;
    # Build Caddy with the Layer 4 plugin
    package = pkgs.caddy.withPlugins {
      plugins = [ "github.com/mholt/caddy-l4" ];
      hash = lib.fakeSha256; # ⚠️ REPLACE THIS with the actual hash after first failed build
    };

    # Global options
    globalConfig = ''
      # Optional: Enable debug logs if you are troubleshooting
      # debug
    '';

    # The Layer 4 Proxy Configuration
    extraConfig = ''
      layer4 {
        :25565 {
          route {
            proxy {
              # REPLACE with your Home Server's Tailscale IP
              upstream 100.73.119.72:25565 
            }
          }
        }
      }
    '';
  };
  
  system.stateVersion = "24.11";
}