# den: hosts, users and aspects. Hosts are instantiated by clan, not den.
{ inputs, den, lib, ... }:
{
  imports = [ inputs.den.flakeModule ];

  den.schema.user.classes = lib.mkDefault [ "homeManager" ];
  # WHY: a user's own nixos content (SSH keys, groups) belongs on every host
  # the user is on; opt into den's explicit form (denful/den#694).
  den.schema.host.includes = [ den.batteries.user-aspects ];
  den.default.homeManager.home.stateVersion = lib.mkDefault "26.05";

  den.hosts.x86_64-linux.clan-spike = {
    intoAttr = [ ];
    users.deepwatrcreatur = { };
  };
}
