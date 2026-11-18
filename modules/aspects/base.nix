# Settings every NixOS machine gets.
{ den, ... }:
{
  den.aspects.base.nixos =
    { lib, ... }:
    {
      nix.settings.experimental-features = [ "nix-command" "flakes" ];
      services.openssh.enable = true;
      # WHY: operators log in with SSH keys only and have no password, so
      # wheel must not need one (same policy as unified's hosts).
      security.sudo.wheelNeedsPassword = false;
      time.timeZone = lib.mkDefault "America/Toronto";
    };
}
