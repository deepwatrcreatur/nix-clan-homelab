{
  config,
  den,
  inputs,
  lib,
  ...
}:
let
  fleet = config.homelab;
  upstream = inputs.nix-router-optimized;
  standbyHosts = lib.filterAttrs (
    _: host: host.migrated && !host.archived && host.router != null && host.router.mode == "standby"
  ) fleet.hosts;
  standbySafe =
    name: host:
    let
      cfg = config.flake.nixosConfigurations.${name}.config;
      wan = cfg.systemd.network.networks."10-router-wan-primary";
      device = host.router.devices.wan.name;
      services = cfg.services;
    in
    wan.matchConfig.Name == device
    && wan.linkConfig.ActivationPolicy == "always-down"
    && (wan.networkConfig.DHCP or "no") == "no"
    && !(wan.networkConfig.IPv6AcceptRA or false)
    && !cfg.networking.useDHCP
    && !(cfg.networking.interfaces.${device}.useDHCP or false)
    && !services.router-dhcp.enable
    && !services.router-kea.enable
    && !services.kea.dhcp4.enable
    && !services.kea.dhcp6.enable
    && !services.kea.dhcp-ddns.enable
    && !services.router-ddns.enable
    && !services.router-upnp.enable
    && !services.router-mdns.enable
    && !services.router-tailscale.enable
    && !services.tailscale.enable
    && !services.router-ha.enable
    # INVARIANT: a standby must hold the replicated zones to answer local names.
    && services.router-technitium.zoneReplication.secondary.zones != [ ]
    && lib.all (
      network:
      !(network.networkConfig.IPv6SendRA or false)
      && !(network.networkConfig.DHCPPrefixDelegation or false)
      && !(network.networkConfig.DHCPServer or false)
    ) (lib.attrValues cfg.systemd.network.networks);
in
{
  den.aspects.router-role = {
    includes = [ den.aspects.router-secrets ];
    nixos =
      { config, pkgs, ... }:
      let
        host = fleet.hosts.${config.networking.hostName};
        router = host.router;
        primary = router.mode == "primary";
        inherit (router.devices) wan lan management;
        legacy = import (inputs.unified + "/lib/hosts.nix");
        topology = legacy.networks;
        lanCidr = topology.lan.cidr;
        managementCidr = topology.management.cidr;
        gateway = fleet.hosts.router.addresses.ip;
        ip = address: builtins.head (lib.splitString "/" address);
        varPath = name: config.clan.core.vars.generators."router-${name}".files.value.path;
        replicatedZones = map (name: { inherit name; }) [
          fleet.domain
          "10.10.in-addr.arpa"
        ];
      in
      {
        # UPSTREAM: the aggregate default imports router-tunnels twice.
        imports =
          (with upstream.nixosModules; [
            router-networking
            router-dhcp
            router-ddns
            router-dns-service
            router-firewall
            router-log-storage
            router-homelab
            router-optimizations
            router-tailscale
            router-observability
            router-vpn
            router-ntp
            router-kea
            router-mdns
            router-upnp
            router-ha
            router-network-security
            router-pangolin
          ])
          ++ [ ../_nixos/router-snmp.nix ];

        # GOTCHA: replies to LAN clients reaching the management IP can leave
        # through the LAN NIC. Strict reverse-path filtering drops that traffic.
        networking.firewall.checkReversePath = "loose";
        networking.resolvconf.enable = lib.mkForce false;
        networking.interfaces =
          lib.genAttrs (map (device: device.name) (lib.attrValues router.devices))
            (_: {
              useDHCP = false;
            });
        boot.kernel.sysctl = {
          "net.ipv4.conf.all.rp_filter" = 2;
          "net.ipv4.conf.default.rp_filter" = 2;
        };

        systemd.network.links = lib.mapAttrs' (
          role: device:
          lib.nameValuePair "10-router-${role}" {
            matchConfig.MACAddress = device.mac;
            linkConfig.Name = device.name;
          }
        ) (lib.filterAttrs (_: device: device.mac != null) router.devices);
        systemd.network.wait-online = {
          enable = lib.mkForce true;
          anyInterface = false;
        };
        systemd.network.networks = {
          # INVARIANT: the modem can hand its single DHCP lease to the standby
          # if the standby starts a client. Keep networkd enforcing link-down.
          "10-router-wan-primary".linkConfig.ActivationPolicy = lib.mkIf (!primary) "always-down";
          "20-router-lan" = {
            networkConfig.ConfigureWithoutCarrier = true;
            gateway = lib.optionals (!primary) [ gateway ];
          };
        };

        services = {
          router-networking = {
            enable = true;
            wan = {
              device = wan.name;
              dhcp = if primary then "yes" else "no";
              ipv6AcceptRA = primary;
              dhcpv6Client = if primary then "always" else "no";
              requiredForOnline = if primary then "routable" else "no";
            };
            routedInterfaces = {
              lan = {
                device = lan.name;
                ipv4Address = router.lanAddress;
                dns = [ "127.0.0.1" ];
                domains = [ fleet.domain ];
                requiredForOnline = "no";
                ipv6SendRA = primary;
                dhcpPrefixDelegation = primary;
              };
              management = {
                device = management.name;
                ipv4Address = router.managementAddress;
                requiredForOnline = "routable";
                ipv6SendRA = false;
                dhcpPrefixDelegation = false;
              };
            };
          };
          # WHY: standby is a manual spare. VRRP participation can be enabled
          # separately when the primary and its peers have been migrated.
          router-ha = {
            enable = false;
            priority = router.vrrpPriority;
            # WHY: a recovered elitedesk waits before taking the role back
            # (docs/router-election.md#33-preemption-and-stability).
            preemptDelay = router.vrrpPreemptDelay;
          };
          router-dhcp.enable = false;
          router-kea = {
            enable = primary;
          }
          // lib.optionalAttrs primary {
            dhcp4 = {
              interfaces = [ lan.name ];
              subnet = lanCidr;
              gatewayAddress = gateway;
              dnsServers = [ gateway ];
              defaultLeaseTimeSec = 14400;
              poolRanges = [
                {
                  start = "10.10.200.1";
                  end = "10.10.222.254";
                }
              ];
              reservations =
                lib.mapAttrsToList
                  (name: entry: {
                    hw-address = entry.dhcpReservation.macAddress;
                    ip-address = entry.ip;
                    hostname = name;
                  })
                  (
                    lib.filterAttrs (
                      _: entry: (entry.dhcpReservation or null) != null && (entry.ip or null) != null
                    ) legacy.hosts
                  );
            };
            ddns = {
              enable = true;
              tsigKeyFile = varPath "kea-ddns-tsig-key";
              tsigKeyName = "kea-ddns";
              forwardZone = fleet.domain;
              reverseZone = "10.10.in-addr.arpa";
            };
          };
          router-ddns = {
            enable = primary;
          }
          // lib.optionalAttrs primary {
            cloudflare = {
              zoneName = fleet.domain;
              labels = legacy.hosts.router.ddnsServices;
              apiTokenFile = varPath "cloudflare-api-token";
            };
          };
          router-upnp = {
            enable = primary;
            externalInterface = wan.name;
            internalIPs = [ lan.name ];
          };
          router-mdns = {
            enable = primary;
            allowInterfaces = [
              lan.name
              management.name
            ];
          };
          router-tailscale = {
            enable = primary;
            trustedInterface = true;
            openFirewall = primary;
          }
          // lib.optionalAttrs primary {
            authKeyFile = varPath "tailscale-auth-key";
            advertiseExitNode = true;
            advertiseRoutes = [ lanCidr ];
          };
          router-ntp.enable = true;
          router-snmp = {
            enable = true;
            communityFile = varPath "snmp-community";
            allowedNetworks = [
              lanCidr
              managementCidr
            ];
            listenAddresses = [
              "127.0.0.1"
              (ip router.managementAddress)
            ]
            ++ lib.optional primary gateway;
          };
          router-firewall = {
            enable = true;
            allowSsh = true;
            hairpinNat.enable = true;
            flowtable.sipFriendly.enable = true;
            flowLogging.enable = true;
            trustedTcpPorts = [
              80
              443
              3000
              3002
              16000
              26000
            ];
            trustedUdpPorts = [
              69
              4011
            ];
            extraLanLocalRules = ''
              tcp dport 5201 accept comment "iperf3 from LAN"
            '';
          };
          router-optimizations = {
            enable = true;
            package = upstream.packages.${pkgs.stdenv.hostPlatform.system}.router-diag;
            conntrack-max = 262144;
            interfaces = {
              wan = {
                device = wan.name;
                role = "wan";
                label = "WAN";
                bandwidth = router.wanBandwidth;
              };
              lan = {
                device = lan.name;
                role = "lan";
                label = "LAN";
              };
              management = {
                device = management.name;
                role = "management";
                label = "Management";
              };
            };
          };
          router-homelab = {
            enable = true;
            sshTarget = "ssh ${config.networking.hostName}";
            listenAddress = "0.0.0.0";
            netdataAllowConnectionsFrom = "${lanCidr} ${managementCidr}";
          };
          router-observability.enable = true;
          # WHY: Pangolin/gerbil are the public tunnel edge and need WAN; on a
          # standby gerbil restart-looped waiting for Pangolin's local API and
          # hung switch-to-configuration (elitedesk's first role deploy).
          router-pangolin = {
            enable = primary;
            openFirewall = primary;
          };
          traefik.enable = lib.mkForce false;
          router-network-security = {
            enable = primary;
            interfaces = [ lan.name ];
            suricata = {
              enable = primary;
              evebox.enable = primary;
            };
          };
          router-technitium = {
            bootstrapPasswordSecretName = "technitium-admin-password";
            # WHY: local names live in the primary's runtime zone (Kea DDNS);
            # standbys hold TSIG-transferred copies so failover keeps them.
            zoneReplication = {
              tsigKeyFile = varPath "technitium-zone-transfer-tsig";
            }
            // (
              if primary then
                {
                  primary = {
                    zones = replicatedZones;
                    secondaries = map (host: ip host.router.lanAddress) (lib.attrValues standbyHosts);
                  };
                }
              else
                {
                  secondary = {
                    zones = replicatedZones;
                    primaryAddresses = [ gateway ];
                  };
                }
            );
          }
          // lib.optionalAttrs (!primary) {
            scopes = lib.mkForce { };
            dhcpReservations = lib.mkForce { };
            ntpServers = lib.mkForce [ ];
            forceBlockListUpdateOnActivation = lib.mkForce false;
          }
          // lib.optionalAttrs primary {
            rfc2136 = {
              enable = true;
              tsigKeyFile = varPath "kea-ddns-tsig-key";
              zones = [
                { name = fleet.domain; }
                { name = "10.10.in-addr.arpa"; }
              ];
            };
          };
          router-dns-service = {
            enable = true;
            provider = "technitium";
            fallbackNameservers =
              if primary then
                [
                  "1.1.1.1"
                  "8.8.8.8"
                ]
              else
                [ gateway ];
            searchDomains = [ fleet.domain ];
            technitium.apiKeySecretName = null;
          };
          fail2ban = {
            enable = true;
            maxretry = 5;
            # WHY: authentication failures must leave the recovery path reachable.
            ignoreIP = [
              "127.0.0.1/8"
              lanCidr
              managementCidr
            ];
          };
        };

        systemd.services.gerbil.serviceConfig.Upholds = lib.mkForce [ ];
        systemd.services.traefik.enable = false;

        router.monitoring = {
          grafanaDomain = "grafana.${fleet.domain}";
          grafanaDataDir = "/var/log/router/grafana";
          listenAddress = "0.0.0.0";
          prometheusStateDir = "router-prometheus";
          prometheusBindMountPath = "/var/log/router/prometheus";
          prometheusRetentionSize = "40GB";
        };
        systemd.tmpfiles.rules = [
          "d /var/log/router/prometheus 0750 prometheus prometheus -"
          "d /var/log/router/grafana 0750 grafana grafana -"
        ];
      };
  };

  perSystem = { pkgs, ... }: {
    checks.router-standby =
      assert lib.assertMsg (
        standbyHosts != { }
      ) "The standby check must cover a migrated standby router.";
      assert lib.all (
        name:
        lib.assertMsg (standbySafe name
          standbyHosts.${name}
        ) "${name}: standby WAN or an exclusive router service can activate, or zone replication is missing."
      ) (lib.attrNames standbyHosts);
      pkgs.runCommand "router-standby" { } "touch $out";
  };
}
