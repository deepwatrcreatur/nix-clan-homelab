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
      # GOTCHA: deploy-rs activates as the SSH user unless told otherwise;
      # a non-root sshUser then fails to switch the system and rolls back.
      user = "root";
      autoRollback = true;
      magicRollback = true;
      profiles.system.path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos nixos;
    }
  ) config.flake.nixosConfigurations;
}
