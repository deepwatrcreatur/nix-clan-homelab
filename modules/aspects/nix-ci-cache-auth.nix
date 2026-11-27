# NixCI user-cache auth, kept separate from the Attic push token.
{ config, lib, ... }:
{
  den.aspects.nix-ci-cache-auth.nixos =
    { config, lib, ... }:
    let
      gen = config.clan.core.vars.generators.nix-ci-cache-auth;
    in
    {
      clan.core.vars.generators.nix-ci-cache-auth = {
        share = true;
        prompts.nix-ci-netrc = {
          description = "netrc entry for cache.nix-ci.com";
          type = "multiline-hidden";
        };
        files.netrc = { };
        script = ''
          cp "$prompts/nix-ci-netrc" "$out/netrc"
        '';
      };

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
        name: host:
        let
          settings = host.config.nix.settings;
          generator = host.config.clan.core.vars.generators.nix-ci-cache-auth or null;
          advertisesNixCI = lib.elem "https://cache.nix-ci.com" settings.substituters;
          trustsNixCI = lib.any (lib.hasPrefix "nix-ci:") settings.trusted-public-keys;
          netrc = settings.netrc-file or null;
          hostName = host.config.networking.hostName or name;
          inventory = config.homelab.hosts.${hostName} or { };
          isRouter = lib.elem "router" (inventory.roles or [ ]);
        in
        !lib.elem "https://cache.nixos.org" settings.substituters
        || advertisesNixCI != trustsNixCI
        || (advertisesNixCI && (netrc == null || netrc == ""))
        || (generator != null && (!advertisesNixCI || netrc != generator.files.netrc.path))
        # SECURITY: Router-class hosts do not receive the NixCI credential.
        || (isRouter && (advertisesNixCI || generator != null))
      ) config.flake.nixosConfigurations;
    in
    {
      checks.nix-ci-cache-auth =
        if invalid == { } then
          pkgs.runCommand "nix-ci-cache-auth" { } "touch $out"
        else
          throw "Inconsistent Nix cache settings on ${lib.concatStringsSep ", " (builtins.attrNames invalid)}";
    };
}
