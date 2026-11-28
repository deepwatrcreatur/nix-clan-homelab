{ den, inputs, ... }:
{
  den.aspects.linuxbrew = {
    provides.deepwatrcreatur.homeManager.imports = [
      (import ../_hm/linuxbrew.nix { inherit inputs; })
    ];
  };
}
