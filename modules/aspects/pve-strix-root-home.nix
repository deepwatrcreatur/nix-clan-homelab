{ den, inputs, ... }:
let
  system = "x86_64-linux";
  # WHY: keep Unified's fnox module revision local to this transitional home.
  proxmoxInputs = inputs // {
    fnox = inputs.fnox-pve;
  };
  proxmoxPkgs = import inputs.nixpkgs {
    inherit system;
    config.allowUnfree = true;
    overlays = [
      (final: prev: {
        fnox = inputs.fnox-pve.packages.${system}.default;
        markit = inputs.nix-markit.packages.${system}.markit;
        leaf = inputs.leaf.packages.${system}.default;
      })
    ]
    ++ import (inputs.unified-pve.outPath + "/overlays/packages.nix") {
      nixpkgsLib = inputs.nixpkgs.lib;
    };
  };
in
{
  den.homes.${system}."root@pve-strix" = {
    pkgs = proxmoxPkgs;
    instantiate =
      { pkgs, modules, ... }:
      inputs.home-manager.lib.homeManagerConfiguration {
        inherit pkgs modules;
        extraSpecialArgs = {
          inputs = proxmoxInputs;
          hostName = "pve-strix";
          isDesktop = false;
        };
      };
  };

  den.aspects."root@pve-strix".includes = [ den.batteries.define-user ];

  den.aspects.root.homeManager =
    { lib, ... }:
    {
      # WHY: retain the Proxmox root home path while this standalone output
      # replaces Unified's profile; the system configuration remains in Unified.
      home.homeDirectory = lib.mkForce "/root";
      # WHY: Home Manager treats even an empty DRY_RUN variable as dry-run
      # mode. The upstream compatibility workaround would skip managed links.
      home.activation.ensureDryRunVariable = lib.mkForce (lib.hm.dag.entryBefore [ "attic-config" ] ":");
      imports = [
        (inputs.unified-pve.outPath + "/users/root")
        (inputs.unified-pve.outPath + "/modules/home-manager")
        (inputs.unified-pve.outPath + "/profiles/home-manager/proxmox-root.nix")
      ];
    };
}
