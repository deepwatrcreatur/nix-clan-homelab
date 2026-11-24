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

    # WHY: compare PVE-Strix against Unified main without changing other
    # hosts' shared inventory reference during this standalone-home migration.
    unified-pve = {
      url = "github:deepwatrcreatur/unified-nix-configuration/2eccceae94485ecfd2d72cc5fb1c1adabe613e72";
      flake = false;
    };

    nix-router-optimized = {
      url = "github:deepwatrcreatur/nix-router-optimized/6e1779bac560fcb63465c699985f997dfd234ad4";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    den.url = "github:denful/den/latest";
    import-tree.url = "github:vic/import-tree";

    # Migration only (nch-sny.3): agenix secrets keep working beside clan vars.
    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";

    # nch-sny.5: magic rollback for deploys that cut off their own access.
    deploy-rs.url = "github:serokell/deploy-rs";
    deploy-rs.inputs.nixpkgs.follows = "nixpkgs";

    niri = {
      url = "github:sodiboo/niri-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    noctalia = {
      url = "github:noctalia-dev/noctalia";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    zen-browser = {
      url = "github:youwen5/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-snapd = {
      url = "github:nix-community/nix-snapd";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-linuxbrew = {
      url = "github:deepwatrcreatur/nix-linuxbrew/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nightscout-tui = {
      url = "github:deepwatrcreatur/nightscout-tui";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };

    openlogi = {
      url = "github:AprilNEA/OpenLogi";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-utils.url = "github:numtide/flake-utils";

    strata = {
      url = "github:deepwatrcreatur/nix-strata-filemanager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };

    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    dmux-flake = {
      url = "github:deepwatrcreatur/nix-dmux";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    fnox = {
      url = "github:deepwatrcreatur/fnox-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # WHY: Unified's Proxmox profile needs the newer SSH identity options;
    # keep that revision scoped to this transitional home, not other hosts.
    fnox-pve = {
      url = "github:deepwatrcreatur/fnox-flake/2ad72d7bd60d7fded65f9b0fc164ece2fd9c7230";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    herdr.url = "github:herdrdev/herdr/v0.9.5";

    hunk = {
      url = "github:modem-dev/hunk";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    jj-starship = {
      url = "github:dmmulroy/jj-starship/v0.7.1";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    leaf = {
      url = "github:DeepanshuMishraa/leaf";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    llm-agents.url = "github:numtide/llm-agents.nix";

    # WHY: the Herdr desktop and backend use a separate upstream pin and
    # package set, matching the prebuilt packages used by unified.
    llm-agents-herdr-app.url = "github:numtide/llm-agents.nix";

    nix-cmux-tui = {
      url = "github:deepwatrcreatur/nix-cmux-tui";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-deepseek-harness = {
      url = "github:deepwatrcreatur/nix-deepseek-harness";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-frankenterm = {
      url = "github:deepwatrcreatur/nix-frankenterm";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # WHY: the standalone Proxmox root profile imports these Home Manager modules.
    nix-attic-infra = {
      url = "github:deepwatrcreatur/nix-attic-infra";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    ssh-keys-manager = {
      url = "github:deepwatrcreatur/nix-ssh-keys-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-markit = {
      url = "github:deepwatrcreatur/nix-markit";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-rtk = {
      url = "github:deepwatrcreatur/nix-rtk";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.llm-agents.follows = "llm-agents";
    };

    plasma-manager = {
      url = "github:pjones/plasma-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    qmd = {
      url = "github:tobi/qmd";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };

    zellij-vivid-rounded = {
      url = "github:deepwatrcreatur/nix-zellij-vivid-rounded";
      inputs.nixpkgs.follows = "nixpkgs";
    };
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
