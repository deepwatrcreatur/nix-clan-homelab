# Router-service credentials as clan vars (nch-sny.11, router domain).
# SECURITY: include only on router-class hosts; sops encrypts a shared var
# only to machines that declare its generator, so no other host can read
# these. Standby hosts declare only what they use.
# WHY: a `vrrp` member can become MASTER without a redeploy, so it holds the
# primary credentials too (docs/router-vrrp.md).
{
  config,
  lib,
  ...
}:
let
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
    { config, pkgs, ... }:
    let
      # WHY: routerRole.node, not the inventory, so checks can evaluate a host
      # in another mode.
      mode = config.routerRole.node.mode;
      primary = mode == "primary" || mode == "vrrp";
      varPath = name: config.clan.core.vars.generators."router-${name}".files.value.path;
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
      }
      // lib.optionalAttrs (mode == "vrrp") {
        # SECURITY: VRRPv2 PASS auth is clear text on the LAN; it only keeps
        # other VRRP groups out. keepalived uses 8 characters, from a set
        # router-ha accepts.
        router-vrrp-password = {
          share = true;
          files.value.mode = "0400";
          runtimeInputs = [ pkgs.coreutils ];
          script = ''
            tr -dc 'A-Za-z0-9' </dev/urandom | head -c 8 >"$out/value"
          '';
        };
      };

      # WHY: nix-router-optimized's *File options take the clan var paths
      # directly (bootstrapPasswordFile is set in router-role), so no agenix
      # module or age.secrets aliases are needed (nch-sny.29).
      services.router-dashboard.cloudflareTokenFile = lib.mkIf primary (varPath "cloudflare-api-token");

    };
}
