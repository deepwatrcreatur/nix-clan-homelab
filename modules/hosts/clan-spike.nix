# Disposable spike VM on pve-rog (beads nch-sny.1-.6).
{ den, ... }:
{
  den.aspects.clan-spike = {
    includes = [ den.aspects.base ];
    nixos = {
      imports = [ ../../machines/clan-spike/disko.nix ];
      system.stateVersion = "26.05";
    };
  };
}
