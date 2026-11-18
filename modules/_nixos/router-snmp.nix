{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.router-snmp;
in
{
  options.services.router-snmp = {
    enable = lib.mkEnableOption "router SNMP monitoring";
    communityFile = lib.mkOption {
      type = lib.types.str;
      description = "Runtime file containing the SNMP read-only community.";
    };
    listenAddresses = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "Node-local IPv4 addresses to listen on for SNMP.";
    };
    allowedNetworks = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "Source networks allowed to query this SNMP community.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.router-firewall.trustedUdpPorts = [ 161 ];

    systemd.services.snmpd = {
      description = "Simple Network Management Protocol (SNMP) daemon";
      # GOTCHA: snmpd binds the management address and needs it configured
      # before starting, including on a fresh boot.
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      preStart = ''
        set -euo pipefail
        umask 077
        community="$(cat "$CREDENTIALS_DIRECTORY/community")"
        cat > /run/snmpd/snmpd.conf <<'CONFIG'
        agentAddress ${lib.concatMapStringsSep "," (address: "udp:${address}:161") cfg.listenAddresses}
        sysLocation Homelab
        sysContact deepwatrcreatur@gmail.com
        CONFIG
        ${lib.concatMapStringsSep "\n" (network: ''
          printf 'rocommunity %s %s\n' "$community" ${lib.escapeShellArg network} >> /run/snmpd/snmpd.conf
        '') cfg.allowedNetworks}
      '';
      serviceConfig = {
        LoadCredential = [ "community:${cfg.communityFile}" ];
        RuntimeDirectory = "snmpd";
        ExecStart = "${lib.getExe' pkgs.net-snmp "snmpd"} -f -Lo -c /run/snmpd/snmpd.conf";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
  };
}
