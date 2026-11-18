# Router-service credentials as clan vars (nch-sny.11, router domain).
# SECURITY: include only on router-class hosts; sops encrypts a shared var
# only to machines that declare its generator, so no other host can read
# these. Ownership beyond root (kea, router-dashboard groups) is set where
# the consuming service is enabled.
{ ... }:
let
  prompt = description: {
    inherit description;
    type = "hidden";
  };
  # One generator per credential, so a host takes only what it uses.
  single = description: {
    share = true;
    prompts.value = prompt description;
    files.value = { };
    script = ''cp "$prompts/value" "$out/value"'';
  };
in
{
  den.aspects.router-secrets.nixos = {
    clan.core.vars.generators = {
      router-cloudflare-api-token = single "Cloudflare API token for DDNS";
      router-technitium-admin-password = single "Technitium admin password";
      router-kea-ddns-tsig-key = single "TSIG key Kea uses for DDNS updates";
      router-tailscale-auth-key = single "Tailscale auth key for the router node";
      router-snmp-community = single "SNMP community string";
    };
  };
}
