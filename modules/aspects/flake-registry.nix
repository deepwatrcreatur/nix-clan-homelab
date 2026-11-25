# Pin the flake registry to this flake's locked inputs on workstations.
# WHY: nixos-base sets `flake-registry = ""`, so only NixOS's built-in
# `nixpkgs` entry resolves; `nix run home-manager#...` failed. The entries are
# store paths in the system closure, so garbage collection keeps those sources.
# GOTCHA: only the source revision is pinned. `nix run home-manager` uses that
# flake's own flake.lock, not our `follows`, so it may download dependencies
# and does not work offline. #57 covers offline evaluation of this checkout.
{
  config,
  den,
  inputs,
  lib,
  ...
}:
{
  den.aspects.flake-registry.nixos = {
    # GOTCHA: `nixpkgs` is left to NixOS (nixpkgs.flake.setFlakeRegistry), and
    # `self` would put every commit's source tree in the closure.
    nix.registry = lib.mapAttrs (_: flake: { inherit flake; }) (
      lib.filterAttrs (_: lib.isType "flake") (
        removeAttrs inputs [
          "self"
          "nixpkgs"
        ]
      )
    );
    # WHY: nixpkgs resolves through the registry; a channel could only shadow
    # it with an unpinned copy.
    nix.channel.enable = false;
  };

  # Only the desktop aspects: routers and containers do not evaluate flakes,
  # and deploys push every path in the closure to them.
  den.aspects.workstation-desktop.includes = [ den.aspects.flake-registry ];
  den.aspects.desktop-sway.includes = [ den.aspects.flake-registry ];

  perSystem =
    { pkgs, ... }:
    let
      workstation = config.flake.nixosConfigurations.lattitude.config;
      router = config.flake.nixosConfigurations.elitedesk.config;
    in
    {
      checks.flake-registry =
        assert workstation.nix.registry.home-manager.to.path == inputs.home-manager.outPath;
        assert workstation.nix.registry ? nixpkgs && !(workstation.nix.registry ? self);
        assert !workstation.nix.channel.enable;
        assert !(router.nix.registry ? home-manager);
        pkgs.runCommand "flake-registry" { } "touch $out";
    };
}
