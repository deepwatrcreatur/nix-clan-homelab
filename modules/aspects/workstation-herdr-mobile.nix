{ ... }:
{
  den.aspects.workstation-herdr-mobile = {
    nixos.users.users.deepwatrcreatur.linger = true;
    provides.deepwatrcreatur.homeManager.programs.herdr.desktopApp.enable = true;
  };
}
