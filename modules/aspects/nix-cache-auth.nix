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
        # INVARIANT: netrc = nix-ci entry + one attic entry per substituter
        # host name. Attic accepts the token as the netrc password.
        script = ''
          cp "$prompts/attic-token" "$out/attic-token"
          {
            cat "$prompts/nix-ci-netrc"
            echo
            for host in attic-cache 10.10.11.55; do
              echo "machine $host password $(cat "$prompts/attic-token")"
            done
          } > "$out/netrc"
        '';
      };

      # WHY: replaces unified's access-tokens entry, which passed a file
      # path where Nix expects the token itself.
      nix.settings.netrc-file = gen.files.netrc.path;
    };
}
