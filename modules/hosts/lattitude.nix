{ config, den, inputs, lib, ... }:
{
  den.aspects.lattitude = {
    includes = with den.aspects; [
      nixos-base
      console-password
      nix-cache-auth
      remote-builder-client
      desktop-network-shares
      desktop-sway
      desktop-media-players
      hardware-printer-phoenix-m477
      btrfs-snapper
      synology-shares
      workstation-user-secrets
    ];

    provides.deepwatrcreatur.includes = with den.aspects; [
      user-workstation-shell
      user-workstation-developer
      user-workstation-desktop
    ];

    nixos =
      { lib, pkgs, ... }:
      {
        imports = [
          inputs.clan-core.inputs.disko.nixosModules.disko
          inputs.strata.nixosModules.default
          ../../machines/lattitude/disko.nix
          ../../machines/lattitude/hardware-configuration.nix
          ../../machines/lattitude/networking.nix
        ];

        environment.systemPackages = with pkgs; [
          google-chrome
          firefox
          vivaldi
          thunderbird
          rclone
          epiphany
          inputs.nightscout-tui.packages.${stdenv.hostPlatform.system}.default
        ];

        programs.strata.defaultFileManager = true;

        # Preserve the active remote-access path on Lattitude.
        services.tailscale.enable = true;

        # WHY: keep Lattitude's current network-online ordering for remote builds and CIFS automounts.
        systemd.network.wait-online.enable = lib.mkForce true;

        zramSwap.enable = true;
        time.timeZone = "America/Toronto";
        i18n.defaultLocale = "en_CA.UTF-8";

        boot.loader.systemd-boot.enable = lib.mkDefault true;
        boot.loader.efi.canTouchEfiVariables = lib.mkDefault true;

        services.logind = {
          settings.Login = {
            HandleLidSwitch = "ignore";
            HandleLidSwitchDocked = "ignore";
            HandleLidSwitchExternalPower = "ignore";
            HandlePowerKey = "poweroff";
            IdleAction = "ignore";
            IdleActionSec = "0";
          };
        };
        systemd.targets = lib.genAttrs [ "sleep" "suspend" "hibernate" "hybrid-sleep" ] (_: {
          enable = false;
        });

        system.stateVersion = "26.05";
      };
  };

  perSystem = { pkgs, ... }:
    let
      candidate = config.flake.nixosConfigurations.lattitude.config;
      shareMount = share: candidate.fileSystems."/${share}";
      credentialsPath = candidate.clan.core.vars.generators.synology-shares.files.credentials.path;
      hasShare = share:
        let mount = shareMount share;
        in mount.device == "//10.10.11.88/${share}"
          && mount.fsType == "cifs"
          && lib.elem "x-systemd.automount" mount.options
          && lib.elem "credentials=${credentialsPath}" mount.options;
    in
    {
      checks.lattitude-host =
        assert builtins.hasAttr "lattitude" config.clan.inventory.machines;
        assert candidate.networking.hostName == "lattitude";
        assert candidate.system.stateVersion == "26.05";
        assert candidate.boot.loader.systemd-boot.enable;
        assert candidate.programs.sway.enable;
        assert candidate.programs.strata.defaultFileManager;
        assert hasShare "cloud" && hasShare "storage";
        assert candidate.services.greetd.settings.initial_session.user == "deepwatrcreatur";
        assert candidate.home-manager.users.deepwatrcreatur.programs.worktrunk.enable;
        assert candidate.home-manager.users.deepwatrcreatur.programs.bitwarden-cli.enable;
        builtins.seq candidate.system.build.toplevel.drvPath
          (pkgs.runCommand "lattitude-host" { } "touch $out");
    };
}
