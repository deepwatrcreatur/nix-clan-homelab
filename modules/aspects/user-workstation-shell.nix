{ config, inputs, ... }:
let
  inherit (config) homelab;
in
{
  den.aspects.user-workstation-shell.homeManager =
    { config, lib, pkgs, ... }:
    let
      jjStarship = inputs.jj-starship.packages.${pkgs.stdenv.hostPlatform.system}.default;
      jjStarshipExe = lib.getExe jjStarship;
    in
    {
      imports = [
        ../_hm/emerald-shell/atuin.nix
        ../_hm/emerald-shell/environment.nix
        ../_hm/emerald-shell/fd-enhanced.nix
        ../_hm/emerald-shell/fish.nix
        ../_hm/emerald-shell/git.nix
        ../_hm/emerald-shell/helix
        ../_hm/emerald-shell/just.nix
        ../_hm/emerald-shell/motd.nix
        ../_hm/emerald-shell/nushell.nix
        (import ../_hm/emerald-shell/packages.nix { inherit inputs; })
        ../_hm/emerald-shell/ripgrep-enhanced.nix
        ../_hm/emerald-shell/shell-aliases.nix
        (import ../_hm/emerald-shell/ssh.nix { inherit (homelab) domain hosts; })
        ../_hm/emerald-shell/starship.nix
        ../_hm/emerald-shell/tmux-enhanced.nix
        (import ../_hm/emerald-shell/yazelix.nix { inherit (inputs) zellij-vivid-rounded; })
        inputs.zellij-vivid-rounded.homeManagerModules.default
      ];

      options.programs.jj.enable = lib.mkEnableOption "Jujutsu prompt integration and terminal tooling";

      config = {
        programs = {
          home-manager.enable = true;
          zellij-vivid-rounded.enable = true;
          nh = {
            enable = true;
            clean.enable = true;
            clean.extraArgs = "--keep-since 4d --keep 3";
          };

          bat = {
            enable = true;
            config = {
              theme = "OneHalfDark";
              pager = "less --quit-if-one-screen --RAW-CONTROL-CHARS";
            };
          };

          eza = {
            enable = true;
            enableBashIntegration = true;
            enableFishIntegration = true;
            enableNushellIntegration = true;
            enableZshIntegration = true;
          };

          fzf = {
            enable = true;
            tmux.enableShellIntegration = true;
            enableBashIntegration = true;
            enableFishIntegration = true;
            enableZshIntegration = true;
          };

          zoxide = {
            enable = true;
            enableBashIntegration = true;
            enableFishIntegration = true;
            enableNushellIntegration = true;
            enableZshIntegration = true;
          };

          jj.enable = true;
          jujutsu.enable = config.programs.jj.enable;
          starship.settings = lib.mkIf config.programs.jj.enable {
            # WHY: jj-starship renders Git and Jujutsu state in the same prompt slot.
            git_branch.disabled = lib.mkForce true;
            git_status.disabled = lib.mkForce true;
            custom.jj = {
              when = "${jjStarshipExe} detect";
              command = "";
              shell = [ jjStarshipExe ];
              format = "$output ";
              ignore_timeout = true;
            };
          };
        };

        home.packages = [ pkgs.rename ] ++ lib.optionals config.programs.jj.enable [
          jjStarship
          pkgs.jjui
        ];
        home.sessionVariables = {
          MANPAGER = "bat --plain";
          PAGER = "bat --plain";
        };
      };
    };
}
