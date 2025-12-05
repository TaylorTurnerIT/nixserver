{ config, pkgs, ... }:

/*
  Caddy Reverse Proxy and ACME Configuration

  This configuration sets up Caddy as a reverse proxy for various services running on the server, along with automatic HTTPS using Let's Encrypt via ACME with DNS challenge through Cloudflare.

  Decisions are documented per component.
*/

/* 
  Domain and Email Configuration
    Define the domain and email to be used for ACME certificate generation.
*/
let
  domain = "tongatime.us"; 
  email = "taylorturnerit@gmail.com";
in
{
  /* 
    ACME (Let's Encrypt) Configuration
    This fetches certs using DNS challenge so we don't need open ports

    Caddy is known to handle HTTPS automatically, but requires a ping to Let's Encrypt. Using DNS challenge with Cloudflare allows us to get wildcard certs without exposing ports.

    Why wildcard?
      Easier management of multiple subdomains
      Future-proofing for adding more services

    Why Caddy?
      Popularity and ease of use

    Why Cloudflare?
      Reliable DNS provider with good API support for DNS challenges
      Cheap!
  */
  security.acme = {
    acceptTerms = true;
    defaults.email = email;
    certs."${domain}" = {
      domain = domain;                      # Main domain (tongatime.us)
      extraDomainNames = [ "*.${domain}" ]; # Wildcard (*.tongatime.us)
      dnsProvider = "cloudflare";
      credentialsFile = config.sops.secrets.cloudflare_token.path;
      postRun = "systemctl is-active caddy && systemctl reload caddy || true";
    };
  };

  /*
    Caddy Reverse Proxy Configuration
    This sets up Caddy to reverse proxy requests to various services running on the host.

    This system will allow me to use my domain to access internal services securely. 

    

    Services:
    - Proxmox Web UI (https://proxmox.tongatime.us)
    - Dashboard (https://tongatime.us)
  */

  services.caddy = {
    enable = true;
    
    # We use the certs generated above
    virtualHosts = {
      
      /*
      Service:  Proxmox Web UI (Proxmox)
                The Proxmox web interface is used to manage virtual machines and containers.
                
                proxmox.tongatime.us -> https://192.168.1.36:8006

                We are choosing to trust the self-signed certs used by Proxmox internally by skipping TLS verification since it is not exposed to the public internet.
      */
      "proxmox.${domain}" = {
        useACMEHost = domain;
        extraConfig = ''
          reverse_proxy https://192.168.1.36:8006 {
            transport http {
              tls_insecure_skip_verify # Proxmox uses self-signed certs internally
            }
          }
        '';
      };

      /* DEFAULT
        Service:  Homepage (Dashboard)
                  Homepage dashboard for quick access to services and status.
                  
                  tongatime.us -> https://192.168.1.36:3000
      */
      "${domain}" = {
        useACMEHost = domain;
        # We use http because the container listens on plain http internally.
        extraConfig = "reverse_proxy http://192.168.1.36:3000";
      };

    };
  };

  /*
    Permission Setup for ACME Certs

    By default, Caddy cannot read the ACME certs because they are stored in /var/lib/acme with restrictive permissions.

    To fix this, we add Caddy to the 'acme' group.
    1. Caddy needs access to the ACME certs stored in /var/lib/acme.
    2. We add Caddy to the 'acme' group to grant read permissions.
  */
  users.users.caddy.extraGroups = [ "acme" ];
}