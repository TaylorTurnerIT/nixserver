{ config, pkgs, modulesPath, ... }:

	{
	imports = [ 
		(modulesPath + "/profiles/qemu-guest.nix")
		./disko-config.nix
		./containers/default.nix
		./network/default.nix
	];
	nix.settings.experimental-features = [ "nix-command" "flakes" ];

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

	# --- SOPS Config ---
	sops.defaultSopsFile = ./secrets/secrets.yaml;
	sops.defaultSopsFormat = "yaml";
	sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

	# --- SOPS Secrets ---
	sops.secrets.cloudflare_token = {
		owner = "acme";
	};
	sops.secrets.minecraft_rcon_password = {
		# We leave the owner as root because Podman runs as root (for now)
		owner = "root";
	};
	sops.secrets.foundry_admin_hash = {
		owner = "root"; # Podman runs as root by default
	};
	# --- Secrets for Foundry VTT ---
	sops.secrets.foundry_username = {};
	sops.secrets.foundry_password = {};
	sops.secrets.foundry_admin_pass = {};

	# Create the config.json template for the container
	sops.templates."foundry_secrets.json" = {
		content = ''
		{
			"foundry_username": "${config.sops.placeholder.foundry_username}",
			"foundry_password": "${config.sops.placeholder.foundry_password}",
			"foundry_admin_key": "${config.sops.placeholder.foundry_admin_pass}"
		}
		'';
		mode = "0444";
	};

	# --- Gitea Secrets ---
	sops.secrets.gitea_secret_key = {
		owner = "root"; # Podman runs as root
	};
	sops.secrets.github_mirror_token = {
		owner = "root";
	};

	# users.users.nixos.openssh.authorizedKeys.keys = [
	#   # Public Keys default nixos user
	# "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJB9MG22hSHdYpwIWFRanUF88YvOYNcrV1zxAvv2RDJt taylort3450@syn-2600-6c5d-567f-3f2b-c338-35e0-ec14-df45.biz6.spectrum.com" 
	# ];

	users.users.root.openssh.authorizedKeys.keys =  [
		# Public Keys for root user
		"ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJB9MG22hSHdYpwIWFRanUF88YvOYNcrV1zxAvv2RDJt taylort3450@syn-2600-6c5d-567f-3f2b-c338-35e0-ec14-df45.biz6.spectrum.com"
	];

	# Dedicated user for running rootless containers
	users.users.podman-services = {
		isSystemUser = true;
		group = "podman-services";
		home = "/var/lib/podman-services";
		createHome = true;
		description = "Rootless Podman service containers";

		# Enable lingering so systemd user services persist after logout
		linger = true;

		# Configure subordinate UID/GID ranges for user namespaces
		# Host UID 100000 maps to container UID 0 (root inside container)
		subUidRanges = [{ startUid = 100000; count = 65536; }];
		subGidRanges = [{ startGid = 100000; count = 65536; }];
	};

	users.groups.podman-services = {};

	# --- PODMAN ---
	virtualisation.podman = {
		enable = true;
		dockerCompat = false;
		defaultNetwork.settings.dns_enabled = true;
	};

	# --- DOCKER ---
	virtualisation.docker = {
		enable = true;
		# Prune images automatically to save space
		autoPrune.enable = true;

		daemon.settings = {
			dns = [ "1.1.1.1" "8.8.8.8" ];
		};
  };


	# Allow rootless containers to bind to privileged ports (<1024)
	boot.kernel.sysctl."net.ipv4.ip_unprivileged_port_start" = 0;

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