{
  description = "Homelab NixOS fleet on Clan, composed from den aspects";

  inputs = {
    # WHY: track clan's release branch; nixpkgs follows clan's pin so clan's
    # modules and CLI are tested against the same package set.
    clan-core.url = "git+https://git.clan.lol/clan/clan-core?ref=26.05";
    nixpkgs.follows = "clan-core/nixpkgs";

    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";

    # WHY: compare inventory with unified during migration by importing its data files.
    unified = {
      url = "github:deepwatrcreatur/unified-nix-configuration";
      flake = false;
    };

    den.url = "github:denful/den/latest";
    import-tree.url = "github:vic/import-tree";

    # Migration only (nch-sny.3): agenix secrets keep working beside clan vars.
    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";

    # nch-sny.5: magic rollback for deploys that cut off their own access.
    deploy-rs.url = "github:serokell/deploy-rs";
    deploy-rs.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" ];
      # Every .nix file under modules/ is a flake-parts module (dendritic
      # layout). GOTCHA: import-tree skips paths with a component starting "_".
      imports = [ (inputs.import-tree ./modules) ];
    };
}
