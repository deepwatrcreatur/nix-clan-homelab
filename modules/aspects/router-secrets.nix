# Router-service credentials as clan vars (nch-sny.11, router domain).
# SECURITY: include only on router-class hosts; sops encrypts a shared var
# only to machines that declare its generator, so no other host can read
# these. Standby hosts declare only what they use.
# TODO(nch-sny.27): with VRRP election a standby takes over without a
# redeploy, so it will need the primary-only credentials installed too.
{
  config,
  lib,
  ...
}:
let
  hosts = config.homelab.hosts;
  single = description: file: {
    share = true;
    prompts.value = {
      inherit description;
      type = "hidden";
    };
    files.value = file;
    script = ''cp "$prompts/value" "$out/value"'';
  };
in
{
  den.aspects.router-secrets.nixos =
    { config, ... }:
    let
      primary = hosts.${config.networking.hostName}.router.mode == "primary";
      varPath = name: config.clan.core.vars.generators."router-${name}".files.value.path;
      passwordPath = varPath "technitium-admin-password";
    in
    {
      # SECURITY: shared router credentials are scoped to the machines that
      # declare their generators, with group access only for service accounts.
      clan.core.vars.generators = {
        router-technitium-admin-password = single "Technitium admin password" { mode = "0400"; };
        router-snmp-community = single "SNMP community string" { mode = "0400"; };
        # WHY: every router node sends alerts, so all of them hold these.
        router-ntfy-url = single "ntfy topic URL for router alerts (https://ntfy.sh/<topic>)" { mode = "0400"; };
        # WHY: per router, not shared: with one check a dead router hides
        # behind the other router's pings.
        router-healthchecks-ping-url = single "healthchecks.io ping URL for this router's alert watchdog" { mode = "0400"; } // { share = false; };
        # WHY: primary and standby sign zone transfers with the same key.
        router-technitium-zone-transfer-tsig = single "TSIG key for Technitium zone transfers (base64)" {
          mode = "0400";
        };
      }
      // lib.optionalAttrs primary {
        router-cloudflare-api-token = single "Cloudflare API token for DDNS" {
          group = "router-dashboard";
          mode = "0440";
        };
        router-kea-ddns-tsig-key = single "TSIG key Kea uses for DDNS updates" {
          group = "kea";
          mode = "0440";
        };
        router-tailscale-auth-key = single "Tailscale auth key for the router node" { mode = "0400"; };
      };

      # SECURITY: systemd makes the root-only password available to the
      # Technitium service's dynamic user through its credentials directory.
      systemd.services.technitium-dns-server = {
        serviceConfig.LoadCredential = [ "admin-password:${passwordPath}" ];
        environment.DNS_SERVER_ADMIN_PASSWORD_FILE = lib.mkForce "%d/admin-password";
      };
    };
}
