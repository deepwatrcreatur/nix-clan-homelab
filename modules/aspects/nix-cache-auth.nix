# Authenticated pulls from the private caches: attic on emerald and
# cache.nix-ci.com. Include per host; routers do not take it.
{ ... }:
{
  den.aspects.nix-cache-auth.nixos =
    { config, ... }:
    let
      gen = config.clan.core.vars.generators.nix-cache-auth;
    in
    {
      # WHY: one fleet-wide value, set once with `clan-admin vars set`;
      # sops encrypts a shared var only to machines that declare it.
      clan.core.vars.generators.nix-cache-auth = {
        share = true;
        prompts.attic-token = {
          description = "Attic client JWT for cache-local";
          type = "hidden";
        };
        prompts.nix-ci-netrc = {
          description = "netrc entry for cache.nix-ci.com";
          type = "multiline-hidden";
        };
        files.attic-token = { };
        files.netrc = { };
        # SECURITY: netrc holds only the HTTPS nix-ci entry. The attic
        # substituters are plain HTTP and readable anonymously, so a netrc
        # entry would send the push-capable token in clear for no benefit.
        # attic-token is kept for the (unported) post-build push hook.
        script = ''
          cp "$prompts/attic-token" "$out/attic-token"
          cp "$prompts/nix-ci-netrc" "$out/netrc"
        '';
      };

      # WHY: replaces unified's access-tokens entry, which passed a file
      # path where Nix expects the token itself.
      nix.settings.netrc-file = gen.files.netrc.path;
    };
}
