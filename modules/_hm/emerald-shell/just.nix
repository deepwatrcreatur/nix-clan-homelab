{ pkgs, ... }:
let
  justHome = pkgs.writeShellScriptBin "just-home" ''
    exec ${pkgs.just}/bin/just --justfile "$HOME/.justfile" --working-directory . "$@"
  '';
  recipeCommand =
    name: recipe:
    pkgs.writeShellApplication {
      inherit name;
      text = ''
        flags=()
        while (( $# )); do
          case "$1" in
            --) shift; break ;;
            -*) flags+=("$1"); shift ;;
            *) break ;;
          esac
        done
        exec ${justHome}/bin/just-home "''${flags[@]}" ${recipe} "$@"
      '';
    };
in
{
  home.file.".justfile".source = ./Justfile;
  home.packages = [
    pkgs.just
    justHome
    (recipeCommand "update-system" "update")
    (recipeCommand "nh-update-system" "nh-update")
  ];
}
