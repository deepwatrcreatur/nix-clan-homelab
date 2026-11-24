{ den, ... }:
{
  den.aspects.mega-vpn-client.nixos = import ../_nixos/mega-vpn-client.nix { };
}
