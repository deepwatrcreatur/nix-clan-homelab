{ config, den, inputs, lib, ... }:
let
  name = "lattitude-eval";
  destination = [ "legacyPackages" "x86_64-linux" name ];
in
{
  den.hosts.x86_64-linux.${name} = {
    intoAttr = destination;
    users.deepwatrcreatur = { };
  };

  den.aspects.${name} = {
    includes = with den.aspects; [
      nixos-base
      desktop-sway
      desktop-media-players
    ];
    provides.deepwatrcreatur = {
      includes = [ den.aspects.user-workstation-shell ];
      homeManager = { pkgs, ... }: {
        imports = [ ./_hm/workstation-developer/worktrunk.nix ];
        home.stateVersion = "26.05";
        home.packages = with pkgs; [
          epiphany
          firefox
          google-chrome
          rclone
          thunderbird
          vivaldi
        ];
        programs.worktrunk.enable = true;
      };
    };
    nixos = { lib, ... }: {
      imports = [
        inputs.clan-core.inputs.disko.nixosModules.disko
        ../checks/lattitude/disko.nix
        ../checks/lattitude/hardware-configuration.nix
        ../checks/lattitude/networking.nix
        (import ./_nixos/synology-share-mounts.nix {
          credentialsPath = "/run/secrets/synology-shares/credentials";
        })
      ];
      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;
      i18n.defaultLocale = "en_CA.UTF-8";
      time.timeZone = "America/Toronto";
      system.stateVersion = "26.05";
      zramSwap.enable = true;
      # WHY: the kiosk display must survive a closed lid or idle session.
      services.logind.settings.Login = {
        HandleLidSwitch = "ignore";
        HandleLidSwitchDocked = "ignore";
        HandleLidSwitchExternalPower = "ignore";
        HandlePowerKey = "poweroff";
        IdleAction = "ignore";
        IdleActionSec = "0";
      };
      systemd.targets = lib.genAttrs [ "sleep" "suspend" "hibernate" "hybrid-sleep" ] (_: {
        enable = false;
      });
    };
  };

  perSystem = { pkgs, ... }:
    let
      candidate = (lib.getAttrFromPath destination config.flake).config;
      home = candidate.home-manager.users.deepwatrcreatur;
    in
    {
      checks.lattitude-kiosk =
        assert !builtins.hasAttr name config.flake.nixosConfigurations;
        assert candidate.networking.hostName == "lattitude";
        assert candidate.systemd.network.networks."10-realtek-eth".address == [ "10.10.11.47/16" ];
        assert candidate.fileSystems."/boot".fsType == "vfat";
        assert lib.all (target: candidate.fileSystems.${target}.fsType == "btrfs")
          [ "/" "/home" "/nix" "/.snapshots" ];
        assert candidate.boot.loader.systemd-boot.enable;
        assert lib.all (share:
          let mount = candidate.fileSystems."/${share}"; in
          mount.device == "//10.10.11.88/${share}"
          && mount.fsType == "cifs"
          && lib.elem "x-systemd.automount" mount.options
          && lib.elem "credentials=/run/secrets/synology-shares/credentials" mount.options
        ) [ "cloud" "storage" ];
        assert candidate.services.greetd.settings.initial_session.user == "deepwatrcreatur";
        assert candidate.programs.sway.enable;
        assert !candidate.systemd.targets.suspend.enable && candidate.zramSwap.enable;
        assert home.programs.worktrunk.enable && home.home.stateVersion == "26.05";
        builtins.seq candidate.system.build.toplevel.drvPath
          (pkgs.runCommand "lattitude-kiosk" { } "touch $out");
    };
}
