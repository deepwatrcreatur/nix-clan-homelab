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
      ${lib.escapeShellArg name})
        backend=${backendFor host}
        target=${lib.escapeShellArg "${host.sshUser}@${host.sshTarget}"}
        # WHY: same certificate check as clan's targetHost (modules/clan.nix).
        host_key_alias=${lib.escapeShellArg "${name}.${config.homelab.domain}"}
        ;;
    '') deployableHosts
  );
in
{
  perSystem =
    { inputs', pkgs, ... }:
    let
      closureDiff = pkgs.writeScriptBin "closure-diff" (
        "#!${lib.getExe pkgs.python3}\n" + builtins.readFile ../scripts/closure-diff.py
      );
    in
    {
      # GOTCHA: not `deploy`: `.#deploy` would then resolve to this package
      # instead of the top-level deploy-rs output, and deploy-rs breaks.
      packages.fleet-deploy = pkgs.writeShellApplication {
        name = "fleet-deploy";
        # GOTCHA: ssh and nix come from the caller's PATH, like the deploy
        # backends', so the operator's SSH setup and Nix version apply.
        runtimeInputs = [
          closureDiff
          pkgs.coreutils
        ];
        text = ''
          usage() {
            printf 'Usage: fleet-deploy [--dry-run | --diff] <host>\n' >&2
            exit 2
          }

          dry_run=false
          diff=false
          if [[ $# == 2 && ( $2 == --dry-run || $2 == --diff ) ]]; then
            set -- "$2" "$1"
          fi
          case ''${1:-} in
            --dry-run) dry_run=true; shift ;;
            --diff) diff=true; shift ;;
          esac
          [[ $# == 1 && $1 != -* ]] || usage
          host=$1

          case "$host" in
            ${backendCases}
            *) printf 'Host %s is not a migrated Clan machine.\n' "$host" >&2; exit 1 ;;
          esac

          if "$diff"; then
            workdir=$(mktemp -d)
            trap 'rm -rf -- "$workdir"' EXIT
            # WHY: read-only on the host. Only the list of active store paths
            # is fetched; nothing is copied there and nothing is activated.
            # GOTCHA: the running kernel is the booted generation's, which a
            # live switch leaves behind; compare with that, not current-system.
            ssh -o HostKeyAlias="$host_key_alias" "$target" '
              set -e
              PATH=/run/current-system/sw/bin
              readlink -f /run/booted-system/kernel
              nix-store --query --requisites /run/current-system
            ' > "$workdir/remote"
            booted_kernel=$(head -n 1 "$workdir/remote")
            tail -n +2 "$workdir/remote" > "$workdir/old"
            toplevel=$(nix build --no-link --print-out-paths \
              ".#nixosConfigurations.$host.config.system.build.toplevel")
            nix-store --query --requisites "$toplevel" > "$workdir/new"
            closure-diff "$workdir/old" "$workdir/new" \
              "$booted_kernel" "$(readlink -f "$toplevel/kernel")"
            exit 0
          fi

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

      checks.closure-diff = pkgs.runCommand "closure-diff" { nativeBuildInputs = [ pkgs.python3 ]; } ''
        python3 ${../checks/closure-diff.py} ${../scripts/closure-diff.py}
        touch $out
      '';

      checks.deploy-dispatch =
        assert backendFor { roles = [ "router" ]; } == "deploy-rs";
        assert backendFor { roles = [ "router-standby" ]; } == "clan";
        assert backendFor { roles = [ ]; } == "clan";
        pkgs.runCommand "deploy-dispatch" { } "touch $out";
    };
}
