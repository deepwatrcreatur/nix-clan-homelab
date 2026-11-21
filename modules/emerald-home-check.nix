{
  config,
  den,
  lib,
  ...
}:
let
  name = "emerald-home-eval";
  destination = [
    "legacyPackages"
    "x86_64-linux"
    name
  ];
in
{
  den.hosts.x86_64-linux.${name} = {
    intoAttr = destination;
    users.deepwatrcreatur = { };
  };

  den.aspects.${name} = {
    includes = with den.aspects; [
      nixos-base
      home-manager-users
    ];
    provides.deepwatrcreatur.includes = with den.aspects; [
      user-workstation-shell
      user-workstation-developer
    ];
    provides.deepwatrcreatur.homeManager.programs.herdr.desktopApp.enable = true;
    nixos = {
      fileSystems."/" = {
        device = "/dev/vda";
        fsType = "btrfs";
      };
      boot.loader.grub.enable = false;
      system.stateVersion = "25.05";
    };
  };

  perSystem =
    { pkgs, ... }:
    let
      host = lib.getAttrFromPath destination config.flake;
      inventory = import ../checks/emerald-home-inventory.nix;
      actual = inventory host.config.home-manager.users.deepwatrcreatur;
      readJSON = path: builtins.fromJSON (builtins.readFile path);
      reference = readJSON ../checks/emerald-home-reference.json;
      expected = readJSON ../checks/emerald-home-expected-differences.json;
      differences = lib.mapAttrs (category: names: {
        missing = lib.subtractLists names reference.${category};
        extra = lib.subtractLists reference.${category} names;
      }) actual;
    in
    {
      legacyPackages.emeraldHomeInventory = actual;
      checks.emerald-home-parity =
        if differences == expected then
          pkgs.runCommand "emerald-home-parity" { } "touch $out"
        else
          throw "Emerald Home Manager differences changed. Observed: ${builtins.toJSON differences}";
    };
}
