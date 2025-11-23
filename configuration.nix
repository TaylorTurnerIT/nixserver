{ config, pkgs, modulesPath, ... }:

{
  imports = [ 
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  # --- BOOTLOADER ---
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "homelab";
  networking.networkmanager.enable = true;

  # --- PROXMOX INTEGRATION ---
  services.qemuGuest.enable = true; #
  boot.kernelModules = [ "kvm-intel" ]; 
  
  # --- SERVER HARDENING ---
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "yes"; # Temporarily yes for install, change to "no" later
  };

  # users.users.nixos.openssh.authorizedKeys.keys = [
  #   # Public Keys default nixos user
  #   "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINBbBcwPIsJV1MBuNS6V9Agwbc5hYc0Ojgi7UA3EXbAD taylorturnerit@gmail.com" 
  # ];

  users.users.root.openssh.authorizedKeys.keys =  [
    # Public Keys for root user
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINBbBcwPIsJV1MBuNS6V9Agwbc5hYc0Ojgi7UA3EXbAD taylorturnerit@gmail.com" 
  ];

  # --- PODMAN ---
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    defaultNetwork.settings.dns_enabled = true;
  };

  # --- PACKAGES ---
  environment.systemPackages = with pkgs; [ 
    git 
    htop
    nano
    neofetch
    ];

  # Don't touch
  system.stateVersion = "25.05"; 
}