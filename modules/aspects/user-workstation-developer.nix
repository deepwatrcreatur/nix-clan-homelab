{ inputs, ... }:
{
  den.aspects.user-workstation-developer.homeManager =
    { config, lib, pkgs, ... }:
    let
      home = config.home.homeDirectory;
      system = pkgs.stdenv.hostPlatform.system;
    in
    {
      imports = [
        inputs.nix-index-database.homeModules.nix-index
        inputs.qmd.homeModules.default
        (import ../_hm/workstation-developer/hunk.nix { inherit (inputs) hunk; })
        (import ../_hm/workstation-developer/herdr.nix { inherit (inputs) herdr llm-agents-herdr-app; })
        ../_hm/workstation-developer/cass-session-search.nix
        ../_hm/workstation-developer/repo-updater.nix
        ../_hm/workstation-developer/worktrunk.nix
        ../_hm/t3code-daemon.nix
      ];

      options.programs = {
        beads.enable = lib.mkEnableOption "Beads issue tracking";
        cmux-tui.enable = lib.mkEnableOption "cmux-tui";
        dmux.enable = lib.mkEnableOption "dmux";
        frankenterm.enable = lib.mkEnableOption "FrankenTerm";
        orca-ide.enable = lib.mkEnableOption "Orca IDE";
      };

      config = {
        programs.nix-index.enable = true;
        programs.nix-index-database.comma.enable = true;
        programs.worktrunk.enable = true;
        programs.hunk-custom.enable = true;
        programs.cass-session-search.enable = true;
        programs.beads.enable = true;
        programs.repo-updater.enable = true;
        programs.orca-ide.enable = true;
        programs.t3code = {
          enable = true;
          package = pkgs.callPackage ../_packages/t3code.nix { };
        };
        services.t3code.enable = true;
        programs.herdr.enable = true;
        programs.cmux-tui.enable = true;
        programs.dmux.enable = true;
        programs.frankenterm.enable = true;
        programs.qmd = {
          enable = true;
          package = inputs.qmd.packages.${system}.default;
        };

        home.packages = with pkgs; [
          cargo
          cargo-binstall
          nodejs
          tuios
        ]
        ++ lib.optional config.programs.cmux-tui.enable inputs.nix-cmux-tui.packages.${system}.default
        ++ lib.optional config.programs.beads.enable (pkgs.callPackage ../_packages/beads-rust.nix { })
        ++ lib.optional config.programs.orca-ide.enable (pkgs.callPackage ../_packages/orca-ide.nix { })
        ++ lib.optional config.programs.dmux.enable inputs.dmux-flake.packages.${system}.default
        ++ lib.optional config.programs.frankenterm.enable inputs.nix-frankenterm.packages.${system}.default;
        home.file.".npmrc".text = ''
          prefix=${home}/.npm-global
          cache=${home}/.npm-cache
          init-author-name=Anwer Khan
          init-author-email=deepwatrcreatur@gmail.com
          init-license=MIT
        '';
        home.sessionPath = [ "${home}/.npm-global/bin" ];
        home.activation.createNpmDirectories = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          run mkdir -p ${lib.escapeShellArg "${home}/.npm-global"} ${lib.escapeShellArg "${home}/.npm-cache"}
        '';
      };
    };
}
