{ config, lib, ... }:
let
  home = config.home.homeDirectory;
  terminalInit = ''
    # An SSH command can start without TERM. Preserve truecolor for known terminal types.
    if [ -z "$TERM" ]; then
      export TERM=xterm-256color
      export COLORTERM=truecolor
    elif [ "$TERM" = "xterm-256color" ] || [ "$TERM" = "tmux-256color" ] || printf %s "$TERM" | grep -q '^screen-256color'; then
      export COLORTERM=truecolor
    fi
  '';
  nixCompletions = shell: ''
    if command -v determinate-nixd &>/dev/null; then
      eval "$(determinate-nixd --nix-bin /nix/var/nix/profiles/default/bin completion ${shell})"
    fi
  '';
in
{
  home = {
    file.".terminfo".source = ./terminfo;
    sessionVariables = {
      EDITOR = "hx";
      VISUAL = "hx";
      NH_FLAKE = "${home}/flakes-worktrees/nix-clan-homelab/main";
      TERMINFO_DIRS = "${home}/.terminfo:/usr/share/terminfo";
    };
    sessionPath = [
      # WHY: NixOS privilege wrappers must take precedence over unwrapped programs.
      "/run/wrappers/bin"
      "${home}/.nix-profile/bin"
      "/home/linuxbrew/.linuxbrew/bin"
      "/home/linuxbrew/.linuxbrew/sbin"
      "${home}/.cargo/bin"
    ];
  };

  programs.bash.initExtra = lib.mkAfter (terminalInit + nixCompletions "bash");
  programs.fish.shellInit = ''
    if command -v determinate-nixd &>/dev/null
      eval (determinate-nixd --nix-bin /nix/var/nix/profiles/default/bin completion fish | string collect)
    end
  '';
  programs.zsh = {
    enable = true;
    initContent = lib.mkAfter (terminalInit + nixCompletions "zsh");
  };
}
