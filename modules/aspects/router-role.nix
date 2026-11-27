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
  vrrpHosts = lib.filterAttrs (
    _: host: host.migrated && !host.archived && host.router != null && host.router.mode == "vrrp"
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
        router = config.routerRole.node;
        # WHY: `promoted` is the manual-failover specialisation of a standby
        # (docs/router-failover.md). It owns the LAN services, but not those
        # whose credentials only an inventory primary holds (`full`).
        promoted = config.routerRole.promoted;
        # WHY: a `vrrp` member holds every credential, because keepalived can
        # make it MASTER without a redeploy (docs/router-vrrp.md).
        vrrp = router.mode == "vrrp";
        full = router.mode == "primary" || vrrp;
        primary = full || promoted;
        # INVARIANT: only a non-VRRP primary holds the gateway address itself;
        # under VRRP keepalived adds it to the MASTER.
        staticGateway = primary && !vrrp;
        vrrpPeers = lib.filterAttrs (name: _: name != config.networking.hostName) config.routerRole.vrrpMembers;
        # The highest-priority member is Kea's HA primary and the only one
        # with Pangolin's state.
        preferred = vrrp && lib.all (peer: peer.vrrpPriority < router.vrrpPriority) (lib.attrValues vrrpPeers);
        # WHY: Kea HA and zone HA need a peer; a lone member (the first step
        # of the rollout, docs/router-vrrp.md#rollout) keeps its zones Primary
        # and runs Kea alone.
        paired = vrrp && vrrpPeers != { };
        peerLanIps = map (peer: ip peer.lanAddress) (lib.attrValues vrrpPeers);
        inherit (router.devices) wan lan management;
        topology = fleet.networks;
        lanCidr = topology.lan.cidr;
        managementCidr = topology.management.cidr;
        gateway = fleet.gateway;
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
            (import ../_nixos/router-primary-edge.nix { inherit inputs fleet; inherit (fleet) gateway; })
            {
              options.routerRole = {
                promoted = lib.mkOption {
                  type = lib.types.bool;
                  default = false;
                  internal = true;
                  description = "Set by the `primary` specialisation of a standby router.";
                };
                # WHY: options, not direct inventory reads, so checks can
                # evaluate a host in another mode with extendModules.
                node = lib.mkOption {
                  type = lib.types.attrs;
                  default = fleet.hosts.${config.networking.hostName}.router;
                  internal = true;
                  description = "This host's inventory `router` attributes.";
                };
                vrrpMembers = lib.mkOption {
                  type = lib.types.attrsOf lib.types.attrs;
                  default = lib.mapAttrs (_: host: host.router) vrrpHosts;
                  internal = true;
                  description = "Inventory `router` attributes of every `vrrp` member, by host name.";
                };
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
        routerRole.full = full;

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
            (lib.mkIf (primary && router.takeover != null) {
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
            # WHY: a BACKUP's WAN is down; it reaches the internet (Tailscale,
            # updates) through the MASTER. On the MASTER the VIP is local and
            # the WAN's DHCP route (metric 1024) wins.
            routes = lib.optionals vrrp [
              {
                Gateway = gateway;
                Metric = 2000;
              }
            ];
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
              # GOTCHA: a VRRP BACKUP's WAN is down; requiring it would block boot.
              requiredForOnline = if staticGateway then "routable" else "no";
            };
            routedInterfaces = {
              lan = {
                device = lan.name;
                # GOTCHA: a primary holds only the gateway. Keeping its own address
                # too would leave it the kernel's primary after a live switch,
                # and Kea would hand out that address as its server identifier.
                ipv4Address =
                  if staticGateway then "${gateway}/${lib.last (lib.splitString "/" lanCidr)}" else router.lanAddress;
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
          # WHY: only `vrrp` members run keepalived; a standby is a manual
          # spare and a `primary` holds the gateway statically.
          router-ha = {
            enable = vrrp;
            priority = router.vrrpPriority;
            # WHY: a recovered elitedesk waits before taking the role back
            # (docs/router-election.md#33-preemption-and-stability).
            preemptDelay = router.vrrpPreemptDelay;
          }
          // lib.optionalAttrs vrrp {
            # With preemptDelay every member starts BACKUP; priority elects.
            role = if preferred then "master" else "backup";
            virtualIp = "${gateway}/${lib.last (lib.splitString "/" lanCidr)}";
            vrrpInterface = lan.name;
            vrrpPasswordFile = varPath "vrrp-password";
            routerAdvertisements.mode = "vrrp-owner";
            # WHY: hold keepalived until the peer is audible, so a switch
            # port still learning after boot cannot bypass preemptDelay
            # (docs/router-vrrp.md, nch-sny.36.11). Alone there is no one to
            # hear, and waiting would only delay the gateway.
            peerWaitSec = if paired then 60 else 0;
            # WHY: switches on the LAN dropped VRRP multicast toward elitedesk,
            # which then never heard router and took over after every start
            # (docs/router-vrrp.md, nch-sny.36.11). Unicast to the peer's LAN
            # address does not depend on switch multicast handling; alone
            # there is nobody to send to.
            unicastPeers = peerLanIps;
            wan = {
              enable = true;
              interface = wan.name;
              # WHY: the modem binds the lease to this MAC; the DUID-EN and
              # IAID set on the WAN network above win over the link-layer
              # DUID router-ha would derive (upstream
              # router-ha-wan-own-dhcp-identity-wins-eval).
              clonedMac = router.takeover.wanMac;
              # WHY: a MASTER whose WAN is dead hands over to the peer. Alone
              # there is no one to hand over to, and the LAN would lose its
              # gateway and DNS for the whole outage.
              healthCheck.enable = paired;
            };
            # WHY: docs/router-vrrp.md#ownership; boot is disabled below.
            singleActiveUnits = [
              "avahi-daemon.socket"
              "avahi-daemon.service"
            ]
            ++ lib.optionals preferred [
              "pangolin.service"
              "gerbil.service"
            ];
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
                    ip-address = entry.addresses.ip;
                    hostname = name;
                  })
                  (
                    lib.filterAttrs (
                      _: entry: (entry.dhcpReservation or null) != null && (entry.addresses.ip or null) != null
                    ) fleet.hosts
                  );
            }
            // lib.optionalAttrs paired {
              # WHY: hot-standby: the preferred member answers every client,
              # the other only once it stops responding (upstream #185; ISC's
              # preferred mode). Kea HA runs regardless of VRRP state.
              ha = {
                enable = true;
                mode = "hot-standby";
                thisServerName = config.networking.hostName;
                peerName = lib.head (lib.attrNames vrrpPeers);
                role = if preferred then "primary" else "secondary";
                localAddress = ip router.lanAddress;
                peerAddress = lib.head peerLanIps;
              };
            };
            ddns = lib.mkIf full (
              {
                enable = true;
                tsigKeyFile = varPath "kea-ddns-tsig-key";
                tsigKeyName = "kea-ddns";
                forwardZone = fleet.domain;
                reverseZone = "10.10.in-addr.arpa";
              }
              // lib.optionalAttrs vrrp {
                # WHY: with Kea HA both servers allocate, so D2 runs on both
                # and sends updates to the VIP, where the zone primary lives.
                # A lone member runs D2 only while MASTER.
                ha.mode = if paired then "follow-vip" else "single-active";
              }
            );
          };
          router-ddns = {
            enable = full;
            ha.singleActiveOwner = vrrp;
          }
          // lib.optionalAttrs full {
            cloudflare = {
              zoneName = fleet.domain;
              labels = fleet.hosts.router.router.ddnsServices;
              apiTokenFile = varPath "cloudflare-api-token";
            };
          };
          router-upnp = {
            enable = primary;
            externalInterface = wan.name;
            internalIPs = [ lan.name ];
            ha.singleActiveOwner = vrrp;
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
          # WHY: Pangolin's database and gerbil's WireGuard key live on one
          # node, so under VRRP only the preferred member runs them, and only
          # while MASTER (docs/router-vrrp.md#ownership).
          router-pangolin = {
            enable = full && (!vrrp || preferred);
            openFirewall = full && (!vrrp || preferred);
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
              # WHY: with no standby there is nothing to replicate to; the
              # zones stay Primary from the cutover (docs/router-failover.md).
              # WHY: in a VRRP pair every member holds the zones as Secondary
              # of the VIP and the MASTER promotes its copy (upstream
              # zoneReplication.ha); peers are the other members' own addresses.
              if paired then
                {
                  secondary = {
                    zones = replicatedZones;
                    primaryAddresses = [ gateway ];
                  };
                  ha = {
                    enable = true;
                    peers = peerLanIps;
                  };
                }
              else if full then
                lib.optionalAttrs (standbyHosts != { }) {
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
              # WHY: paired, D2 sends to the VIP from the node's own LAN
              # address; Technitium checks this ACL before TSIG.
              zones = map (name: { inherit name; } // lib.optionalAttrs paired {
                updateNetworkACL = [ "127.0.0.1" gateway (ip router.lanAddress) ] ++ peerLanIps;
              }) [ fleet.domain "10.10.in-addr.arpa" ];
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
            # WHY: D2 sends updates to the VIP, and a wildcard listener would
            # answer from the node's own address (upstream router-kea
            # assertion). Binding the VIP on a BACKUP relies on router-ha's
            # ip_nonlocal_bind. IPv6 clients keep the wildcard.
            serviceListenAddresses = lib.optionals vrrp [
              "127.0.0.1"
              gateway
              (ip router.lanAddress)
              (ip router.managementAddress)
              "::"
            ];
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

        # GOTCHA: define these only where Pangolin runs. Even a mkIf-false
        # attribute under systemd.services.<unit> creates a bare unit file,
        # and switching a member without Pangolin then failed with "bad unit
        # file setting".
        systemd.services.gerbil = lib.mkIf config.services.router-pangolin.enable {
          serviceConfig.Upholds = lib.mkForce [ ];
          wantedBy = lib.mkIf vrrp (lib.mkForce [ ]);
        };
        systemd.services.pangolin = lib.mkIf (config.services.router-pangolin.enable && vrrp) {
          wantedBy = lib.mkForce [ ];
        };

        # SECURITY: the abort fence (docs/router-vrrp.md#abort). A fenced
        # member must not elect itself after a reboot next to a static
        # primary that sends no VRRP; keepalived stays off until the marker
        # is removed.
        systemd.services.keepalived.unitConfig.ConditionPathExists = lib.mkIf vrrp "!/var/lib/router-failover/demoted";

        # WHY: units without an upstream ownership option run on the VRRP
        # MASTER only: Pangolin needs the WAN and its state is on the
        # preferred member; two Avahi reflectors on one LAN would reflect
        # each other's traffic.
        # GOTCHA: router-ha starts and stops these (singleActiveUnits, in
        # services.router-ha above) but leaves boot to us.
        systemd.services.avahi-daemon.wantedBy = lib.mkIf vrrp (lib.mkForce [ ]);
        systemd.sockets.avahi-daemon.wantedBy = lib.mkIf vrrp (lib.mkForce [ ]);
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

    # WHY: Clan vars are the router credential source; evaluating the router
    # role must not depend on the legacy agenix module.
    checks.router-secret-files =
      let
        routers = lib.filterAttrs (_: host: host.migrated && !host.archived && host.router != null) fleet.hosts;
        ok = name:
          let
            cfg = config.flake.nixosConfigurations.${name}.config;
            expected = cfg.clan.core.vars.generators.router-technitium-admin-password.files.value.path;
          in
          cfg.services.router-technitium.bootstrapPasswordFile == expected
          && !(cfg ? age);
      in
      assert lib.all (name: lib.assertMsg (ok name) "${name}: router secret file paths or agenix independence are incorrect.") (lib.attrNames routers);
      pkgs.runCommand "router-secret-files" { } "touch $out";

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
          && sp.services.router-networking.routedInterfaces.lan.ipv4Address == "${fleet.gateway}/16"
          && lanNet.address == [ "${fleet.gateway}/16" ]
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
      assert lib.all (name: lib.assertMsg (ok name) "${name}: the primary specialisation does not take over the gateway, WAN identity or LAN services.") (lib.attrNames takers);
      pkgs.runCommand "router-promotion" { } "touch $out";

    # WHY: no migrated standby exists after elitedesk became the primary;
    # these checks cover the next one when it is added.
    # WHY: the inventory primary holds the gateway alone and keeps router's WAN
    # identity, so the move off router kept the IPv4 lease and the /56; it
    # alone runs public ingress, PXE and DDNS (nch-sny.22).
    checks.router-primary =
      let
        primaries = lib.filterAttrs (
          _: host: host.migrated && !host.archived && host.router != null && host.router.mode == "primary"
        ) fleet.hosts;
        ok =
          name:
          let
            host = primaries.${name};
            cfg = config.flake.nixosConfigurations.${name}.config;
            net = cfg.systemd.network.networks;
            wan = net."10-router-wan-primary";
            takeover = host.router.takeover;
          in
          cfg.routerRole.full
          && cfg.specialisation == { }
          && net."20-router-lan".address == [ "${fleet.gateway}/16" ]
          && (wan.linkConfig.ActivationPolicy or "up") != "always-down"
          && (takeover == null || (wan.linkConfig.MACAddress == takeover.wanMac && wan.dhcpV6Config.IAID == takeover.dhcpIaid))
          && cfg.services.kea.dhcp4.enable
          && cfg.services.kea.dhcp-ddns.enable
          && cfg.services.caddy.enable
          && cfg.services.iventoy.enable
          && cfg.services.inadyn.enable
          && cfg.services.tailscale.enable
          && cfg.services.router.dnsZones != { }
          && cfg.networking.nftables.tables ? plex-remote-access;
      in
      assert lib.all (name: lib.assertMsg (ok name) "${name}: the primary router does not hold the gateway, WAN identity or primary-only services.") (lib.attrNames primaries);
      pkgs.runCommand "router-primary" { } "touch $out";

    # WHY: a VRRP member must hand the gateway, the WAN identity and the
    # single-owner services to keepalived, keep the modem's DUID, and pair
    # Kea and the zones only when a peer exists (docs/router-vrrp.md). The
    # reference host is also evaluated as a member in three layouts, so the
    # mode stays checked before any inventory host uses it.
    checks.router-vrrp =
      let
        gateway = fleet.gateway;
        okVrrp =
          label: cfg:
          let
            node = cfg.routerRole.node;
            peers = lib.filterAttrs (name: _: name != cfg.networking.hostName) cfg.routerRole.vrrpMembers;
            preferred = lib.all (peer: peer.vrrpPriority < node.vrrpPriority) (lib.attrValues peers);
            paired = peers != { };
            ha = cfg.services.router-ha;
            net = cfg.systemd.network.networks;
            wanNet = net."10-router-wan-primary";
            lanNet = net."20-router-lan";
            kea = cfg.services.router-kea;
            zones = cfg.services.router-technitium.zoneReplication.ha;
            owned = unit: lib.elem unit ha.singleActiveUnits;
            checks = {
              "keepalived holds the VIP" = ha.enable && ha.virtualIp == "${gateway}/16" && ha.vrrpInterface == node.devices.lan.name;
              "the preferred member starts as master" = ha.role == (if preferred then "master" else "backup");
              "WAN follows VRRP with the modem's MAC" = ha.wan.enable && ha.wan.clonedMac == node.takeover.wanMac;
              "WAN health check yields iff paired" = ha.wan.healthCheck.enable == paired;
              "keepalived waits for the peer iff paired" = (ha.peerWaitSec > 0) == paired;
              "VRRP adverts go unicast to each peer's LAN address" =
                ha.unicastPeers == map (peer: builtins.head (lib.splitString "/" peer.lanAddress)) (lib.attrValues peers);
              "WAN keeps the modem's DUID-EN and IAID" =
                wanNet.linkConfig.ActivationPolicy == "manual"
                && wanNet.dhcpV4Config.DUIDRawData == node.takeover.dhcpDuidRawData
                && wanNet.dhcpV6Config.IAID == node.takeover.dhcpIaid;
              "WAN is not required for boot" = (wanNet.linkConfig.RequiredForOnline or "no") == "no";
              "LAN holds only the node address" = lanNet.address == [ node.lanAddress ];
              "LAN fallback route via the VIP" = lib.elem { Gateway = gateway; Metric = 2000; } lanNet.routes;
              "no manual-failover specialisation" = cfg.specialisation == { };
              "DDNS, UPnP and Avahi run on the MASTER only" =
                lib.all owned [ "inadyn.timer" "miniupnpd.service" "avahi-daemon.service" "avahi-daemon.socket" ];
              "Kea HA hot-standby iff paired" =
                kea.dhcp4.ha.enable == paired
                && (!paired || (kea.dhcp4.ha.mode == "hot-standby" && kea.dhcp4.ha.role == (if preferred then "primary" else "secondary")));
              "D2 follows the VIP iff paired" = kea.ddns.ha.mode == (if paired then "follow-vip" else "single-active");
              "peers may send DNS updates iff paired" =
                lib.all (zone:
                  let acl = zone.updateNetworkACL; in
                  if paired then lib.elem (builtins.head (lib.splitString "/" node.lanAddress)) acl && lib.length acl > 3 else acl == [ "127.0.0.1" ]
                ) cfg.services.router-technitium.rfc2136.zones;
              "zones follow VRRP iff paired" = zones.enable == paired && (!paired || zones.peers != [ ]);
              "Pangolin only on the preferred member, while MASTER" =
                if preferred then owned "pangolin.service" && owned "gerbil.service" && cfg.systemd.services.pangolin.wantedBy == [ ]
                else !cfg.services.router-pangolin.enable && !(cfg.systemd.services ? pangolin) && !(cfg.systemd.services ? gerbil);
              "keepalived fenced by the demoted marker" =
                (cfg.systemd.services.keepalived.unitConfig.ConditionPathExists or null) == "!/var/lib/router-failover/demoted";
              "VRRP password var declared" = cfg.clan.core.vars.generators ? router-vrrp-password;
            };
            failed = lib.attrNames (lib.filterAttrs (_: v: !v) checks);
          in
          lib.assertMsg (failed == [ ]) "${label}: ${lib.concatStringsSep "; " failed}";

        asMember =
          name: priorities:
          let
            base = config.flake.nixosConfigurations.${name};
            node = base.config.routerRole.node // { mode = "vrrp"; };
          in
          (base.extendModules {
            modules = [
              {
                routerRole.node = node;
                routerRole.vrrpMembers =
                  { ${name} = node; }
                  // lib.mapAttrs (_: priority: node // { lanAddress = "10.10.10.2/16"; vrrpPriority = priority; }) priorities;
              }
            ];
          }).config;
        reference = "elitedesk";
        variants = {
          "${reference} as preferred member" = asMember reference { peer = 100; };
          "${reference} as backup member" = asMember reference { peer = 120; };
          "${reference} as lone member" = asMember reference { };
        }
        // lib.mapAttrs' (name: _: lib.nameValuePair name config.flake.nixosConfigurations.${name}.config) vrrpHosts;
      in
      assert lib.all (label: okVrrp label variants.${label}) (lib.attrNames variants);
      pkgs.runCommand "router-vrrp" { } "touch $out";

    checks.router-standby =
      assert lib.all (
        name:
        lib.assertMsg (standbySafe name
          standbyHosts.${name}
        ) "${name}: standby WAN or an exclusive router service can activate, or zone replication is missing."
      ) (lib.attrNames standbyHosts);
      pkgs.runCommand "router-standby" { } "touch $out";
  };
}
