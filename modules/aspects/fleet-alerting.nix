# Fleet alerting (nch-a9a.5): exporters on every migrated host, scraped by
# both routers, alerts delivered by the routers' Alertmanager (ntfy, the
# healthchecks watchdog). docs/decisions/0005-fleet-alerting.md
{
  config,
  den,
  lib,
  ...
}:
let
  fleet = config.homelab;
  ip = address: builtins.head (lib.splitString "/" address);
  live = lib.filterAttrs (_: host: host.migrated && !host.archived) fleet.hosts;
  routers = lib.filterAttrs (_: host: host.router != null) live;
  fleetHosts = lib.filterAttrs (_: host: host.router == null) live;
  # WHY: a router scrapes from its node address, or from the gateway address
  # while it is VRRP MASTER (both sit on the LAN interface).
  scraperAddresses = lib.unique (map (host: ip host.router.lanAddress) (lib.attrValues routers) ++ [ fleet.gateway ]);
  ports = {
    node = 9100;
    smartctl = 9633;
    nodeCert = 9141;
    alertmanagerCluster = 9094;
  };
  target = host: if host.addresses.ip != null then host.addresses.ip else host.fqdn;
  # WHY: desktops and laptops sleep or are switched off; no host-down alert.
  alwaysOn = host: !(lib.elem "desktop" host.roles);
  fleetTargets =
    port:
    lib.mapAttrsToList (name: host: {
      targets = [ "${target host}:${toString port}" ];
      labels = {
        # INVARIANT: alerts about a fleet host carry its name; the routers'
        # external `host` label applies only to series without one.
        host = name;
        always_on = lib.boolToString (alwaysOn host);
      };
    }) fleetHosts;

  pseudoFs = "tmpfs|ramfs|devtmpfs|overlay|squashfs|efivarfs|nsfs|autofs|fuse.*";
  days14 = toString (14 * 86400);
  /**
    Alert rules for every scraped host, routers included. Summaries leave out
    the host: router-alerting titles each notification "<alert> on <host>".
  */
  rules = {
    groups = [
      {
        name = "fleet";
        rules = [
          {
            alert = "HostDown";
            expr = ''up{job="fleet-node",always_on="true"} == 0'';
            for = "10m";
            labels.severity = "critical";
            annotations.summary = "not answering metrics scrapes for 10 minutes";
          }
          {
            alert = "SystemdUnitFailed";
            expr = ''node_systemd_unit_state{state="failed"} == 1'';
            for = "5m";
            labels.severity = "warning";
            annotations.summary = "{{ $labels.name }} has failed";
          }
          {
            alert = "FilesystemAlmostFull";
            expr = ''
              (1 - node_filesystem_avail_bytes{fstype!~"${pseudoFs}"} / node_filesystem_size_bytes{fstype!~"${pseudoFs}"}) > 0.85
              and node_filesystem_readonly{fstype!~"${pseudoFs}"} == 0'';
            for = "15m";
            labels.severity = "warning";
            annotations.summary = "{{ $labels.mountpoint }} is {{ $value | humanizePercentage }} full";
          }
          {
            alert = "DiskSmartFailed";
            expr = "smartctl_device_smart_status == 0";
            for = "5m";
            labels.severity = "critical";
            annotations.summary = "SMART health check failed on {{ $labels.device }}";
          }
          {
            alert = "DiskCriticalWarning";
            expr = "smartctl_device_critical_warning > 0";
            for = "5m";
            labels.severity = "critical";
            annotations.summary = "NVMe critical warning on {{ $labels.device }}";
          }
          {
            alert = "DiskMediaErrors";
            expr = "increase(smartctl_device_media_errors[1h]) > 0";
            labels.severity = "warning";
            annotations.summary = "new media errors on {{ $labels.device }}";
          }
          {
            alert = "TlsCertificateExpiring";
            expr = "ssl_certificate_expiry_seconds < ${days14}";
            for = "1h";
            labels.severity = "warning";
            annotations.summary = "{{ $labels.path }} expires in {{ $value | humanizeDuration }}";
          }
        ];
      }
    ];
  };
  rulesFile = pkgs: pkgs.writeText "fleet.rules.json" (builtins.toJSON rules);

  # Exporters on a fleet host; routers run node exporter through
  # nix-router-optimized's monitoring module instead.
  hostExporters =
    { config, lib, options, ... }:
    let
      # GOTCHA: routers run node exporter through nix-router-optimized; a
      # second collector list would repeat flags node_exporter rejects.
      isRouter = options ? routerRole;
      nft = config.networking.nftables.enable;
      allowFrom = port: {
        iptables = lib.concatMapStringsSep "\n" (
          source: "iptables -A nixos-fw -p tcp -s ${source} --dport ${toString port} -j nixos-fw-accept"
        ) scraperAddresses;
        nftables = "ip saddr { ${lib.concatStringsSep ", " scraperAddresses} } tcp dport ${toString port} accept";
      };
      exported = [ ports.node ] ++ lib.optional config.services.prometheus.exporters.smartctl.enable ports.smartctl;
    in
    lib.mkIf (!isRouter) {
      services.prometheus.exporters.node = {
        enable = true;
        enabledCollectors = [ "systemd" ];
      };
      services.prometheus.exporters.smartctl.enable = lib.mkDefault (!config.boot.isContainer);
      # SECURITY: only the routers may scrape (the exporters bind all
      # addresses). IPv4 iptables, not ip46tables: the sources are IPv4.
      networking.firewall = lib.mkIf config.networking.firewall.enable (
        if nft then
          { extraInputRules = lib.concatMapStringsSep "\n" (port: (allowFrom port).nftables) exported; }
        else
          { extraCommands = lib.concatMapStringsSep "\n" (port: (allowFrom port).iptables) exported; }
      );
    };

  # Router side: scrape the fleet, deduplicate across the pair, watch the
  # routers' own disks and Caddy certificates.
  routerAlerting =
    { config, lib, pkgs, ... }:
    let
      self = config.routerRole.node;
      peers = lib.filterAttrs (name: _: name != config.networking.hostName) config.routerRole.vrrpMembers;
      peerIps = map (peer: ip peer.lanAddress) (lib.attrValues peers);
      own = ip self.lanAddress;
      clusterPort = toString ports.alertmanagerCluster;
      localTarget = port: [
        {
          targets = [ "127.0.0.1:${toString port}" ];
          labels.host = config.networking.hostName;
        }
      ];
    in
    {
      services.prometheus.ruleFiles = [ (rulesFile pkgs) ];
      services.prometheus.scrapeConfigs = [
        {
          job_name = "fleet-node";
          static_configs = fleetTargets ports.node;
        }
        {
          job_name = "fleet-smartctl";
          static_configs = fleetTargets ports.smartctl;
        }
        {
          job_name = "smartctl";
          static_configs = localTarget ports.smartctl;
        }
        {
          job_name = "node-cert";
          static_configs = localTarget ports.nodeCert;
        }
      ];

      services.prometheus.exporters.smartctl = {
        enable = true;
        listenAddress = "127.0.0.1";
      };
      # Caddy obtains the routers' TLS certificates (DNS challenge, on both
      # routers); it renews them itself, this catches a renewal that stopped.
      services.prometheus.exporters.node-cert = {
        enable = true;
        listenAddress = "127.0.0.1";
        user = "caddy";
        paths = [ "${config.services.caddy.dataDir}/.local/share/caddy/certificates" ];
        includeGlobs = [ "*.crt" ];
      };

      # WHY: both routers scrape the fleet; clustered Alertmanagers send each
      # notification once while they can reach each other.
      services.router-alerting.clusterPeers = map (peerIp: "${peerIp}:${clusterPort}") peerIps;
      services.prometheus.alertmanager.extraFlags = lib.mkIf (peerIps != [ ]) [
        "--cluster.listen-address=${own}:${clusterPort}"
        "--cluster.advertise-address=${own}:${clusterPort}"
      ];
      services.router-firewall.extraLanLocalRules = lib.mkIf (peerIps != [ ]) ''
        ip saddr { ${lib.concatStringsSep ", " peerIps} } tcp dport ${clusterPort} accept comment "Alertmanager cluster"
        ip saddr { ${lib.concatStringsSep ", " peerIps} } udp dport ${clusterPort} accept comment "Alertmanager cluster"
      '';
    };
in
{
  den.aspects.fleet-metrics.nixos = hostExporters;
  den.aspects.fleet-alerting-router.nixos = routerAlerting;
  den.aspects.router-role.includes = [ den.aspects.fleet-alerting-router ];

  perSystem =
    { pkgs, ... }:
    let
      hostCfg = name: config.flake.nixosConfigurations.${name}.config;
      scrapedBy =
        cfg: job:
        lib.concatMap (sc: lib.concatMap (s: [ s.labels.host ]) sc.static_configs) (
          lib.filter (sc: sc.job_name == job) cfg.services.prometheus.scrapeConfigs
        );
    in
    {
      # WHY: every migrated host is scraped by every router, reachable only
      # by them, and the pair deduplicates (decision 0005).
      checks.fleet-metrics =
        let
          hostOk =
            name:
            let
              cfg = hostCfg name;
              node = cfg.services.prometheus.exporters.node;
            in
            node.enable
            && lib.elem "systemd" node.enabledCollectors
            && !node.openFirewall
            && lib.all (source: lib.hasInfix "-s ${source} --dport ${toString ports.node}" cfg.networking.firewall.extraCommands) scraperAddresses;
          routerOk =
            name:
            let
              cfg = hostCfg name;
              peers = lib.filterAttrs (n: _: n != name) cfg.routerRole.vrrpMembers;
            in
            lib.sort lib.lessThan (scrapedBy cfg "fleet-node") == lib.sort lib.lessThan (lib.attrNames fleetHosts)
            && lib.elem "${rulesFile pkgs}" (map toString cfg.services.prometheus.ruleFiles)
            && cfg.services.prometheus.exporters.smartctl.enable
            && cfg.services.prometheus.exporters.node-cert.enable
            && lib.length cfg.services.router-alerting.clusterPeers == lib.length (lib.attrNames peers)
            && (peers == { } || lib.hasInfix "dport ${toString ports.alertmanagerCluster}" cfg.services.router-firewall.extraLanLocalRules);
        in
        assert lib.all (n: lib.assertMsg (hostOk n) "${n}: fleet exporters or their firewall rules are missing.") (lib.attrNames fleetHosts);
        assert lib.all (n: lib.assertMsg (routerOk n) "${n}: fleet scraping, rules, exporters or Alertmanager clustering are not wired.") (lib.attrNames routers);
        pkgs.runCommand "fleet-metrics" { } "touch $out";

      # WHY: proves each fleet alert fires, and stays quiet when it should.
      checks.fleet-alert-rules =
        let
          file = rulesFile pkgs;
          day = 86400;
          tests = pkgs.writeText "fleet.rules.test.json" (builtins.toJSON {
            rule_files = [ "${file}" ];
            evaluation_interval = "1m";
            tests = [
              {
                interval = "1m";
                input_series = [
                  { series = ''up{job="fleet-node",host="spike",always_on="true"}''; values = "1 1 0x12"; }
                  { series = ''up{job="fleet-node",host="laptop",always_on="false"}''; values = "1 1 0x12"; }
                  { series = ''node_systemd_unit_state{host="spike",name="broken.service",state="failed"}''; values = "0 0 1x8"; }
                  { series = ''node_systemd_unit_state{host="spike",name="fine.service",state="failed"}''; values = "0x10"; }
                  { series = ''node_filesystem_avail_bytes{host="spike",mountpoint="/",fstype="ext4"}''; values = "10x20"; }
                  { series = ''node_filesystem_size_bytes{host="spike",mountpoint="/",fstype="ext4"}''; values = "100x20"; }
                  { series = ''node_filesystem_readonly{host="spike",mountpoint="/",fstype="ext4"}''; values = "0x20"; }
                  { series = ''node_filesystem_avail_bytes{host="spike",mountpoint="/run",fstype="tmpfs"}''; values = "1x20"; }
                  { series = ''node_filesystem_size_bytes{host="spike",mountpoint="/run",fstype="tmpfs"}''; values = "100x20"; }
                  { series = ''node_filesystem_readonly{host="spike",mountpoint="/run",fstype="tmpfs"}''; values = "0x20"; }
                  { series = ''smartctl_device_smart_status{host="spike",device="sda"}''; values = "1 0x10"; }
                  { series = ''smartctl_device_media_errors{host="spike",device="nvme0"}''; values = "0 0 0 2 2 2"; }
                  { series = ''ssl_certificate_expiry_seconds{host="r",path="/c/soon.crt"}''; values = "${toString (10 * day)}x70"; }
                  { series = ''ssl_certificate_expiry_seconds{host="r",path="/c/later.crt"}''; values = "${toString (60 * day)}x70"; }
                ];
                alert_rule_test = [
                  {
                    eval_time = "13m";
                    alertname = "HostDown";
                    exp_alerts = [
                      {
                        exp_labels = { severity = "critical"; job = "fleet-node"; host = "spike"; always_on = "true"; };
                        exp_annotations.summary = "not answering metrics scrapes for 10 minutes";
                      }
                    ];
                  }
                  {
                    eval_time = "8m";
                    alertname = "SystemdUnitFailed";
                    exp_alerts = [
                      {
                        exp_labels = { severity = "warning"; host = "spike"; name = "broken.service"; state = "failed"; };
                        exp_annotations.summary = "broken.service has failed";
                      }
                    ];
                  }
                  {
                    eval_time = "16m";
                    alertname = "FilesystemAlmostFull";
                    exp_alerts = [
                      {
                        exp_labels = { severity = "warning"; host = "spike"; mountpoint = "/"; fstype = "ext4"; };
                        exp_annotations.summary = "/ is 90% full";
                      }
                    ];
                  }
                  {
                    eval_time = "7m";
                    alertname = "DiskSmartFailed";
                    exp_alerts = [
                      {
                        exp_labels = { severity = "critical"; host = "spike"; device = "sda"; };
                        exp_annotations.summary = "SMART health check failed on sda";
                      }
                    ];
                  }
                  {
                    eval_time = "4m";
                    alertname = "DiskMediaErrors";
                    exp_alerts = [
                      {
                        exp_labels = { severity = "warning"; host = "spike"; device = "nvme0"; };
                        exp_annotations.summary = "new media errors on nvme0";
                      }
                    ];
                  }
                  {
                    eval_time = "65m";
                    alertname = "TlsCertificateExpiring";
                    exp_alerts = [
                      {
                        exp_labels = { severity = "warning"; host = "r"; path = "/c/soon.crt"; };
                        exp_annotations.summary = "/c/soon.crt expires in 10d 0h 0m 0s";
                      }
                    ];
                  }
                ];
              }
            ];
          });
        in
        pkgs.runCommand "fleet-alert-rules" { nativeBuildInputs = [ pkgs.prometheus.cli ]; } ''
          promtool check rules ${file}
          promtool test rules ${tests}
          touch $out
        '';
    };
}
