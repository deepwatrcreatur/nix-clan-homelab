{ ... }:
{
  den.aspects.btrfs-snapper.nixos =
    { ... }:
    {
      imports = [
        ../_nixos/snapper.nix
      ];
    };
}
