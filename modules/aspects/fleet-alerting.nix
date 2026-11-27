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
  # WHY: node_exporter's default also excludes .mount and .automount units,
  # so a failed network share would never alert.
  systemdUnitExclude = "--collector.systemd.unit-exclude=.+\\.(device|scope|slice)";
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
      exported = [ ports.node ] ++ lib.optional config.services.prometheus.exporters.smartctl.enable ports.smartctl;
      portList = lib.concatMapStringsSep ", " toString exported;
      sourceList = lib.concatStringsSep ", " scraperAddresses;
      # SECURITY: drop exporter traffic from anyone but the routers in the raw
      # table, before tailscaled's ts-input chain (which accepts all tailnet
      # input ahead of nixos-fw) or a trusted interface can accept it. IPv6
      # is dropped outright: the routers scrape over IPv4.
      rawChain = lib.concatStringsSep "\n" (
        lib.concatMap (tool: [
          "${tool} -t raw -N fleet-exporters 2>/dev/null || ${tool} -t raw -F fleet-exporters"
          "${tool} -t raw -C PREROUTING -j fleet-exporters 2>/dev/null || ${tool} -t raw -I PREROUTING -j fleet-exporters"
        ]) [ "iptables" "ip6tables" ]
        ++ lib.concatMap (
          port:
          map (source: "iptables -t raw -A fleet-exporters -p tcp -s ${source} --dport ${toString port} -j RETURN") scraperAddresses
          ++ [
            "iptables -t raw -A fleet-exporters -p tcp --dport ${toString port} -j DROP"
            "ip6tables -t raw -A fleet-exporters -p tcp --dport ${toString port} -j DROP"
          ]
        ) exported
      );
      rawChainStop = lib.concatMapStringsSep "\n" (tool: ''
        ${tool} -t raw -D PREROUTING -j fleet-exporters 2>/dev/null || true
        ${tool} -t raw -F fleet-exporters 2>/dev/null || true
        ${tool} -t raw -X fleet-exporters 2>/dev/null || true
      '') [ "iptables" "ip6tables" ];
      # The accept in nixos-fw itself (default deny); IPv4 iptables, not
      # ip46tables, because the sources are IPv4.
      accepts = lib.concatMapStringsSep "\n" (
        port:
        lib.concatMapStringsSep "\n" (
          source: "iptables -A nixos-fw -p tcp -s ${source} --dport ${toString port} -j nixos-fw-accept"
        ) scraperAddresses
      ) exported;
    in
    lib.mkIf (!isRouter) {
      services.prometheus.exporters.node = {
        enable = true;
        enabledCollectors = [ "systemd" ];
        extraFlags = [ systemdUnitExclude ];
      };
      services.prometheus.exporters.smartctl.enable = lib.mkDefault (!config.boot.isContainer);
      networking.firewall = lib.mkIf config.networking.firewall.enable (
        if nft then
          { extraInputRules = "ip saddr { ${sourceList} } tcp dport { ${portList} } accept"; }
        else
          {
            extraCommands = rawChain + "\n" + accepts;
            extraStopCommands = rawChainStop;
          }
      );
      networking.nftables.tables.fleet-exporters = lib.mkIf (nft && config.networking.firewall.enable) {
        family = "inet";
        content = ''
          chain prerouting {
            type filter hook prerouting priority raw; policy accept;
            tcp dport { ${portList} } ip saddr { ${sourceList} } return
            tcp dport { ${portList} } drop
          }
        '';
      };
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
      services.prometheus.exporters.node.extraFlags = [ systemdUnitExclude ];
      # SECURITY: the cluster carries silences and notification state. The
      # LAN rule below admits the peer; this drop comes first in the input
      # chain, so no trusted or overlay interface (tailscale0) admits others.
      services.router-firewall.extraInputEarlyRules = lib.mkIf (peerIps != [ ]) ''
        meta l4proto { tcp, udp } th dport ${clusterPort} ip saddr != { ${lib.concatStringsSep ", " peerIps} } drop comment "Alertmanager cluster: peer only"
        meta nfproto ipv6 meta l4proto { tcp, udp } th dport ${clusterPort} drop comment "Alertmanager cluster: peer only"
      '';
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
          sourceSet = "{ ${lib.concatStringsSep ", " scraperAddresses} }";
          hostCfgOk =
            cfg:
            let
              node = cfg.services.prometheus.exporters.node;
              fw = cfg.networking.firewall;
              portSet = "{ ${lib.concatMapStringsSep ", " toString ([ ports.node ] ++ lib.optional cfg.services.prometheus.exporters.smartctl.enable ports.smartctl)} }";
            in
            node.enable
            && lib.elem "systemd" node.enabledCollectors
            && lib.elem systemdUnitExclude node.extraFlags
            && !node.openFirewall
            && (
              if cfg.networking.nftables.enable then
                let
                  raw = cfg.networking.nftables.tables.fleet-exporters.content;
                in
                lib.hasInfix "ip saddr ${sourceSet} tcp dport ${portSet} accept" fw.extraInputRules
                && lib.hasInfix "priority raw" raw
                && lib.hasInfix "tcp dport ${portSet} ip saddr ${sourceSet} return" raw
                && lib.hasInfix "tcp dport ${portSet} drop" raw
              else
                lib.all (
                  source:
                  lib.hasInfix "iptables -A nixos-fw -p tcp -s ${source} --dport ${toString ports.node}" fw.extraCommands
                  && lib.hasInfix "iptables -t raw -A fleet-exporters -p tcp -s ${source} --dport ${toString ports.node} -j RETURN" fw.extraCommands
                ) scraperAddresses
                && lib.hasInfix "iptables -t raw -A fleet-exporters -p tcp --dport ${toString ports.node} -j DROP" fw.extraCommands
                && lib.hasInfix "ip6tables -t raw -A fleet-exporters -p tcp --dport ${toString ports.node} -j DROP" fw.extraCommands
                && lib.hasInfix "-D PREROUTING -j fleet-exporters" fw.extraStopCommands
            );
          hostOk = name: hostCfgOk (hostCfg name);
          # WHY: no fleet host uses nftables yet; prove that branch too.
          nftVariantOk =
            name:
            hostCfgOk
              (config.flake.nixosConfigurations.${name}.extendModules {
                modules = [ { networking.nftables.enable = true; } ];
              }).config;
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
            && lib.elem systemdUnitExclude cfg.services.prometheus.exporters.node.extraFlags
            && (
              peers == { }
              || lib.hasInfix "dport ${toString ports.alertmanagerCluster}" cfg.services.router-firewall.extraLanLocalRules
              && lib.hasInfix "dport ${toString ports.alertmanagerCluster} ip saddr != {" cfg.services.router-firewall.extraInputEarlyRules
            );
        in
        assert lib.all (n: lib.assertMsg (hostOk n) "${n}: fleet exporters or their firewall rules are missing.") (lib.attrNames fleetHosts);
        assert lib.all (n: lib.assertMsg (nftVariantOk n) "${n}: with nftables, fleet exporter firewall rules are missing.") (lib.attrNames fleetHosts);
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
                  { series = ''node_systemd_unit_state{host="spike",name="cloud.mount",state="failed"}''; values = "0 0 1x8"; }
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
                      {
                        exp_labels = { severity = "warning"; host = "spike"; name = "cloud.mount"; state = "failed"; };
                        exp_annotations.summary = "cloud.mount has failed";
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
