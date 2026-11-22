{ credentialsPath }:
{ lib, pkgs, ... }:
let
  shares = [ "cloud" "storage" ];
in
{
  environment.systemPackages = [ pkgs.cifs-utils pkgs.samba ];
  fileSystems = lib.listToAttrs (map (share: {
    name = "/${share}";
    value = {
      device = "//10.10.11.88/${share}";
      fsType = "cifs";
      options = [
        "x-systemd.automount"
        "noauto"
        "x-systemd.idle-timeout=60"
        "x-systemd.device-timeout=5s"
        "x-systemd.mount-timeout=5s"
        "_netdev"
        "soft"
        "uid=deepwatrcreatur"
        "gid=users"
        "forceuid"
        "forcegid"
        "file_mode=0770"
        "dir_mode=0770"
        "credentials=${credentialsPath}"
      ];
    };
  }) shares);
  systemd.tmpfiles.rules = map (share: "d /${share} 0775 deepwatrcreatur users -") shares;
}
