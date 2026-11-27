{
  config,
  lib,
  ...
}:
let
  backendFor = host: host.deployBackend;
  routerBackend = config.homelab.hosts.router.deployBackend;
  workstationBackend = config.homelab.hosts.lattitude.deployBackend;
  deployableHosts = lib.filterAttrs (
    name: host: host.migrated && !host.archived && builtins.hasAttr name config.flake.clan.machines
  ) config.homelab.hosts;
  # The hosts fleet-status reads, with the same SSH target and host key alias.
  statusHosts = builtins.toJSON (
    lib.mapAttrs (name: host: {
      target = "${host.sshUser}@${host.deployTarget}";
      alias = host.sshHostKeyAlias;
    }) deployableHosts
  );
  backendCases = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (name: host: ''
      ${lib.escapeShellArg name})
        backend=${backendFor host}
        target=${lib.escapeShellArg "${host.sshUser}@${host.deployTarget}"}
        # WHY: same certificate check as clan's targetHost (modules/clan.nix).
        host_key_alias=${lib.escapeShellArg host.sshHostKeyAlias}
        ;;
    '') deployableHosts
  );
in
{
  perSystem =
    {
      config,
      inputs',
      pkgs,
      ...
    }:
    let
      closureDiff = pkgs.writeScriptBin "closure-diff" (
        "#!${lib.getExe pkgs.python3}\n" + builtins.readFile ../scripts/closure-diff.py
      );
      deployHealth = pkgs.writeScriptBin "deploy-health" (
        "#!${lib.getExe pkgs.python3}\n" + builtins.readFile ../scripts/deploy-health.py
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
          deployHealth
          pkgs.coreutils
        ];
        text = ''
          usage() {
            printf 'Usage: fleet-deploy [--dry-run | --diff | --no-check] <host>\n' >&2
            exit 2
          }

          dry_run=false
          diff=false
          check=true
          host=""
          for arg; do
            case $arg in
              --dry-run) dry_run=true ;;
              --diff) diff=true ;;
              --no-check) check=false ;;
              -*) usage ;;
              *) [[ -z $host ]] || usage; host=$arg ;;
            esac
          done
          [[ -n $host ]] || usage
          if "$dry_run" && "$diff"; then usage; fi

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
          if ! "$check"; then
            exec "''${command[@]}"
          fi

          # WHY: clan machines update has no post-activation check
          # (clan-core #3078); deploy-rs's magic rollback only proves SSH
          # still works. Compare failed units with a snapshot from before, so
          # a unit that was already failing does not fail every deploy.
          # INVARIANT: the rollback is printed, never run.
          snapshot=$(mktemp)
          trap 'rm -f -- "$snapshot"' EXIT
          deploy-health before "$host_key_alias" "$target" > "$snapshot" || {
            printf 'Use --no-check to deploy without the health check.\n' >&2
            exit 1
          }
          deploy_status=0
          "''${command[@]}" || deploy_status=$?
          health_status=0
          deploy-health after "$host_key_alias" "$target" "$snapshot" || health_status=$?
          if (( deploy_status != 0 )); then
            printf 'Deploy exited %s.\n' "$deploy_status" >&2
            exit "$deploy_status"
          fi
          exit "$health_status"
        '';
      };

      # Read-only: which hosts lag this checkout, need a reboot or have failed
      # units (nch-a9a.3). ssh and nix come from the caller's PATH.
      packages.fleet-status = pkgs.writeShellApplication {
        name = "fleet-status";
        text = ''
          FLEET_STATUS_HOSTS=${lib.escapeShellArg statusHosts} \
            exec ${lib.getExe pkgs.python3} ${../scripts/fleet-status.py} "$@"
        '';
      };

      checks.fleet-status = pkgs.runCommand "fleet-status" { nativeBuildInputs = [ pkgs.python3 ]; } ''
        python3 ${../checks/fleet-status.py} ${../scripts/fleet-status.py}
        touch $out
      '';

      checks.deploy-health = pkgs.runCommand "deploy-health" { nativeBuildInputs = [ pkgs.python3 ]; } ''
        python3 ${../checks/deploy-health.py} ${../scripts/deploy-health.py} \
          ${lib.getExe config.packages.fleet-deploy}
        touch $out
      '';

      checks.closure-diff = pkgs.runCommand "closure-diff" { nativeBuildInputs = [ pkgs.python3 ]; } ''
        python3 ${../checks/closure-diff.py} ${../scripts/closure-diff.py}
        touch $out
      '';

      checks.deploy-dispatch =
        assert routerBackend == "deploy-rs";
        assert workstationBackend == "clan";
        pkgs.runCommand "deploy-dispatch" { } "touch $out";
    };
}
