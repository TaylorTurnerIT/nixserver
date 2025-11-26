{ config, pkgs, ... }:


/*
  Tailscale Network Configuration

  We are setting up Tailscale to require all containers to use Tailscale for networking by default. We will include exceptions, but those must be explicitly defined. For example, a public Minecraft server may need to be accessible outside of Tailscale.

  This configuration is a zero-trust setup, meaning that all traffic is blocked by default unless explicitly allowed.

  Decisions are documented per component.
*/

{
  /*
    Enable Tailscale service
      Nix ensures the package is installed, the systemd service 
      is created, and it starts automatically on boot.
  */
  services.tailscale.enable = true;


  /*
    The Firewall Configuration
      We don't open any ports by default. All traffic is blocked unless explicitly allowed.

      We do NOT open port 22 (SSH) or 80 (HTTP) to the public internet.

      Result: If you connect via Tailscale IP, all ports are open.
              If you connect via Public IP, all ports are closed (invisible).
  */
  networking.firewall = {

    # Trust traffic on the tailscale interface
    trustedInterfaces = [ "tailscale0" ];


    # Setting checkReversePath to "loose" prevents Linux from dropping legitimate Tailscale traffic.
    checkReversePath = "loose";
  };
}