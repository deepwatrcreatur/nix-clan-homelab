{ config, lib, ... }:
let
  inherit (config.flake) clan deploy;
  inherit (config.homelab) domain hosts;
  matchingIdentity =
    name: machine:
    let
      host = hosts.${name};
      node = deploy.nodes.${name};
    in
    machine.deploy.targetHost
    == "${host.sshUser}@${host.sshTarget}?HostKeyAlias=${host.sshHostKeyAlias}"
    && node.hostname == host.sshTarget
    && node.sshUser == host.sshUser
    &&
      node.sshOpts == [
        "-o"
        "HostKeyAlias=${host.sshHostKeyAlias}"
      ];
in
{
  perSystem = { pkgs, ... }: {
    checks.deploy-ssh-identity =
      assert hosts.elitedesk.sshHostKeyAlias == "elitedesk.${domain}";
      assert hosts.elitedesk.sshTarget != hosts.elitedesk.sshHostKeyAlias;
      assert lib.all (name: matchingIdentity name clan.inventory.machines.${name}) (
        builtins.attrNames clan.inventory.machines
      );
      pkgs.runCommand "deploy-ssh-identity" { } "touch $out";
  };
}
