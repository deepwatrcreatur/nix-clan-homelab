# The operator user. SSH access matches unified's stable identity.
{ den, ... }:
{
  den.aspects.deepwatrcreatur = {
    includes = [ den.batteries.primary-user ];
    nixos.users.users.deepwatrcreatur.openssh.authorizedKeys.keyFiles = [
      ../../keys/deepwatrcreatur-stable.pub
      ../../keys/deepwatrcreatur-phoenix.pub
    ];
    homeManager = { pkgs, ... }: { home.packages = [ pkgs.htop ]; };
  };
}
