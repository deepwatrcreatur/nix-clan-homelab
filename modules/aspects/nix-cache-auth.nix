# NixCI pull authentication and the reserved Attic push credential.
{ config, lib, ... }:
{
  den.aspects.nix-cache-auth.nixos =
    { config, lib, ... }:
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

      # WHY: the endpoint and its credential must be enabled together to avoid 401s.
      nix.settings = {
        substituters = lib.mkBefore [ "https://cache.nix-ci.com" ];
        trusted-public-keys = [ "nix-ci:g3xV5BDTLtIBZr/A00IU1x0EtKKlb7YLgBN2SgYgM6A=" ];
        netrc-file = gen.files.netrc.path;
      };
    };

  perSystem =
    { pkgs, ... }:
    let
      invalid = lib.filterAttrs (
        _: host:
        let
          settings = host.config.nix.settings;
          generator = host.config.clan.core.vars.generators.nix-cache-auth or null;
          advertisesNixCI = lib.elem "https://cache.nix-ci.com" settings.substituters;
          trustsNixCI = lib.any (lib.hasPrefix "nix-ci:") settings.trusted-public-keys;
          netrc = settings.netrc-file or null;
        in
        !lib.elem "https://cache.nixos.org" settings.substituters
        || advertisesNixCI != trustsNixCI
        || (advertisesNixCI && (netrc == null || netrc == ""))
        || (generator != null && (!advertisesNixCI || netrc != generator.files.netrc.path))
      ) config.flake.nixosConfigurations;
    in
    {
      checks.nix-cache-auth =
        if invalid == { } then
          pkgs.runCommand "nix-cache-auth" { } "touch $out"
        else
          throw "Inconsistent Nix cache settings on ${lib.concatStringsSep ", " (builtins.attrNames invalid)}";
    };
}
