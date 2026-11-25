{ den, inputs, ... }:
{
  den.aspects.phoenix = {
    includes = with den.aspects; [
      nixos-base
      console-password
      nix-cache-auth
      remote-builder-client
      workstation-desktop
      desktop-niri-cosmic-fallback
      desktop-network-shares
      desktop-media-players
      hardware-printer-phoenix-m477
      btrfs-snapper
      safe-mode
      synology-shares
      workstation-user-secrets
      rclone-client
      vpn-unlimited-client
      mega-vpn-client
      workstation-herdr-mobile
      orca-ide
      t3code
    ];

    nixos = { lib, ... }: {
      system.stateVersion = lib.mkForce "25.05";

      imports = [
        inputs.clan-core.inputs.disko.nixosModules.disko
        inputs.strata.nixosModules.default
        inputs.nix-omarchy-screen-mirroring.nixosModules.default
        inputs.nix-omarchy-iphone-mirror.nixosModules.default
        ../../machines/phoenix-disko.nix
        ../../machines/phoenix-hardware.nix
        ../../machines/phoenix-networking.nix
        {
          services.omarchy-screen-mirroring.enable = true;
          services.omarchy-iphone-mirror.enable = true;
        }
        {
          boot.loader = {
            systemd-boot.enable = lib.mkForce false;
            limine = {
              enable = lib.mkForce true;
              efiInstallAsRemovable = true;
              biosSupport = true;
              biosDevice = "/dev/disk/by-id/nvme-TEAM_TM8FPK002T_TPBF2401080020300197";
              partitionIndex = 3;
            };
            efi.canTouchEfiVariables = lib.mkForce false;
          };
        }
      ];
    };
    provides.deepwatrcreatur.includes = with den.aspects; [
      user-workstation-shell
      user-workstation-developer
      user-workstation-desktop
      user-workstation-whitesur
    ];

    provides.deepwatrcreatur.homeManager.home.stateVersion = "25.11";
  };

}
