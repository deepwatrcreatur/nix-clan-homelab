# Workstation rclone access with the migrated, user-owned Clan credential.
{ den, ... }:
{
  den.aspects.rclone-client.nixos =
    { config, pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.rclone ];
      systemd.tmpfiles.rules = [
        "d /root/.config/rclone 0700 root root -"
        "L+ /root/.config/rclone/rclone.conf - - - - ${config.clan.core.vars.generators.workstation-user-secrets.files.rclone-conf.path}"
      ];
    };
}
