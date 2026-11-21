{ config, lib, pkgs, ... }:
let
  filter = lib.escapeShellArg "${config.xdg.configHome}/rclone/filter.txt";
  sync =
    name: remote:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [ config.programs.rclone.package ];
      text = ''
        if [ "$#" -ne 2 ]; then
          printf 'Usage: %s <local_dir> <remote_dir>\n' "$0" >&2
          exit 1
        fi
        exec rclone sync --progress --verbose --metadata --filter-from ${filter} -- "$1" "${remote}:$2"
      '';
    };
in
{
  options.programs.rclone-scripts.enable = lib.mkEnableOption "rclone sync commands";
  config = lib.mkIf config.programs.rclone-scripts.enable {
    programs.rclone.enable = true;
    xdg.configFile."rclone/filter.txt".source = ./rclone-filter.txt;
    home.packages = [
      (sync "onedrive-sync" "OneDrive")
      (sync "mega-rclone" "mega")
    ];
  };
}
