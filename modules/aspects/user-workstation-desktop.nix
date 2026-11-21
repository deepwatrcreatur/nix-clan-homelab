{ ... }:
{
  den.aspects.user-workstation-desktop.homeManager = { pkgs, ... }: {
    imports = [
      ../_hm/workstation-desktop/fastfetch.nix
      ../_hm/workstation-desktop/ghostty
      ../_hm/workstation-desktop/zed.nix
    ];
    programs.fastfetch-custom.enable = true;
    programs.firefox = {
      enable = true;
      configPath = ".mozilla/firefox";
    };
    programs.google-chrome.enable = true;
    home.packages = with pkgs; [
      flameshot
      vivaldi
    ];
  };
}
