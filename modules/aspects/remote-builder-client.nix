# Offload builds to emerald. Include per host.
# SECURITY: never on routers: the key logs into emerald, and routers hold no
# outbound SSH keys.
{ ... }:
{
  den.aspects.remote-builder-client.nixos =
    { config, ... }:
    {
      clan.core.vars.generators.nix-remote-builder = {
        share = true;
        prompts.key = {
          description = "SSH private key the Nix daemon uses to log into emerald";
          type = "multiline-hidden";
        };
        files.key = { };
        # GOTCHA: clan's multiline prompt drops the final newline, and
        # OpenSSH rejects a private key without one; add it only if missing.
        script = ''sed -e '$a\' "$prompts/key" > "$out/key"'';
      };

      nix.distributedBuilds = true;
      nix.settings.builders-use-substitutes = true;
      nix.buildMachines = [
        {
          # TODO(nch-sny.8): take emerald's address from homelab.hosts once
          # the inventory PR is merged.
          hostName = "10.10.11.55";
          system = "x86_64-linux";
          maxJobs = 8;
          speedFactor = 2;
          supportedFeatures = [
            "nixos-test"
            "benchmark"
            "big-parallel"
            "kvm"
          ];
          sshUser = "deepwatrcreatur";
          sshKey = config.clan.core.vars.generators.nix-remote-builder.files.key.path;
          # WHY: emerald has no clan host certificate until it migrates, so
          # pin its host key instead of relying on the CA.
          # INVARIANT: base64 of keys/emerald-host-ed25519.pub (Nix has no base64 builtin).
          publicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUN1NXZ6YTFURFRjbHFTaDc5WDhKMlVWY0VUU1RGS1JjTk51aWNNZE0yNEMgcm9vdEBlbWVyYWxk";
        }
      ];
    };
}
