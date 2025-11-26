{ ... }:


/* 
    Network Services Configuration
    This file imports the network-related configurations for the server, including Tailscale and Caddy.

    Services Included:
    - Tailscale: A mesh VPN service that connects devices securely.
    - Caddy: A web server that provides automatic HTTPS and reverse proxy capabilities.
*/
{
  imports = [
    ./tailscale.nix
    ./caddy.nix
  ];
}