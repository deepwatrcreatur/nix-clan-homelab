{ ... }:
{
  den.aspects.hardware-printer-phoenix-m477.nixos =
    { ... }:
    {
      imports = [
        ../_nixos/hp-print-scan.nix
        ../_nixos/printers/phoenix-hp-m477.nix
      ];
    };
}
