# Bootable installer ISO for `clan machines install` targets with no OS (VMs,
# bare metal). Root accepts the operator keys, so no password exchange.
{ inputs, ... }:
{
  perSystem =
    { system, ... }:
    {
      packages.installer-iso =
        (inputs.nixpkgs.lib.nixosSystem {
          modules = [
            "${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
            inputs.clan-core.nixosModules.installer
            {
              nixpkgs.hostPlatform = system;
              users.users.root.openssh.authorizedKeys.keyFiles = [
                ../keys/deepwatrcreatur-stable.pub
                ../keys/deepwatrcreatur-phoenix.pub
              ];
            }
          ];
        }).config.system.build.isoImage;
    };
}
