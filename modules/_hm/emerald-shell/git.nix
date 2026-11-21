{
  config,
  pkgs,
  lib,
  ...
}:
{
  imports = [
    ./git-ssh-signing.nix
    ./ssh-agent.nix
  ];

  config = {
    # Shell configurations that merge with existing configs from other modules
    programs.bash.initExtra = lib.mkAfter ''

      # SSH environment: disable interactive TUI features over SSH
      if [ -n "$SSH_CONNECTION" ]; then
        export CI=true
        # Disable OpenCode plugins that cause issues over SSH
        export OPENCODE_DISABLE_PLUGINS=1
      fi
    '';

    programs.zsh.initContent = lib.mkAfter ''

      # SSH environment: disable interactive TUI features over SSH
      if [ -n "$SSH_CONNECTION" ]; then
        export CI=true
        # Disable OpenCode plugins that cause issues over SSH
        export OPENCODE_DISABLE_PLUGINS=1
      fi
    '';

    programs.fish.interactiveShellInit = lib.mkAfter ''

      # SSH environment: disable interactive TUI features over SSH
      if test -n "$SSH_CONNECTION"
        set -gx CI true
        # Disable OpenCode plugins that cause issues over SSH
        set -gx OPENCODE_DISABLE_PLUGINS 1
      end
    '';

    programs.nushell.extraConfig = lib.mkAfter ''

      # SSH environment: disable interactive TUI features over SSH
      if ($env.SSH_CONNECTION? != null) {
        $env.CI = "true"
        # Disable OpenCode plugins that cause issues over SSH
        $env.OPENCODE_DISABLE_PLUGINS = "1"
      }

    '';


    home.packages =
      with pkgs;
      [
        delta
        mergiraf
        lazygit
        difftastic # Add difftastic to the list of packages
      ]
      ++ [ meld ]
      ++ lib.optional (!(config.programs.fnox.enable or false)) pkgs.gh;

    programs.git = {
      enable = true;
      package = pkgs.git;
      settings = {
        user.name = "Anwer Khan";
        user.email = "deepwatrcreatur@gmail.com";
        core.excludesfile = "${config.xdg.configHome}/git/ignore";
        init.defaultBranch = "main";
        core.editor = "hx";
        core.fsmonitor = true;
        core.pager = lib.mkDefault "delta";
        interactive.diffFilter = lib.mkDefault "delta --color-only";

        # GitHub credential helpers
        "credential \"https://github.com\"".helper = "!gh auth git-credential";
        "credential \"https://gist.github.com\"".helper = "!gh auth git-credential";


        # Delta settings
        delta.navigate = true;
        delta.syntax-theme = "Dracula";
        delta.line-numbers = true;
        delta.side-by-side = true;

        # Additional configurations
        add.interactive.useBuiltin = false;
        branch.sort = "-committerdate";
        column.ui = "auto";
        diff.algorithm = "histogram";
        diff.colorMoved = "default";
        diff.tool = "vimdiff";
        diff.guitool = "meld";
        diff.external = "${pkgs.difftastic}/bin/difft"; # Use difftastic as the external diff tool
        merge.conflictstyle = "diff3";
        merge.tool = "vimdiff";
        merge.guitool = "meld";
        pull.rebase = true;
        push.autoSetupRemote = true;
        rebase.autoStash = true;
        rebase.autoSquash = true;
        rerere.enabled = true;
        rerere.autoUpdate = true;
        tag.sort = "version:refname";
        alias = {
          co = "checkout";
          br = "branch";
          ci = "commit";
          st = "status";
          graph = "mergiraf";
        };
        url."ssh://git@github.com/".insteadOf = "https://github.com/";
        url."https://github.com/Homebrew/".insteadOf = "https://github.com/Homebrew/";
      };

      lfs.enable = true;
    };

    xdg.configFile."git/ignore".source = ./files/gitignore_global;

  };
}
