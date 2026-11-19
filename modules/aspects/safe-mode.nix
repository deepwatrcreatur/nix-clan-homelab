{ ... }:
{
  den.aspects.safe-mode.nixos =
    { lib, ... }:
    {
      imports = [
        ../_nixos/specializations/safe-mode.nix
      ];

      myModules.specializations.safeMode.enable = lib.mkDefault true;
    };
}
