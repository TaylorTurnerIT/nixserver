{ config, pkgs, modulesPath, ... }:

{
  imports = [ 
    (modulesPath + "/profiles/qemu-guest.nix")
    ./disko-config.nix
    ./containers/default.nix
    ./network/default.nix
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
    settings = {
      PermitRootLogin = "prohibit-password"; # Only keys allowed
      PasswordAuthentication = false;        # Disable passwords completely
      KbdInteractiveAuthentication = false;  # Disable keyboard-interactive auth
    };
  };

  # SOPS
  sops.defaultSopsFile = ./secrets/secrets.yaml;
  sops.defaultSopsFormat = "yaml";
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  sops.secrets.cloudflare_token = {
    owner = "acme";
  };

  # users.users.nixos.openssh.authorizedKeys.keys = [
  #   # Public Keys default nixos user
  # "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJB9MG22hSHdYpwIWFRanUF88YvOYNcrV1zxAvv2RDJt taylort3450@syn-2600-6c5d-567f-3f2b-c338-35e0-ec14-df45.biz6.spectrum.com" 
  # ];

  users.users.root.openssh.authorizedKeys.keys =  [
    # Public Keys for root user
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJB9MG22hSHdYpwIWFRanUF88YvOYNcrV1zxAvv2RDJt taylort3450@syn-2600-6c5d-567f-3f2b-c338-35e0-ec14-df45.biz6.spectrum.com" 
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

  # --- NIX SETTINGS ---
  nix.settings.download-buffer-size = 524288000; # 500MiB
  # Don't touch
  system.stateVersion = "25.05"; 
}