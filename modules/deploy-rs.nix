# deploy-rs nodes for clan machines: same system closure clan builds, deployed
# with magic rollback (activation must be confirmed over a new SSH connection).
{ inputs, config, lib, ... }:
{
  flake.deploy.nodes = lib.mapAttrs (name: nixos: {
    hostname = "${name}.deepwatercreature.com";
    sshUser = "root";
    profiles.system.path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos nixos;
  }) config.flake.nixosConfigurations;
}
