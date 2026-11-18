{
  description = "Homelab NixOS fleet on Clan, composed from den aspects";

  inputs = {
    # WHY: track clan's release branch; nixpkgs follows clan's pin so clan's
    # modules and CLI are tested against the same package set.
    clan-core.url = "git+https://git.clan.lol/clan/clan-core?ref=26.05";
    nixpkgs.follows = "clan-core/nixpkgs";

    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";

    den.url = "github:denful/den/latest";
    import-tree.url = "github:vic/import-tree";

    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" ];
      # Every file under modules/ is a flake-parts module (dendritic layout).
      imports = [ (inputs.import-tree ./modules) ];
    };
}
