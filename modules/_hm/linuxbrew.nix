{ inputs }:
{
  config,
  lib,
  pkgs,
  osConfig ? null,
  ...
}:
let
  systemSetupEnabled =
    if osConfig != null then (osConfig.programs.linuxbrew.enableSystemSetup or false) else true;
in
{
  imports = [ inputs.nix-linuxbrew.homeManagerModules.default ];

  config =
    lib.mkIf
      (pkgs.stdenv.hostPlatform.isLinux && config.home.homeDirectory != null && systemSetupEnabled)
      {
        programs.linuxbrew = {
          enable = lib.mkDefault true;
          taps = lib.mkDefault [
            "manaflow-ai/cmux"
            "steveyegge/beads"
            "xykong/tap"
          ];
          brews = lib.mkDefault [
            "ccat"
            "steveyegge/beads/bd"
          ];
        };

        home.packages = [
          inputs.nix-linuxbrew.packages.${pkgs.stdenv.hostPlatform.system}.brew-wrapper
        ];
      };
}
