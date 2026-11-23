{ ... }:
{
  den.aspects.synology-shares.nixos =
    { config, pkgs, ... }:
    {
      imports = [
        (import ../_nixos/synology-share-mounts.nix {
          credentialsPath = config.clan.core.vars.generators.synology-shares.files.credentials.path;
        })
      ];

      clan.core.vars.generators.synology-shares = {
        share = true;
        prompts.credentials = {
          description = "Synology SMB credentials file for /cloud and /storage";
          type = "multiline-hidden";
        };
        files.credentials.mode = "0400";
        runtimeInputs = [ pkgs.coreutils ];
        script = ''cp "$prompts/credentials" "$out/credentials"'';
      };
    };
}
