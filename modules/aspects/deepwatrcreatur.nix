# The operator user. SSH access matches unified's stable identity.
{ den, ... }:
{
  den.aspects.deepwatrcreatur = {
    includes = [
      den.batteries.primary-user
      den.aspects.user-server
    ];
    nixos.users.users.deepwatrcreatur.openssh.authorizedKeys.keyFiles = [
      ../../keys/deepwatrcreatur-stable.pub
      ../../keys/deepwatrcreatur-phoenix.pub
    ];
  };
}
