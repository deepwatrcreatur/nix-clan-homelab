{
  config,
  lib,
  ...
}:
let
  backendFor = host: if builtins.elem "router" host.roles then "deploy-rs" else "clan";
  deployableHosts = lib.filterAttrs (
    name: host: host.migrated && !host.archived && builtins.hasAttr name config.flake.clan.machines
  ) config.homelab.hosts;
  backendCases = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (name: host: ''
      ${lib.escapeShellArg name}) backend=${backendFor host} ;;
    '') deployableHosts
  );
in
{
  perSystem =
    { inputs', pkgs, ... }:
    {
      packages.deploy = pkgs.writeShellApplication {
        name = "deploy";
        text = ''
          usage() {
            printf 'Usage: deploy [--dry-run] <host>\n' >&2
            exit 2
          }

          dry_run=false
          if [[ $# == 2 && $2 == --dry-run ]]; then
            set -- "$2" "$1"
          fi
          if [[ ''${1:-} == --dry-run ]]; then
            dry_run=true
            shift
          fi
          [[ $# == 1 && $1 != -* ]] || usage
          host=$1

          case "$host" in
            ${backendCases}
            *) printf 'Host %s is not a migrated Clan machine.\n' "$host" >&2; exit 1 ;;
          esac

          case "$backend" in
            deploy-rs) command=(${lib.getExe' inputs'.deploy-rs.packages.deploy-rs "deploy"} ".#$host") ;;
            clan) command=(clan-admin machines update "$host") ;;
          esac

          if "$dry_run"; then
            printf '%q' "''${command[0]}"
            printf ' %q' "''${command[@]:1}"
            printf '\n'
            exit 0
          fi
          exec "''${command[@]}"
        '';
      };

      checks.deploy-dispatch =
        assert backendFor { roles = [ "router" ]; } == "deploy-rs";
        assert backendFor { roles = [ "router-standby" ]; } == "clan";
        assert backendFor { roles = [ ]; } == "clan";
        pkgs.runCommand "deploy-dispatch" { } "touch $out";
    };
}
