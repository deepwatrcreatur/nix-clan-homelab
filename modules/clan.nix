# Clan owns machine lifecycle (install, vars, deploy). Host composition comes
# from den: each clan machine imports its den host's mainModule.
# GOTCHA: only den.hosts.x86_64-linux is mapped; add other systems here when
# a non-x86 machine joins.
{ inputs, config, lib, ... }:
let
  denHosts = config.den.hosts.x86_64-linux;
in
{
  imports = [ inputs.clan-core.flakeModules.default ];

  clan = {
    meta.name = "deepwater";
    # TODO(nch-sny.4): settle the internal domain used for SSH certificates.
    meta.domain = "deepwater";

    inventory.machines = lib.mapAttrs (_: _: { }) denHosts;

    # INVARIANT: den hosts set intoAttr = [ ] (modules/den.nix), so clan is
    # the only producer of nixosConfigurations.
    # den adds hostPlatform only when it instantiates the host itself.
    machines = lib.mapAttrs (_: host: {
      imports = [ host.mainModule ];
      nixpkgs.hostPlatform = lib.mkDefault host.system;
    }) denHosts;
  };

  perSystem =
    { inputs', pkgs, ... }:
    {
      devShells.default = pkgs.mkShell { packages = [ inputs'.clan-core.packages.clan-cli ]; };
    };
}
