# Settings every NixOS machine gets.
{ den, ... }:
{
  den.aspects.base.nixos =
    { lib, ... }:
    {
      nix.settings.experimental-features = [ "nix-command" "flakes" ];
      services.openssh.enable = true;
      time.timeZone = lib.mkDefault "America/Toronto";
    };
}
