{ inputs, ... }:
{
  den.aspects.user-workstation-plasma.homeManager.imports = [
    inputs.plasma-manager.homeModules.plasma-manager
    ../_hm/workstation-desktop/plasma.nix
  ];

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
      programs.bash.shellAliases.neohtop = "NeoHtop";
      programs.fish.shellAliases.neohtop = "NeoHtop";
      programs.zsh.shellAliases.neohtop = "NeoHtop";
      home.packages = with pkgs; [
        flameshot
        neohtop
        vivaldi
        (callPackage ../_packages/omasnap.nix { })
        inputs.nix-linuxbrew.packages.${stdenv.hostPlatform.system}.brew-wrapper
      ] ++ lib.optional (config.programs.bitwarden-cli.enable && !(config.programs.fnox.enable or false)) pkgs.bitwarden-cli;
    };
  };
}
