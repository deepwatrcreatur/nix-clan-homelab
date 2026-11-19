{ den, ... }:
{
  den.aspects.orca-ide.nixos =
    { lib, ... }:
    {
      imports = [
        ../_nixos/orca-ide.nix
      ];

      modules.desktop.apps.orca-ide.enable = lib.mkDefault true;
    };

  den.aspects.orca = den.aspects.orca-ide;
}
