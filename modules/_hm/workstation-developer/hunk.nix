{ hunk }:
{ config, lib, pkgs, ... }:

let
  cfg = config.programs.hunk-custom;
  hunkPkg = hunk.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
{
  imports = [
    hunk.homeManagerModules.default
  ];

  options.programs.hunk-custom = {
    enable = lib.mkEnableOption "Hunk review-first terminal diff viewer for macOS & Linux";
    enableGitIntegration = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Configure Git to use Hunk for diff/show/patch operations.";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.hunk = {
      enable = true;
      package = hunkPkg;
      enableGitIntegration = cfg.enableGitIntegration;
      settings = {
        mode = "split";
        line_numbers = true;
      };
    };

    home.shellAliases = {
      hd = "hunk diff";
      hdw = "hunk diff --watch";
      hs = "hunk show";
    };
  };
}
