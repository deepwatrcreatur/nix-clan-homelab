{ ... }:
{
  den.aspects.user-workstation-desktop.homeManager = { config, lib, pkgs, ... }: {
    imports = [
      ../_hm/workstation-desktop/fastfetch.nix
      ../_hm/workstation-desktop/ghostty
      ../_hm/workstation-desktop/rclone-scripts.nix
      ../_hm/workstation-desktop/zed.nix
    ];
    options.programs.bitwarden-cli.enable = lib.mkEnableOption "Bitwarden CLI";
    config = {
      programs.fastfetch-custom.enable = true;
      programs.bitwarden-cli.enable = true;
      programs.rclone-scripts.enable = true;
      programs.rbw = {
        enable = true;
        settings = {
          email = "bitwarden.com@deepwatercreature.com";
          lock_timeout = 300;
          pinentry = pkgs.pinentry-curses;
        };
      };
      programs.firefox = {
        enable = true;
        configPath = ".mozilla/firefox";
      };
      programs.google-chrome.enable = true;
      home.packages = with pkgs; [
        flameshot
        vivaldi
      ] ++ lib.optional (config.programs.bitwarden-cli.enable && !(config.programs.fnox.enable or false)) pkgs.bitwarden-cli;
    };
  };
}
