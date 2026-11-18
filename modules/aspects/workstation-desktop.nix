{ den, inputs, ... }:
{
  den.aspects.workstation-desktop = {
    includes = [ den.aspects.nixos-base ];
    nixos = import ../_nixos/workstation.nix { inherit inputs; };
  };
}
