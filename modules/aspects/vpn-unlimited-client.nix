{ den, ... }:
{
  den.aspects.vpn-unlimited-client.nixos = import ../_nixos/vpn-unlimited-client.nix { };
}
