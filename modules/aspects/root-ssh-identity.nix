# Stable root client identity, shared only by hosts that opt into this aspect.
{ den, ... }:
{
  den.aspects.root-ssh-identity.nixos =
    { config, ... }:
    {
      clan.core.vars.generators.root-ssh-identity = {
        share = true;
        prompts.key = {
          description = "Stable root SSH client private key";
          type = "multiline-hidden";
        };
        files.key = {
          owner = "root";
          mode = "0600";
        };
        script = ''sed -e '$a\' "$prompts/key" > "$out/key"'';
      };

      systemd.tmpfiles.rules = [
        "d /root/.ssh 0700 root root -"
        "L+ /root/.ssh/id_ed25519 - - - - ${config.clan.core.vars.generators.root-ssh-identity.files.key.path}"
      ];
    };
}
