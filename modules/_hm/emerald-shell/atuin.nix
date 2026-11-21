{
  lib,
  ...
}:

{
  programs.atuin = {
    enable = true;
    enableFishIntegration = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
  };

  # Add shell alias for atuin script run (if atuin is available)
  programs.bash.initExtra = ''
    if command -v atuin &>/dev/null; then
      alias asr="atuin script run"
    fi
  '';
  programs.zsh.initContent = ''
    if command -v atuin &>/dev/null; then
      alias asr="atuin script run"
    fi
  '';
  programs.fish.shellInit = lib.mkAfter ''
    # Set ATUIN_SESSION for atuin (if available)
    if command -v atuin &>/dev/null
      set -gx ATUIN_SESSION (atuin uuid)
      alias asr "atuin script run"
    end
  '';
  programs.nushell.extraConfig = lib.mkAfter ''
    if (which atuin | is-not-empty) {
      alias asr = atuin script run
    }
  '';

}
