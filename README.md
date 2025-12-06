# ❄️ Tonga NixLab

> **A fully declarative, immutable infrastructure stack for self-hosting services, utilizing a hybrid architecture of NixOS and Nix-on-Ubuntu.**

![Nix](https://img.shields.io/badge/Nix-Reproducible_Builds-5277C3?style=for-the-badge&logo=nixos&logoColor=white)  ![Oracle Cloud](https://img.shields.io/badge/Oracle_Cloud-F80000?style=for-the-badge&logo=oracle&logoColor=white)![Ubuntu](https://img.shields.io/badge/Ubuntu-E95420?style=for-the-badge&logo=ubuntu&logoColor=white)![Home Manager](https://img.shields.io/badge/Home_Manager-Enabled-5277C3?style=for-the-badge&logo=nixos&logoColor=white)

![Tailscale](https://img.shields.io/badge/Tailscale-Mesh_VPN-orange?style=for-the-badge&logo=tailscale&logoColor=white) ![Caddy](https://img.shields.io/badge/Caddy-Layer_4_Proxy-green?style=for-the-badge&logo=caddy&logoColor=white) ![Minecraft](https://img.shields.io/badge/Minecraft-Java_Edition-green?style=for-the-badge&logo=minecraft&logoColor=white)


## Overview

This repository contains the Infrastructure as Code (IaC) configuration for the **Tonga** homelab and its public-facing gateway. The core philosophy of this project is **strict reproducibility**. By leveraging Nix flakes, every component of the server is defined in code.

### The Hybrid Challenge

While the goal is pure NixOS everywhere, the public gateway runs on an Oracle VPS which presented specific technical limitations preventing a full NixOS install. To maintain declarative rigor, I implemented a hybrid approach:

  * **Homelab:** Pure **NixOS** (Immutable system).
  * **VPS Gateway:** **Ubuntu** bootstrapped with **Nix + Home Manager** (Declarative user-space).

## 🏗 Architecture
> “This containers revolution is changing the basic act of software consumption. It’s redefining this much more lightweight, portable unit, or atom, that is much easier to manage… It’s a gateway to dynamic management and dynamic systems.” – Craig McLuckie, Google.

The network utilizes a **Zero Trust** model. No ports are open on the Homelab's public IP. All ingress traffic is routed through the VPS Gateway via a Tailscale mesh, using Caddy for Layer 4 proxying.

```mermaid
flowchart LR
    User(Public Internet User)
    
    subgraph VPS ["Oracle Cloud VPS (Ubuntu + Nix)"]
        direction TB
        Ingress[Ingress :25565]
        CaddyL4[Caddy Layer 4 Proxy]
        TS_VPS[Tailscale Interface]
    end

    subgraph Home ["Homelab (NixOS)"]
        direction TB
        TS_Home[Tailscale Interface]
        Podman[Podman OCI Backend]
        MC[Minecraft Container]
        Homepage[Homepage Dashboard]
        CaddyRev[Caddy Reverse Proxy]
    end

    User -->|Connects to Public IP| Ingress
    Ingress --> CaddyL4
    CaddyL4 -->|Proxy via 100.x.y.z| TS_VPS
    TS_VPS -.->|Encrypted Tunnel| TS_Home
    TS_Home --> MC
    CaddyRev --> Homepage
    
    style VPS fill:#e1f5fe,stroke:#01579b
    style Home fill:#f3e5f5,stroke:#4a148c
```

## 🖥️ Services

The homelab currently hosts:

  * **Homepage** (`tongatime.us`) - Service dashboard with container monitoring
  * **Minecraft** (`mc.tongatime.us`) - Java Edition server (whitelisted)
  * **Proxmox** (`proxmox.tongatime.us`) - Hypervisor management interface

## Key Features

### 🛡️ Secure Ingress Gateway

Instead of exposing the home IP, an Oracle VPS acts as a shield.

  * **Caddy L4 Proxy:** Uses `caddy-l4` to proxy raw TCP traffic  over Tailscale.
  * **Tailscale Mesh:** The VPS and Homelab communicate over an encrypted WireGuard mesh. The VPS bans malicious IPs via **Fail2Ban** but whitelists the Tailscale subnet (`100.0.0.0/8`).

### ❄️ Declarative Services

Services are defined in Nix, ensuring that `rebuild switch` brings the system to the exact desired state.

  * **Homepage:** A centralized dashboard at the root domain providing service monitoring and quick access. Integrated with the Docker socket to display real-time container status.
  * **Minecraft:** Configured via `virtualisation.oci-containers`. The entire server state, including hardware configuration, Message of the Day (MOTD), and whitelist, is version controlled.
  * **Reverse Proxy:** Caddy handles internal HTTPS with automatic ACME DNS challenges via Cloudflare, enabling wildcard certs (`*.tongatime.us`) without opening ports.

### 🚀 Reproducible Deployment Environment
> It works on my machine! - Everyone

To solve the "it works on my machine" problem for deployment, the deployer itself is containerized.

  * **Containerfile:** A custom Docker image (`homelab-deployer`) pre-installs `nixos-rebuild`, `nixos-anywhere`, and SSH configs.
  * **Bootstrap Script:** `deploy-vps.sh` automates the conversion of a fresh Ubuntu box into a Nix-managed node, installing the Nix daemon, setting up trusted users, and applying the Home Manager flake.

## 🛠️ Technical Stack
> "Oh, and you’re going to be lighter weight than a VM? Awesome. I’m all about containers now.” – Steven Pousty, Red Hat. 

| Component | Technology | Description |
| :--- | :--- | :--- |
| **OS (Home)** | NixOS 24.11 | Pure, immutable Linux distribution. |
| **OS (VPS)** | Ubuntu + Home Manager | Declarative user configuration on traditional Linux. |
| **Containers** | Podman | Daemonless container engine (Docker compatible). |
| **Dashboard** | Homepage | Service monitoring and management dashboard. |
| **DNS** | DNSControl | Declarative DNS zone management for Cloudflare. |
| **Secrets** | sops-nix | Encrypted secret storage in version control. |
| **Storage** | Disko | Declarative disk partitioning and formatting. |
| **Networking** | Tailscale | Mesh VPN for secure internal communication. |
| **Proxy** | Caddy | Web server with Layer 4 and Reverse Proxy capabilities. |

## 📂 Directory Structure

```graphql
.
├── build-deployer.sh     # Builds the deployment container
├── configuration.nix     # Main NixOS Homelab configuration
├── Containerfile         # Definition of the reproducible deployer image
├── containers/           # Service definitions (Podman)
│   ├── default.nix       # Imports active containers
│   ├── homepage.nix      # Homepage dashboard OCI config
│   └── minecraft.nix     # Minecraft server OCI config
├── deploy-dns.sh         # Script to deploy DNS changes
├── deploy-nix.sh         # Script to deploy to Homelab
├── deploy-vps.sh         # Script to bootstrap and deploy to VPS
├── disko-config.nix      # ZFS/EXT4 partition layouts
├── flake.nix             # Entry point for system configurations
├── network/              # Networking configuration
│   ├── caddy.nix         # Reverse proxy & ACME settings
│   ├── dnsconfig.js      # DNSControl configuration
│   ├── dns_zones.yaml    # Declarative DNS zones
│   └── tailscale.nix     # VPN configuration
├── secrets/              # Encrypted secrets (sops-nix)
│   └── secrets.yaml
└── vps/                  # VPS-specific configuration
    ├── home.nix          # Home Manager config for Ubuntu
    └── configuration.nix # Partial system config
```

## 🚀 Deployment Guide

### Prerequisites

  * Podman installed on your local machine.
  * SSH access to target hosts.
  * A `secrets/` directory (ignored by git) containing API tokens and private SSH keys.

### 1\. The Deployer

Build the hermetic deployment environment. This ensures you are using the exact same version of `nix` and `nixos-rebuild` regardless of your host OS.

```bash
./build-deployer.sh
```

### 2\. Deploying to Homelab (NixOS)

To update the main server:

```bash
./deploy-nix.sh          # Updates existing system
./deploy-nix.sh --install # Wipes disk and installs fresh (NixOS Anywhere)
```

### 3\. Deploying to VPS (Ubuntu)

To bootstrap or update the gateway:

```bash
./deploy-vps.sh
```

*This script will SSH into the Ubuntu host, install the Nix package manager if missing, configure multi-user support, and apply the `homeConfigurations."ubuntu"` flake output.*

### 4\. Managing DNS Records

To update DNS records declaratively:

```bash
./deploy-dns.sh          # Preview and push DNS changes
./deploy-dns.sh --revert backups/dns_zones_TIMESTAMP.yaml  # Revert to backup
```

*This script uses DNSControl to manage Cloudflare DNS zones from `network/dns_zones.yaml`. All changes are previewed before being applied.*

## 🗺️ Roadmap
> "Debugging is twice as hard as writing the code in the first place. Therefore, if you write the code as cleverly as possible, you are, by definition, not smart enough to debug it." - Brian Kernighan, Canadian

Future plans are documented in the project TODOs.

👉 **See [TODO.md](https://github.com/TaylorTurnerIT/nixserver/blob/master/README.md) for the full roadmap.**

-----

**[View Source](https://github.com/taylorturnerit/nixserver)**
