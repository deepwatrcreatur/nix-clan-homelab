# Clan owns machine lifecycle (install, vars, deploy). Host composition comes
# from den: each clan machine imports its den host's mainModule.
# GOTCHA: only den.hosts.x86_64-linux is mapped; add other systems here when
# a non-x86 machine joins.
{
  inputs,
  config,
  lib,
  ...
}:
let
  # WHY: den outputs with their own destination are evaluation fixtures.
  denHosts = lib.filterAttrs (_: host: host.intoAttr == [ ]) (config.den.hosts.x86_64-linux or { });
in
{
  imports = [ inputs.clan-core.flakeModules.default ];

  clan = {
    meta.name = "deepwater";
    # WHY: the LAN zone Technitium serves and Kea registers hosts in; SSH host
    # certificates are issued for <machine>.<domain>.
    meta.domain = "deepwatercreature.com";

    inventory.machines = lib.mapAttrs (
      name: _:
      let
        host = config.homelab.hosts.${name};
      in
      {
        tags = host.roles;
        deploy.targetHost = "${host.sshUser}@${host.sshTarget}";
      }
    ) denHosts;

    # Persistent host keys, CA-signed host certificates, root access for the
    # operator keys; every machine also trusts the CA as a client.
    inventory.instances.sshd = {
      roles.server.tags.all = { };
      roles.server.settings.authorizedKeys = {
        deepwatrcreatur = lib.fileContents ../keys/deepwatrcreatur-phoenix.pub;
        deepwatrcreatur-stable = lib.fileContents ../keys/deepwatrcreatur-stable.pub;
      };
      roles.client.tags.all = { };
    };

    # INVARIANT: fleet hosts reserve nixosConfigurations for Clan by setting
    # intoAttr = [ ] (modules/den.nix).
    # den adds hostPlatform only when it instantiates the host itself.
    machines = lib.mapAttrs (_: host: {
      imports = [ host.mainModule ];
      nixpkgs.hostPlatform = lib.mkDefault host.system;
      # WHY: clan otherwise encrypts only to the admin running the command;
      # the admins group (sops/groups/admins) holds both operator keys.
      clan.core.sops.defaultGroups = [ "admins" ];
    }) denHosts;
  };

  perSystem =
    { config, inputs', pkgs, ... }:
    {
      devShells.default = pkgs.mkShell {
        packages = [
          config.packages.fleet-deploy
          inputs'.clan-core.packages.clan-cli
          # SECURITY: the sops admin identity is the operator SSH key, converted
          # per invocation; no age key file is ever written. docs/plan.md#nch-sny3
          (pkgs.writeShellApplication {
            name = "clan-admin";
            runtimeInputs = [
              inputs'.clan-core.packages.clan-cli
              pkgs.ssh-to-age
            ];
            text = ''
              SOPS_AGE_KEY="$(ssh-to-age -private-key -i "''${CLAN_ADMIN_SSH_KEY:-$HOME/.ssh/id_ed25519}")"
              export SOPS_AGE_KEY
              exec clan "$@"
            '';
          })
        ];
      };
    };
}
