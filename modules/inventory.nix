{
  config,
  inputs,
  lib,
  ...
}:
let
  inherit (lib) mkOption types;
  optionalString = types.nullOr types.str;
  stringList = types.listOf types.str;
  reservationType = types.nullOr (types.submodule {
    options = {
      macAddress = mkOption {
        type = types.str;
        description = "MAC address reserved for this host by Kea.";
      };
      scope = mkOption {
        type = types.str;
        description = "Kea reservation scope.";
      };
    };
  });
  routerType = types.submodule {
    options = {
      mode = mkOption {
        type = types.enum [
          "standby"
          "primary"
          "vrrp"
        ];
        description = ''
          `primary`: holds the gateway address and the WAN statically.
          `standby`: a manual spare with a `primary` specialisation
          (docs/router-failover.md). `vrrp`: a member of the VRRP pair;
          keepalived decides which member holds the gateway and the WAN
          (docs/router-vrrp.md).
        '';
      };
      devices = lib.genAttrs [ "wan" "lan" "management" ] (_: {
        name = mkOption {
          type = types.str;
          description = "Stable interface name.";
        };
        mac = mkOption {
          type = optionalString;
          default = null;
          description = "Hardware address used to pin the interface name.";
        };
      });
      lanAddress = mkOption {
        type = types.str;
        description = "Node-local LAN IPv4 address in CIDR notation.";
      };
      managementAddress = mkOption {
        type = types.str;
        description = "Management IPv4 address in CIDR notation.";
      };
      wanBandwidth = mkOption {
        type = types.str;
        default = "1Gbit";
        description = "WAN bandwidth for router diagnostics.";
      };
      takeover = mkOption {
        type = types.nullOr (
          types.submodule {
            options = {
              wanMac = mkOption {
                type = types.str;
                description = "WAN MAC address of the router whose lease this node takes over.";
              };
              dhcpDuidRawData = mkOption {
                type = types.str;
                description = ''
                  That router's DHCP DUID as networkd DUIDRawData (DUID-EN: enterprise
                  number plus identifier, colon-separated bytes). The modem binds
                  the IPv4 lease and the delegated prefix to it.
                '';
              };
              dhcpIaid = mkOption {
                type = types.ints.unsigned;
                description = "That router's WAN IAID, in decimal.";
              };
            };
          }
        );
        default = null;
        description = ''
          WAN identity of the router this standby replaces. When set, the host
          gets a `primary` specialisation for manual failover
          (docs/router-failover.md).
        '';
      };
      vrrpPriority = mkOption {
        type = types.ints.between 1 254;
        default = 100;
        description = ''
          VRRP priority in `vrrp` mode. The member with the highest priority is
          the preferred router: Kea's HA primary and the only one running
          Pangolin and PXE (docs/router-vrrp.md).
        '';
      };
      vrrpPreemptDelay = mkOption {
        type = types.ints.between 0 1000;
        default = 300;
        description = ''
          Seconds a recovered higher-priority router waits, as BACKUP, before
          taking the role back (keepalived preempt_delay; max 1000). Avoids a
          second failover when a flapping router returns. See
          docs/router-election.md#preemption-and-stability.
        '';
      };
      ddnsServices = mkOption {
        type = stringList;
        default = [ ];
        description = "Public Cloudflare labels owned by the primary router.";
      };
    };
  };
  hostType = types.submodule (
    { config, ... }:
    {
      options = {
        system = mkOption {
          type = optionalString;
          default = null;
          description = "Nix system for hosts with a known platform.";
        };
        kind = mkOption {
          type = types.enum [
            "nixos"
            "darwin"
            "proxmox"
            "appliance"
            "other"
          ];
          description = "Operating system or device class.";
        };
        addresses = {
          ip = mkOption {
            type = optionalString;
            default = null;
            description = "Static or reserved IP address.";
          };
          hostname = mkOption {
            type = optionalString;
            default = null;
            description = "DNS name when the primary address is a name.";
          };
          sshHostname = mkOption {
            type = optionalString;
            default = null;
            description = "Explicit SSH endpoint, including management addresses.";
          };
        };
        sshTarget = mkOption {
          type = optionalString;
          readOnly = true;
          default =
            if config.addresses.sshHostname != null then
              config.addresses.sshHostname
            else if config.addresses.hostname != null then
              config.addresses.hostname
            else
              config.addresses.ip;
          description = "SSH endpoint derived from the inventory addresses.";
        };
        deployTarget = mkOption {
          type = optionalString;
          readOnly = true;
          # WHY: a VRRP member's management address is reached through the
          # LAN gateway, which the member itself may be holding; a deploy that
          # moves the VIP then cuts its own SSH session and rolls back
          # (2026-11-27, docs/router-vrrp.md). The LAN address is on the
          # deployer's own segment and survives a handover.
          # GOTCHA: only in vrrp mode. A primary holds just the gateway on the
          # LAN and a standby none, so their node address is absent.
          default =
            if config.router != null && config.router.mode == "vrrp" then
              builtins.head (lib.splitString "/" config.router.lanAddress)
            else
              config.sshTarget;
          description = "Address deploys and fleet-status connect to: a VRRP member's LAN address, otherwise sshTarget.";
        };
        inventoryName = mkOption {
          type = types.str;
          readOnly = true;
          description = "Canonical host key from homelab.hosts.";
        };
        fqdn = mkOption {
          type = types.str;
          readOnly = true;
          description = "Fully qualified host name derived from the inventory key and domain.";
        };
        sshHostKeyAlias = mkOption {
          type = types.str;
          readOnly = true;
          description = "SSH host certificate identity derived from the host FQDN.";
        };
        deployBackend = mkOption {
          type = types.enum [ "clan" "deploy-rs" ];
          readOnly = true;
          description = "Deployment backend selected from the host's roles.";
        };
        sshUser = mkOption {
          type = types.str;
          default = "deepwatrcreatur";
          description = "Default SSH login.";
        };
        aliases = mkOption {
          type = stringList;
          default = [ ];
          description = "Additional names for this host.";
        };
        cacheAliases = mkOption {
          type = stringList;
          default = [ ];
          description = "Host aliases that unified recognizes as legacy cache server names.";
        };
        dhcpReservation = mkOption {
          type = reservationType;
          default = null;
          description = "Optional Kea reservation for a host with a stable address.";
        };
        description = mkOption {
          type = types.str;
          default = "";
          description = "Human-readable host description.";
        };
        roles = mkOption {
          type = stringList;
          default = [ ];
          description = "Host roles used for grouping and Clan inventory tags.";
        };
        router = mkOption {
          type = types.nullOr routerType;
          default = null;
          description = "Router role settings for hosts composed with the router aspect.";
        };
        includeSsh = mkOption {
          type = types.bool;
          default = true;
          description = "Include this host in generated SSH configuration.";
        };
        archived = mkOption {
          type = types.bool;
          default = false;
          description = "Keep this record for historical or compatibility purposes.";
        };
        clanCandidate = mkOption {
          type = types.bool;
          default = false;
          description = "Compose an offline Clan host candidate without enabling the fleet deployment dispatcher.";
        };
        migrated = mkOption {
          type = types.bool;
          default = false;
          description = "Enable host composition and deployment in this flake.";
        };
      };
    }
  );
in
{
  options.homelab.domain = mkOption {
    type = types.str;
    default = "deepwatercreature.com";
    description = "LAN DNS zone; SSH host certificates name <machine>.<domain>.";
  };

  options.homelab.gateway = mkOption {
    type = types.str;
    default = "10.10.10.1";
    description = ''
      LAN gateway address. A `primary` router holds it statically; under
      `vrrp` keepalived moves it to the MASTER. Not any host's own address.
    '';
  };

  options.homelab.networks = mkOption {
    type = types.attrsOf (types.submodule {
      options = {
        cidr = mkOption { type = types.str; description = "Network CIDR."; };
        prefixLength = mkOption { type = types.ints.between 0 128; description = "Network prefix length."; };
      };
    });
    default = import ../inventory/networks.nix;
    description = "Homelab network prefixes used to compose router roles.";
  };

  options.homelab.hosts = mkOption {
    type = types.attrsOf hostType;
    description = "Homelab inventory keyed by canonical host name.";
  };

  config = {
    homelab.hosts = lib.mapAttrs (name: host: host // {
      inventoryName = name;
      fqdn = "${name}.${config.homelab.domain}";
      sshHostKeyAlias = "${name}.${config.homelab.domain}";
      deployBackend = if builtins.elem "router" (host.roles or [ ]) then "deploy-rs" else "clan";
    }) (
      import ../inventory/hosts.nix
    );
    perSystem =
      { pkgs, ... }:
      {
        checks.inventory-matches-unified = import ../inventory/check.nix {
          inherit lib pkgs;
          inherit (config.homelab) hosts;
          inherit (config.homelab) networks;
          domain = config.homelab.domain;
          unified = inputs.unified.outPath;
        };
      };
  };
}
