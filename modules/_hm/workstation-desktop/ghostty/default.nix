{ pkgs, ... }:
{
  home.sessionVariables.TERMINAL = "ghostty";
  programs.ghostty = {
    enable = true;
    installBatSyntax = true;
    systemd.enable = true;
  };

  xdg.configFile."ghostty/config".source = pkgs.replaceVars ./config {
    shellCommand = "${pkgs.fish}/bin/fish";
  };
  xdg.configFile."ghostty/themes/Sugarplum".source = ./themes/Sugarplum;

  xdg.desktopEntries.ghostty = {
    name = "Ghostty";
    comment = "Terminal emulator";
    icon = "ghostty";
    exec = "${pkgs.ghostty}/bin/ghostty";
    categories = [
      "System"
      "TerminalEmulator"
    ];
    terminal = false;
  };
}
