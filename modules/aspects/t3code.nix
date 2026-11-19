{ ... }:
{
  den.aspects.t3code.nixos =
    { lib, ... }:
    {
      imports = [
        ../_nixos/t3code.nix
      ];

      modules.desktop.apps.t3code = {
        enable = lib.mkDefault true;
        openFirewall = lib.mkDefault true;
        user = lib.mkDefault "deepwatrcreatur";
        tailscaleServe = lib.mkDefault true;
      };
    };
}
