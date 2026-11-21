{ inputs, ... }:
{
  den.aspects.user-workstation-shell.homeManager =
    { config, lib, pkgs, ... }:
    let
      jjStarship = inputs.jj-starship.packages.${pkgs.stdenv.hostPlatform.system}.default;
      jjStarshipExe = lib.getExe jjStarship;
    in
    {
      imports = [ ../_hm/emerald-shell/starship.nix ];

      options.programs.jj.enable = lib.mkEnableOption "Jujutsu prompt integration and terminal tooling";

      config = {
        programs = {
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
        home.shellAliases.less = "bat --plain";
      };
    };
}
