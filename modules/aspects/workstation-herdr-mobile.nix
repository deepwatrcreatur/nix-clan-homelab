{ ... }:
{
  den.aspects.workstation-herdr-mobile = {
    nixos.users.users.deepwatrcreatur = {
      linger = true;
      openssh.authorizedKeys.keyFiles = [
        ../../keys/herdr-mobile-1.pub
        ../../keys/herdr-mobile-2.pub
      ];
    };
    provides.deepwatrcreatur.homeManager.programs.herdr.desktopApp.enable = true;
  };
}
