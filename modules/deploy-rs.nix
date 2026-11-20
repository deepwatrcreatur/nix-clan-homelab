# deploy-rs nodes for clan machines: same system closure clan builds, deployed
# with magic rollback (activation must be confirmed over a new SSH connection).
{
  inputs,
  config,
  lib,
  ...
}:
{
  flake.deploy.nodes = lib.mapAttrs (
    name: nixos:
    let
      host = config.homelab.hosts.${name};
    in
    {
      hostname = host.sshTarget;
      inherit (host) sshUser;
      # WHY: same certificate check as clan's targetHost (modules/clan.nix).
      sshOpts = [ "-o" "HostKeyAlias=${name}.${config.homelab.domain}" ];
      # GOTCHA: deploy-rs activates as the SSH user unless told otherwise;
      # a non-root sshUser then fails to switch the system and rolls back.
      user = "root";
      # WHY: router activations retune NICs (router-offload-negotiate) and
      # bounce the deploy link for seconds; the 30 s default timed out on
      # elitedesk's first router-role deploy and left the profile rolled back
      # while the new system kept running.
      confirmTimeout = 120;
      # WHY: push every path from the deployer. Without it the target
      # substitutes on its own, and elitedesk's management-only network has
      # no internet: the substituters timed out and the copy aborted
      # (2026-11-20). Routers shouldn't depend on caches mid-deploy anyway.
      fastConnection = true;
      autoRollback = true;
      magicRollback = true;
      profiles.system.path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos nixos;
    }
  ) config.flake.nixosConfigurations;
}
