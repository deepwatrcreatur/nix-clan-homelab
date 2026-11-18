# Shared Home Manager settings for fleet machines.
# Ported from unified den/aspects/home-manager-users.nix.
{ den, ... }:
{
  den.aspects.home-manager-users.nixos =
    { lib, ... }:
    {
      home-manager = {
        useGlobalPkgs = lib.mkDefault true;
        useUserPackages = lib.mkDefault true;
        backupFileExtension = lib.mkDefault "bak";
      };

      # WHY: ensures Home Manager activation units communicate with nix-daemon
      systemd.services = {
        "home-manager-root".environment.NIX_REMOTE = "daemon";
        "home-manager-deepwatrcreatur".environment.NIX_REMOTE = "daemon";
      };
    };
}
