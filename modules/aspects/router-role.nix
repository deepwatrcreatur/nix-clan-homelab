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
    # INVARIANT: a standby must hold both replicated zones to answer local names.
    # INVARIANT: standbys take part in VRRP-driven zone ownership.
    && services.router-technitium.zoneReplication.ha.enable
    && lib.elem "technitium-zone-ha-owner.service" services.router-ha.singleActiveUnits
    && lib.all (zone: lib.elem zone (map (z: z.name) services.router-technitium.zoneReplication.secondary.zones)) [
      fleet.domain
      "10.10.in-addr.arpa"
    ]
    && lib.all (
      network:
      !(network.networkConfig.IPv6SendRA or false)
      && !(network.networkConfig.DHCPPrefixDelegation or false)
      && !(network.networkConfig.DHCPServer or false)
    ) (lib.attrValues cfg.systemd.network.networks);
  /**
    Prometheus rule groups for router NICs: carrier loss, flapping and a NIC
    that vanished from the kernel. Exact device matchers, one rule per device.
  */
  nicRules = devices: {
    groups = [
      {
        name = "router-nics";
        rules = lib.concatMap (device: [
          {
            alert = "RouterNicCarrierLost";
            expr = ''node_network_carrier{device="${device}"} == 0'';
            for = "1m";
            labels = {
              severity = "critical";
              inherit device;
            };
            annotations.summary = "${device} on {{ $labels.instance }} has no carrier";
          }
          {
            # GOTCHA: a counter; changes() would count several flaps between
            # scrapes as one.
            alert = "RouterNicFlapping";
            expr = ''increase(node_network_carrier_changes_total{device="${device}"}[1h]) > 2'';
            labels = {
              severity = "warning";
              inherit device;
            };
            # increase() extrapolates, so the value is approximate.
            annotations.summary = "${device} carrier is flapping (about {{ $value | printf \"%.0f\" }} changes in an hour)";
          }
          {
            alert = "RouterNicMissing";
            expr = ''absent(node_network_info{device="${device}"})'';
            for = "1m";
            labels = {
              severity = "critical";
              inherit device;
            };
            annotations.summary = "${device} is gone from the kernel";
          }
        ]) devices;
      }
    ];
  };
in
{
  den.aspects.router-role = {
    includes = [ den.aspects.router-secrets ];
    nixos =
      { config, pkgs, ... }:
      let
        host = fleet.hosts.${config.networking.hostName};
        router = host.router;
        # WHY: `promoted` is the manual-failover specialisation of a standby
        # (docs/router-failover.md). It owns the LAN services, but not those
        # whose credentials only an inventory primary holds (`full`).
        promoted = config.routerRole.promoted;
        full = router.mode == "primary";
        primary = full || promoted;
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
            router-alerting
          ])
          ++ [
            ../_nixos/router-snmp.nix
            {
              options.routerRole.promoted = lib.mkOption {
                type = lib.types.bool;
                default = false;
                internal = true;
                description = "Set by the `primary` specialisation of a standby router.";
              };
            }
          ];

        # WHY: manual failover until VRRP runs (docs/router-failover.md). The
        # standby carries the primary role as a specialisation, activated with
        # `switch-to-configuration test`, so a reboot returns it to standby.
        # INVARIANT: not inside the specialisation itself, or it would nest.
        specialisation = lib.mkIf (!full && !promoted && router.takeover != null) {
          primary.configuration = {
            system.nixos.tags = [ "primary" ];
            routerRole.promoted = true;
          };
        };

        # WHY: drives the Technitium zone-HA owner without keepalived: master
        # promotes the replicated zones, backup hands them back.
        systemd.services.technitium-zone-ha-owner.wantedBy = lib.mkIf promoted [ "multi-user.target" ];

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
          "10-router-wan-primary" = lib.mkMerge [
            { linkConfig.ActivationPolicy = lib.mkIf (!primary) "always-down"; }
            # WHY: the modem binds its single lease and the /56 to the old
            # router's MAC, DHCP client ID and DUID/IAID; present all of them.
            (lib.mkIf (promoted && router.takeover != null) {
              linkConfig.MACAddress = router.takeover.wanMac;
              dhcpV4Config = {
                ClientIdentifier = "duid";
                DUIDType = "vendor";
                DUIDRawData = router.takeover.dhcpDuidRawData;
                IAID = router.takeover.dhcpIaid;
              };
              dhcpV6Config = {
                DUIDType = "vendor";
                DUIDRawData = router.takeover.dhcpDuidRawData;
                IAID = router.takeover.dhcpIaid;
              };
            })
          ];
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
                # GOTCHA: promoted holds only the gateway. Keeping its own address
                # too would leave it the kernel's primary after a live switch,
                # and Kea would hand out that address as its server identifier.
                ipv4Address =
                  if promoted then "${gateway}/${lib.last (lib.splitString "/" lanCidr)}" else router.lanAddress;
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
            ddns = lib.mkIf full {
              enable = true;
              tsigKeyFile = varPath "kea-ddns-tsig-key";
              tsigKeyName = "kea-ddns";
              forwardZone = fleet.domain;
              reverseZone = "10.10.in-addr.arpa";
            };
          };
          router-ddns = {
            enable = full;
          }
          // lib.optionalAttrs full {
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
            enable = full;
            trustedInterface = true;
            openFirewall = full;
          }
          // lib.optionalAttrs full {
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
          # WHY: alerts reach the operator by phone (ntfy); the healthchecks
          # watchdog reports a router that is down or cut off.
          router-alerting = {
            enable = true;
            ntfy = {
              enable = true;
              urlFile = varPath "ntfy-url";
            };
            watchdog.pingUrlFile = varPath "healthchecks-ping-url";
            # Kea runs only on the primary.
            newDhcpDevices.enable = primary;
          };
          # WHY: Pangolin/gerbil are the public tunnel edge and need WAN; on a
          # standby gerbil restart-looped waiting for Pangolin's local API and
          # hung switch-to-configuration (elitedesk's first role deploy).
          router-pangolin = {
            enable = full;
            openFirewall = full;
          };
          traefik.enable = lib.mkForce false;
          router-network-security = {
            enable = full;
            interfaces = [ lan.name ];
            suricata = {
              enable = full;
              evebox.enable = full;
            };
          };
          router-technitium = {
            bootstrapPasswordFile = varPath "technitium-admin-password";
            # WHY: local names live in the primary's runtime zone (Kea DDNS);
            # standbys hold TSIG-transferred copies so failover keeps them.
            zoneReplication = {
              tsigKeyFile = varPath "technitium-zone-transfer-tsig";
            }
            // (
              # WHY: a promoted standby keeps its secondary copies; the
              # zone-HA owner promotes them while the role file says master.
              if full then
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
                    # The VRRP virtual IP; today router holds it statically.
                    primaryAddresses = [ gateway ];
                  };
                  # WHY: the zones follow VRRP: the MASTER promotes its copy so
                  # DDNS keeps working after a takeover (nch-sny.30).
                  ha = {
                    enable = true;
                    # TODO(nch-sny.30): router's own address once it moves off
                    # the VIP; until VRRP, router answers only on the VIP.
                    peers = [ gateway ];
                  };
                }
            );
          }
          // lib.optionalAttrs (!full) {
            scopes = lib.mkForce { };
            dhcpReservations = lib.mkForce { };
            ntpServers = lib.mkForce [ ];
            forceBlockListUpdateOnActivation = lib.mkForce false;
          }
          // lib.optionalAttrs full {
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

        # WHY: docs/router-election.md#router-nic-alerts (nch-sny.31).
        # GOTCHA: services.prometheus.rules joins every entry into one file, and
        # a second JSON document there is silently ignored; use a rule file.
        services.prometheus.ruleFiles = [
          (pkgs.writeText "router-nics.rules.json" (builtins.toJSON (nicRules [
            lan.name
            management.name
          ])))
        ];

        router.monitoring = {
          alerting.enable = true;
          # NIC chip and SFP temperatures/optics for the "Router Hardware"
          # dashboard; docs/router-hardware.md.
          hardwareSensors.enable = true;
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
        ]
        # The role file read by the zone-HA owner (see technitium-zone-ha-owner).
        ++ lib.optionals (!full) [
          "d /run/router-ha 0755 root root -"
          "f+ /run/router-ha/role 0644 root root - ${if promoted then "master" else "backup"}"
        ];
      };
  };

  perSystem = { pkgs, ... }: {
    # WHY: every router must deliver alerts (ntfy) and feed its own
    # dead-man watchdog; docs/router-election.md#alert-delivery.
    checks.router-alerting =
      let
        routers = lib.filterAttrs (_: host: host.migrated && !host.archived && host.router != null) fleet.hosts;
        ok =
          name:
          let
            cfg = config.flake.nixosConfigurations.${name}.config;
            alerting = cfg.services.router-alerting;
            hc = cfg.clan.core.vars.generators.router-healthchecks-ping-url;
          in
          alerting.enable && alerting.ntfy.enable && alerting.watchdog.pingUrlFile != null && !hc.share;
      in
      assert lib.all (name: lib.assertMsg (ok name) "${name}: router alerting (ntfy + per-router watchdog) is not wired.") (lib.attrNames routers);
      pkgs.runCommand "router-alerting" { } "touch $out";

    # WHY: every router graphs its NIC chip and SFP temperatures
    # (docs/router-hardware.md): the collector runs on a timer and
    # node_exporter reads its textfile directory.
    checks.router-hw-sensors =
      let
        routers = lib.filterAttrs (_: host: host.migrated && !host.archived && host.router != null) fleet.hosts;
        ok =
          name:
          let
            cfg = config.flake.nixosConfigurations.${name}.config;
            node = cfg.services.prometheus.exporters.node;
          in
          cfg.router.monitoring.hardwareSensors.enable
          && cfg.systemd.timers ? router-hw-sensors
          && lib.elem "textfile" node.enabledCollectors
          && lib.elem "--collector.textfile.directory=/run/router-hw-sensors" node.extraFlags
          && cfg.environment.etc ? "grafana-dashboards/router-hardware.json";
      in
      assert lib.all (name: lib.assertMsg (ok name) "${name}: router hardware sensors (timer, textfile collector, dashboard) are not wired.") (lib.attrNames routers);
      pkgs.runCommand "router-hw-sensors" { } "touch $out";

    # WHY: proves the NIC alerts fire, including flap bursts between scrapes.
    checks.router-nic-alerts =
      let
        rules = pkgs.writeText "router-nics.rules.json" (builtins.toJSON (nicRules [ "lan0" "mgmt0" ]));
        tests = pkgs.writeText "router-nics.test.json" (builtins.toJSON {
          rule_files = [ "${rules}" ];
          evaluation_interval = "1m";
          tests = [
            {
              interval = "1m";
              input_series = [
                { series = ''node_network_carrier{device="lan0",instance="r"}''; values = "1 1 0 0 0 0"; }
                { series = ''node_network_carrier{device="mgmt0",instance="r"}''; values = "1x6"; }
                { series = ''node_network_info{device="lan0",instance="r"}''; values = "1x6"; }
                # Four transitions land between two scrapes.
                { series = ''node_network_carrier_changes_total{device="lan0",instance="r"}''; values = "10 10 14 14 14 14"; }
                { series = ''node_network_carrier_changes_total{device="mgmt0",instance="r"}''; values = "3x6"; }
              ];
              alert_rule_test = [
                {
                  eval_time = "5m";
                  alertname = "RouterNicCarrierLost";
                  exp_alerts = [
                    {
                      exp_labels = { severity = "critical"; device = "lan0"; instance = "r"; };
                      exp_annotations.summary = "lan0 on r has no carrier";
                    }
                  ];
                }
                {
                  eval_time = "5m";
                  alertname = "RouterNicFlapping";
                  exp_alerts = [
                    {
                      exp_labels = { severity = "warning"; device = "lan0"; instance = "r"; };
                      exp_annotations.summary = "lan0 carrier is flapping (about 4 changes in an hour)";
                    }
                  ];
                }
                {
                  eval_time = "5m";
                  alertname = "RouterNicMissing";
                  exp_alerts = [
                    {
                      exp_labels = { severity = "critical"; device = "mgmt0"; };
                      exp_annotations.summary = "mgmt0 is gone from the kernel";
                    }
                  ];
                }
              ];
            }
          ];
        });
      in
      pkgs.runCommand "router-nic-alerts" { nativeBuildInputs = [ pkgs.prometheus.cli ]; } ''
        promtool check rules ${rules}
        promtool test rules ${tests}
        touch $out
      '';

    # WHY: the manual-failover specialisation must take over the gateway and
    # the old router's WAN identity, and own the LAN services
    # (docs/router-failover.md).
    checks.router-promotion =
      let
        takers = lib.filterAttrs (_: host: host.router.takeover != null) standbyHosts;
        ok =
          name:
          let
            host = takers.${name};
            cfg = config.flake.nixosConfigurations.${name}.config;
            sp = cfg.specialisation.primary.configuration;
            net = sp.systemd.network.networks;
            wan = net."10-router-wan-primary";
            lanNet = net."20-router-lan";
          in
          sp.routerRole.promoted
          && sp.specialisation == { }
          && sp.services.router-networking.routedInterfaces.lan.ipv4Address == "${fleet.hosts.router.addresses.ip}/16"
          && lanNet.address == [ "${fleet.hosts.router.addresses.ip}/16" ]
          && (wan.linkConfig.ActivationPolicy or "up") != "always-down"
          && wan.linkConfig.MACAddress == host.router.takeover.wanMac
          && wan.dhcpV4Config.DUIDRawData == host.router.takeover.dhcpDuidRawData
          && wan.dhcpV6Config.IAID == host.router.takeover.dhcpIaid
          && sp.services.kea.dhcp4.enable
          && sp.services.miniupnpd.enable
          && lib.elem "multi-user.target" sp.systemd.services.technitium-zone-ha-owner.wantedBy
          && lib.elem "f+ /run/router-ha/role 0644 root root - master" sp.systemd.tmpfiles.rules
          && lib.elem "f+ /run/router-ha/role 0644 root root - backup" cfg.systemd.tmpfiles.rules
          # Credentials only an inventory primary holds stay off.
          && !sp.services.tailscale.enable
          && !sp.services.inadyn.enable;
      in
      assert lib.assertMsg (takers != { }) "The promotion check must cover a standby with a takeover identity.";
      assert lib.all (name: lib.assertMsg (ok name) "${name}: the primary specialisation does not take over the gateway, WAN identity or LAN services.") (lib.attrNames takers);
      pkgs.runCommand "router-promotion" { } "touch $out";

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
