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
        ../_hm/workstation-developer/worktrunk.nix
      ];

      programs.nix-index.enable = true;
      programs.nix-index-database.comma.enable = true;
      programs.worktrunk.enable = true;
      programs.hunk-custom.enable = true;
      programs.qmd = {
        enable = true;
        package = inputs.qmd.packages.${system}.default;
      };

      home.packages = with pkgs; [
        cargo
        cargo-binstall
        nodejs
        tuios
      ];
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
}
