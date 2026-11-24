{
  "418" = {
    kind = "appliance";
    addresses.ip = "10.10.10.59";
    description = "418 entrance doorbell camera";
    includeSsh = false;
  };

  "420" = {
    kind = "appliance";
    addresses.ip = "10.10.10.60";
    description = "420 entrance doorbell camera";
    includeSsh = false;
  };

  ap-nosheen-bedroom = {
    kind = "appliance";
    addresses.ip = "10.10.18.22";
    description = "AP11 Nosheen Bedroom";
    includeSsh = false;
  };

  ap-nosheen-living = {
    kind = "appliance";
    addresses.ip = "10.10.18.21";
    description = "AP22 Nosheen Living Room";
    includeSsh = false;
  };

  ap-ruqayya = {
    kind = "appliance";
    addresses.ip = "10.10.18.20";
    description = "AP25 Ruqayya Bedroom";
    includeSsh = false;
  };

  apt-cache = {
    kind = "other";
    addresses.ip = "10.10.11.42";
    aliases = [ "apt-proxy" ];
    description = "APT caching proxy";
    includeSsh = false;
    roles = [ "lxc" ];
  };

  atiyas-airport-extreme = {
    kind = "appliance";
    addresses.ip = "10.10.18.23";
    description = "AirPort Express/Extreme switch";
    includeSsh = false;
  };

  authentik-host = {
    kind = "nixos";
    system = "x86_64-linux";
    addresses.ip = "10.10.11.70";
    sshUser = "deepwatrcreatur";
    description = "Dedicated Authentik identity host";
    roles = [
      "remoteBuilderClient"
      "lxc"
    ];
  };

  clan-spike = {
    kind = "nixos";
    system = "x86_64-linux";
    addresses.sshHostname = "clan-spike.deepwatercreature.com";
    sshUser = "root";
    description = "Clan migration spike VM on pve-rog";
    migrated = true;
    roles = [ "vm" ];
  };

  elitedesk = {
    kind = "nixos";
    system = "x86_64-linux";
    addresses.sshHostname = "192.168.100.98";
    sshUser = "deepwatrcreatur";
    description = "Bare-metal primary router (HP EliteDesk); replaced router on 2026-11-24";
    includeDns = false;
    migrated = true;
    router = {
      # WHY: permanent primary since router's hardware is being repurposed
      # (nch-sny.22); it holds the gateway 10.10.10.1, and lanAddress is used
      # only while a standby.
      mode = "primary";
      # ConnectX-4 Lx (mlx5) since 2026-11-20, replacing the X520 that
      # dropped off PCIe twice (nch-sny.31). Port 0 has the LAN DAC, port 1
      # the WAN 10G-SR optic: the reverse of the X520 layout.
      devices = {
        wan = {
          name = "enp1s0f1np1";
          mac = "ec:0d:9a:49:a8:1f";
        };
        lan = {
          name = "enp1s0f0np0";
          mac = "ec:0d:9a:49:a8:1e";
        };
        management = {
          name = "eno1";
          mac = "24:be:05:06:9b:09";
        };
      };
      lanAddress = "10.10.10.4/16";
      managementAddress = "192.168.100.98/24";
      # WHY: router's WAN identity as the modem sees it (MAC, DUID-EN from its
      # machine-id, IAID). The primary keeps presenting it so the IPv4 lease
      # and the /56 survive the move off router.
      # Read from `networkctl status enp6s17` on router, 2026-11-22.
      takeover = {
        wanMac = "02:76:c6:01:2a:b0";
        dhcpDuidRawData = "00:00:ab:11:05:d7:c4:8d:af:eb:0b:c9";
        dhcpIaid = 227970921; # 0x0d968f69
      };
      wanBandwidth = "2.5Gbit";
      # WHY: preferred primary (docs/router-election.md); router gets 100.
      vrrpPriority = 110;
    };
    roles = [ "router" ];
  };

  emerald = {
    kind = "nixos";
    system = "x86_64-linux";
    addresses.ip = "10.10.11.55";
    sshUser = "deepwatrcreatur";
    aliases = [
      "tomahawk"
      "attic-cache"
      "cache"
      "nix-cache"
    ];
    cacheAliases = [ "attic-cache" ];
    description = "Nix binary cache server on baremetal (MSI Tomahawk)";
    roles = [
      "cacheServer"
      "desktop"
    ];
  };

  homeassistant = {
    kind = "other";
    addresses.ip = "10.10.11.84";
    aliases = [ "ha" ];
    description = "Home Assistant (Podman container on podman host)";
    includeSsh = false;
  };

  homeserver = {
    kind = "nixos";
    system = "x86_64-linux";
    addresses.ip = "10.10.11.69";
    sshUser = "deepwatrcreatur";
    aliases = [ "semaphore" ];
    description = "Home automation, Semaphore Ansible UI";
    roles = [
      "remoteBuilderClient"
      "lxc"
    ];
  };

  infisical = {
    kind = "other";
    addresses.hostname = "infisical.deepwatercreature.com";
    sshUser = "deepwatrcreatur";
    description = "Secrets management";
    includeDns = false;
  };

  lattitude = {
    kind = "nixos";
    system = "x86_64-linux";
    addresses.ip = "10.10.11.47";
    sshUser = "deepwatrcreatur";
    description = "Latitude laptop - Sway desktop kiosk (migrated)";
    # Unified retired its system definition (unified #257); this repo owns it.
    migrated = true;
    roles = [
      "remoteBuilderClient"
      "desktop"
    ];
  };

  macminim4 = {
    kind = "darwin";
    system = "aarch64-darwin";
    sshUser = "deepwatrcreatur";
    includeDns = false;
    includeSsh = false;
    description = "Mac mini M4";
  };

  phoenix = {
    kind = "nixos";
    system = "x86_64-linux";
    addresses.ip = "10.10.11.92";
    sshUser = "deepwatrcreatur";
    description = "Phoenix workstation";
    roles = [
      "remoteBuilderClient"
      "desktop"
    ];
  };

  phoenix-hp-m477 = {
    kind = "appliance";
    addresses.ip = "10.10.11.56";
    description = "HP PageWide Pro 477dn MFP printer/scanner";
    includeDns = false;
    includeSsh = false;
  };

  podman = {
    kind = "nixos";
    system = "x86_64-linux";
    addresses.ip = "10.10.11.84";
    sshUser = "deepwatrcreatur";
    aliases = [ "plex" ];
    description = "Podman container host (Plex)";
    roles = [
      "remoteBuilderClient"
      "lxc"
    ];
  };

  pve-rog = {
    kind = "proxmox";
    system = "x86_64-linux";
    addresses.ip = "10.10.11.53";
    sshUser = "root";
    description = "Proxmox node - ROG laptop";
    roles = [
      "remoteBuilderClient"
      "proxmoxNode"
    ];
  };

  pve-strix = {
    kind = "proxmox";
    system = "x86_64-linux";
    addresses.ip = "10.10.11.57";
    sshUser = "root";
    description = "Proxmox node - Strix";
    roles = [
      "remoteBuilderClient"
      "proxmoxNode"
    ];
  };

  router = {
    kind = "nixos";
    system = "x86_64-linux";
    addresses.ip = "10.10.10.1";
    addresses.sshHostname = "192.168.100.100";
    sshUser = "deepwatrcreatur";
    aliases = [
      "dns"
      "dhcp"
      "firewall"
      "router-management"
    ];
    description = "Main router/firewall running NixOS";
    roles = [ "router" ];
  };

  router-bootstrap = {
    kind = "nixos";
    system = "x86_64-linux";
    sshUser = "deepwatrcreatur";
    description = "Minimal bootstrap output for router-class installs";
    includeDns = false;
    includeSsh = false;
  };

  ruby = {
    kind = "nixos";
    system = "x86_64-linux";
    description = "Legacy remote-builder client name";
    includeDns = false;
    includeSsh = false;
    archived = true;
    roles = [ "remoteBuilderClient" ];
  };

  sapphire = {
    kind = "nixos";
    system = "x86_64-linux";
    description = "Legacy remote-builder client name";
    includeDns = false;
    includeSsh = false;
    archived = true;
    roles = [ "remoteBuilderClient" ];
  };
  scrypted-lxc = {
    kind = "other";
    addresses.ip = "10.10.11.85";
    sshUser = "root";
    description = "Dedicated Scrypted LXC container on pve-rog";
    roles = [ "lxc" ];
  };

  sw-main = {
    kind = "appliance";
    addresses.ip = "10.10.18.10";
    description = "Core switch (HRUI LG510S-4T2XS, 4x 10G RJ45 / 2x SFP+)";
    includeSsh = false;
  };

  sw-cisco-sg300-52p = {
    kind = "appliance";
    addresses.ip = "10.10.18.11";
    description = "Cisco SG300-52P (52-port PoE, managed)";
    includeSsh = false;
  };

  sw-dell-n1124t-on = {
    kind = "appliance";
    addresses.ip = "10.10.18.12";
    description = "Dell N1124T-ON (24-port, managed)";
    includeSsh = false;
  };

  sw-hp-2910al-48g-poe = {
    kind = "appliance";
    addresses.ip = "10.10.18.13";
    description = "HP 2910al-48G-PoE (J9148A)";
    includeSsh = false;
  };

  sw-dell-powerconnect = {
    kind = "appliance";
    addresses.ip = "10.10.18.14";
    description = "Dell PowerConnect (model unknown)";
    includeSsh = false;
  };

  synology-dsm = {
    kind = "appliance";
    addresses.ip = "10.10.11.88";
    sshUser = "deepwatrcreatur";
    aliases = [ "dsm" ];
    description = "Synology DSM virtual machine on pve-rog";
    roles = [ "vm" ];
  };

  vaglio = {
    kind = "nixos";
    system = "x86_64-linux";
    addresses.ip = "10.10.11.71";
    sshUser = "deepwatrcreatur";
    description = "Dedicated Vaglio (Roundtable) discussion orchestrator";
    roles = [
      "remoteBuilderClient"
      "lxc"
    ];
  };

}
