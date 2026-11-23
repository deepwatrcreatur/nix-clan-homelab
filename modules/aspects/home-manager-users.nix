# Shared Home Manager settings for fleet machines.
# Ported from unified den/aspects/home-manager-users.nix.
{ den, inputs, ... }:
{
  den.aspects.home-manager-users.nixos =
    { lib, pkgs, ... }:
    {
      home-manager = {
        useGlobalPkgs = lib.mkDefault true;
        useUserPackages = lib.mkDefault true;
        backupFileExtension = lib.mkDefault "bak";
      };

      # WHY: root and workstation Home Manager activations communicate with nix-daemon.
      systemd.services = {
        "home-manager-root".environment.NIX_REMOTE = "daemon";
        "home-manager-deepwatrcreatur".environment.NIX_REMOTE = "daemon";
      };

      # WHY: Unified has a managed root profile on NixOS hosts; keep its
      # non-secret operator tools available while the user profile moves to Clan.
      home-manager.users.root = {
        imports = [
          ../_hm/emerald-shell/git-ssh-signing.nix
          ../_hm/workstation-desktop/fastfetch.nix
          inputs.zellij-vivid-rounded.homeManagerModules.default
        ];

        home.username = "root";
        home.homeDirectory = "/root";
        home.stateVersion = lib.mkDefault "25.11";
        home.packages = with pkgs; [ fish lsd sops ];
        home.file.".terminfo" = {
          source = ../_hm/emerald-shell/terminfo;
          recursive = true;
        };

        programs = {
          fish.enable = true;
          git = {
            enable = true;
            settings.user = {
              name = "Anwer Khan";
              email = "deepwatrcreatur@gmail.com";
            };
          };
          home-manager.enable = true;
          fastfetch-custom.enable = true;
          zellij-vivid-rounded.enable = true;
        };
      };
    };
}
