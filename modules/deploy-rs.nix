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
      autoRollback = true;
      magicRollback = true;
      profiles.system.path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos nixos;
    }
  ) config.flake.nixosConfigurations;
}
