# Services only the inventory primary router runs, ported from unified's
# hosts/nixos/router (caddy.nix, configuration.nix, service-capability.nix
# and role.nix) when elitedesk became the permanent primary (nch-sny.22).
# INVARIANT: everything here is gated on routerRole.full; a standby or a
# promoted standby never serves public ingress or PXE.
{ inputs, fleet, gateway }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  enable = config.routerRole.full;
  domain = fleet.domain;
  hosts = fleet.hosts;
  lanCidr = fleet.networks.lan.cidr;
  fqdn = label: "${label}.${domain}";
  tokenFile = config.clan.core.vars.generators.router-cloudflare-api-token.files.value.path;
  iventoyHttpPort = config.services.iventoy.httpPort;

  # WHY: names only the LAN, the tailnet and loopback may reach.
  trusted = "remote_ip ${lanCidr} 100.64.0.0/10 fd7a:115c:a1e0::/48 127.0.0.1 ::1";
  restricted = upstream: ''
    @trusted ${trusted}
    handle @trusted {
      ${upstream}
    }
    respond "Access restricted to home LAN and Tailnet" 403
  '';
  # Authentik forward auth for LAN/tailnet clients; everyone else gets 403.
  authenticated = upstream: ''
    @trustedOutpost {
      ${trusted}
      path /outpost.goauthentik.io/*
    }
    @trustedApp {
      ${trusted}
      not path /outpost.goauthentik.io/*
    }
    handle @trustedOutpost {
      reverse_proxy ${hosts.authentik-host.addresses.ip}:9000
    }
    handle @trustedApp {
      forward_auth ${hosts.authentik-host.addresses.ip}:9000 {
        uri /outpost.goauthentik.io/auth/caddy
        copy_headers X-Authentik-Username X-Authentik-Groups X-Authentik-Email X-Authentik-Name X-Authentik-Uid X-Authentik-Jwt
      }
      reverse_proxy ${upstream}
    }
    handle {
      respond "Access restricted to home LAN and Tailnet" 403
    }
  '';
  insecureHttps = target: ''
    reverse_proxy https://${target} {
      transport http {
        tls_insecure_skip_verify
      }
    }
  '';

  virtualHosts = {
    "${domain}".extraConfig = "redir https://x.com/deepwatrcreatur permanent";
    "${fqdn "www"}".extraConfig = "redir https://x.com/deepwatrcreatur permanent";
    "${fqdn "dashboard"}".extraConfig = restricted "reverse_proxy 127.0.0.1:8888";
    "${fqdn "status"}".extraConfig = authenticated "${hosts.homeserver.addresses.ip}:8085";
    "${fqdn "homelab"}".extraConfig = authenticated "${hosts.homeserver.addresses.ip}:8082";
    "${fqdn "pangolin"}".extraConfig = "reverse_proxy 127.0.0.1:3002";
    "${fqdn "home-assistant"}".extraConfig = "reverse_proxy ${hosts.homeassistant.addresses.ip}:8123";
    "${fqdn "authentik"}".extraConfig = "reverse_proxy ${hosts.authentik-host.addresses.ip}:9000";
    "${fqdn "paperless"}".extraConfig = "reverse_proxy ${hosts.podman.addresses.ip}:18000";
    "${fqdn "nightscout"}".extraConfig = "reverse_proxy ${hosts.podman.addresses.ip}:11337";
    "${fqdn "netalertx"}".extraConfig = restricted "reverse_proxy ${hosts.podman.addresses.ip}:20211";
    "${fqdn "graylog"}".extraConfig = restricted "reverse_proxy ${hosts.podman.addresses.ip}:9000";
    "${fqdn "scrypted"}".extraConfig = ''
      reverse_proxy https://${hosts.scrypted-lxc.addresses.ip}:10443 {
        transport http {
          tls_insecure_skip_verify
        }
        header_up Host {host}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
      }
    '';
    "${fqdn "roundtable"}".extraConfig = "reverse_proxy ${hosts.vaglio.addresses.ip}:4000";
    "${fqdn "grafana"}".extraConfig = "reverse_proxy 127.0.0.1:3001";
    "${fqdn "technitium"}".extraConfig = restricted "reverse_proxy 127.0.0.1:5380";
    "${fqdn "netdata"}".extraConfig = restricted "reverse_proxy 127.0.0.1:19999";
    "${fqdn "prometheus"}".extraConfig = restricted "reverse_proxy 127.0.0.1:9090";
    "${fqdn "evebox"}".extraConfig = restricted "reverse_proxy 127.0.0.1:5636";
    "${fqdn "synology"}".extraConfig = restricted (insecureHttps "${hosts.synology-dsm.addresses.ip}:5001");
  };

  # WHY: ACME DNS-01 needs Technitium (local resolver) and the Cloudflare API
  # reachable; continue after 45 s so a slow DNS start cannot block ingress.
  waitForDns = pkgs.writeShellScript "router-caddy-wait-for-dns" ''
    for _ in $(seq 1 45); do
      if ${lib.getExe pkgs.curl} --max-time 2 -fsS http://127.0.0.1:5380/api/dns/status >/dev/null 2>&1 \
        && timeout 2s ${pkgs.glibc.bin}/bin/getent ahostsv4 api.cloudflare.com >/dev/null 2>&1; then
        exit 0
      fi
      sleep 1
    done
    echo "router-caddy: DNS was not ready after 45 seconds; continuing" >&2
  '';
  writeCaddyEnv = pkgs.writeShellScript "router-caddy-env" ''
    set -euo pipefail
    install -d -m 0750 -o caddy -g caddy /run/caddy
    token="$(tr -d '\n' < ${tokenFile})"
    test -n "$token"
    umask 077
    printf 'CLOUDFLARE_API_TOKEN=%s\n' "$token" > /run/caddy/caddy.env
    chown caddy:caddy /run/caddy/caddy.env
  '';
in
{
  imports = [
    (inputs.unified + "/modules/nixos/services/iventoy.nix")
  ];

  options.routerRole.full = lib.mkOption {
    type = lib.types.bool;
    default = false;
    internal = true;
    description = "Set by router-role on the inventory primary router.";
  };

  config = lib.mkIf enable {
    services.caddy = {
      enable = true;
      email = "deepwatrcreatur@gmail.com";
      package = pkgs.caddy.withPlugins {
        plugins = [ "github.com/caddy-dns/cloudflare@v0.2.3" ];
        hash = "sha256-weP1HzwGvPlLqiAViJus1GN74bps3bI179gomTCb6N4=";
      };
      globalConfig = ''
        email deepwatrcreatur@gmail.com
        acme_dns cloudflare {$CLOUDFLARE_API_TOKEN}
      '';
      virtualHosts =
        lib.mapAttrs (_: vhost: {
          extraConfig = ''
            tls {
              dns cloudflare {$CLOUDFLARE_API_TOKEN}
              resolvers 1.1.1.1 8.8.8.8
            }
            ${vhost.extraConfig}
          '';
        }) virtualHosts
        // {
          # PXE images over plain HTTP on the gateway address.
          "http://${gateway}".extraConfig = ''
            root * /srv/pxe
            file_server browse
          '';
        };
    };
    systemd.services.caddy = {
      after = [ "network-online.target" "technitium-dns-server.service" ];
      wants = [ "network-online.target" "technitium-dns-server.service" ];
      serviceConfig = {
        # GOTCHA: systemd reads EnvironmentFile when it starts each command,
        # so the file ExecStartPre writes is there for ExecStart.
        EnvironmentFile = lib.mkForce [ "-/run/caddy/caddy.env" ];
        ExecStartPre = lib.mkBefore [
          "+${writeCaddyEnv}"
          "${waitForDns}"
        ];
      };
    };

    # PXE: iVentoy in external mode behind Kea's boot options.
    services.iventoy = {
      enable = true;
      isoDir = "/srv/pxe/images";
      openFirewall = false;
    };
    services.router-kea.dhcp4.pxe = {
      enable = true;
      bootServerAddress = gateway;
      bootServerName = fqdn "router";
      # iVentoy external mode expects this loader name and serves the real
      # BIOS/UEFI path after inspecting the request.
      bootFilename = "iventoy_loader_${toString iventoyHttpPort}";
    };
    systemd.services.setup-router-pxe-storage = {
      description = "Prepare router PXE storage directories";
      after = [ "srv-pxe.mount" ];
      wants = [ "srv-pxe.mount" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        install -d -m 0755 /srv/pxe /srv/pxe/images /srv/pxe/ipxe
      '';
    };

    # Static host records (lib/hosts.nix) next to Kea's DDNS names.
    services.router.dnsZones =
      let
        zones = (import (inputs.unified + "/hosts/nixos/router/dns-zone.nix")).zones;
      in
      lib.mapAttrs (_: zone: {
        nameserverIP = gateway;
        allowDynamicUpdates = true;
        aliases = zone.aliases or { };
        staticHosts = lib.mapAttrs (_: host: {
          ipAddress = host.ipv4;
          aliases = host.aliases or [ ];
        }) zone.hosts;
        reverseZone = {
          enable = true;
          networks = [ lanCidr ];
        };
      }) zones;

    services.router-dns-service = {
      dnssec.enableValidation = true;
      ntpServers = [ gateway ];
      technitium = {
        blockListPresets = [
          "hagezi-normal"
          "hagezi-nrd-14d"
        ];
        blockListUpdateIntervalHours = 24;
      };
    };
    services.router-ntp.lanSubnets = [ lanCidr ];

    # Plex remote access: WAN TCP 32400 to the Synology DSM VM. Logging is
    # rate limited in its own rule so the limit never applies to traffic.
    services.router-firewall.extraWanInRules = ''
      ip daddr ${hosts.synology-dsm.addresses.ip} tcp dport 32400 limit rate 30/minute log prefix "PLEX-FWD: "
      ip daddr ${hosts.synology-dsm.addresses.ip} tcp dport 32400 counter accept comment "Plex Media Server forward from WAN"
    '';
    networking.nftables.tables.plex-remote-access = {
      family = "ip";
      content = ''
        chain prerouting {
          type nat hook prerouting priority dstnat; policy accept;
          iifname "${config.services.router-networking.wan.device}" tcp dport 32400 limit rate 30/minute log prefix "PLEX-DNAT: "
          iifname "${config.services.router-networking.wan.device}" tcp dport 32400 counter dnat to ${hosts.synology-dsm.addresses.ip}:32400 comment "Plex Media Server DNAT"
        }
      '';
    };

    services.iperf3 = {
      enable = true;
      bind = gateway;
    };

    router.monitoring.blackbox = {
      enable = true;
      targets = [
        { name = "AP25 Ruqayya"; target = "10.10.18.20"; }
        { name = "AP22 Nosheen Living"; target = "10.10.18.21"; }
        { name = "AP11 Nosheen Bedroom"; target = "10.10.18.22"; }
        { name = "Core Switch"; target = hosts.sw-main.addresses.ip; }
        { name = "WAN Cloudflare DNS"; target = "1.1.1.1"; }
        { name = "WAN Google DNS"; target = "8.8.8.8"; }
      ];
    };

    # Interface counters of the core switch (sw-main), polled over SNMP v2c
    # with its default read-only community.
    # TODO: move the community to a clan var once it is changed on the switch.
    services.prometheus.exporters.snmp = {
      enable = true;
      listenAddress = "127.0.0.1";
      configurationPath = "${pkgs.prometheus-snmp-exporter.src}/snmp.yml";
      # GOTCHA: the check copies the file with builtins.path, which rejects a
      # store path; this is upstream's own generated config.
      enableConfigCheck = false;
    };
    services.prometheus.scrapeConfigs = [
      {
        job_name = "aruba-instant-on";
        static_configs = [ { targets = [ "10.10.11.69:9590" ]; } ];
      }
      {
        job_name = "snmp-switches";
        metrics_path = "/snmp";
        params = {
          module = [ "if_mib" ];
          auth = [ "public_v2" ];
        };
        static_configs = [
          {
            targets = [ hosts.sw-main.addresses.ip ];
            labels.switch = "sw-main";
          }
        ];
        relabel_configs = [
          { source_labels = [ "__address__" ]; target_label = "__param_target"; }
          { source_labels = [ "__param_target" ]; target_label = "instance"; }
          {
            target_label = "__address__";
            replacement = "127.0.0.1:${toString config.services.prometheus.exporters.snmp.port}";
          }
        ];
      }
    ];
  };
}
