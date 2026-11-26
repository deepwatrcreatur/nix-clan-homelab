{
  config,
  den,
  inputs,
  lib,
  ...
}:
let
  name = "phoenix-candidate";
  destination = [
    "legacyPackages"
    "x86_64-linux"
    name
  ];
in
{
  den.hosts.x86_64-linux.${name} = {
    intoAttr = destination;
    users.deepwatrcreatur = { };
  };

  den.aspects.${name} = {
    includes = [ den.aspects.phoenix ];

    nixos = { lib, ... }: {
      imports = [
        {
          # WHY: this fixture is not a Clan machine. Inert paths let the
          # candidate evaluate without reading or decrypting credentials.
          options.clan = lib.mkOption {
            type = lib.types.anything;
            default = { };
          };
          config.clan.core.vars.generators = {
            root-ssh-identity.files.key.path = "/run/secrets/phoenix-candidate/root-ssh-identity/key";
            console-password.files = {
              root.path = "/run/secrets/phoenix-candidate/root-password";
              deepwatrcreatur.path = "/run/secrets/phoenix-candidate/user-password";
            };
            nix-cache-auth.files = {
              attic-token.path = "/run/secrets/phoenix-candidate/attic-token";
              netrc.path = "/run/secrets/phoenix-candidate/nix-ci-netrc";
            };
            nix-remote-builder.files.key.path = "/run/secrets/phoenix-candidate/remote-builder-key";
            synology-shares.files.credentials.path = "/run/secrets/phoenix-candidate/synology-credentials";
            workstation-user-secrets.files =
              lib.genAttrs
                [
                  "anthropic-api-key"
                  "atuin-key-b64"
                  "bitwarden-data"
                  "deepseek-api-key"
                  "gemini-api-key"
                  "github-token"
                  "grok-api-key"
                  "oauth-creds"
                  "openai-api-key"
                  "opencode-zen-api-key"
                  "openrouter-api-key"
                  "rclone-conf"
                  "z-ai-api-key"
                ]
                (name: {
                  path = "/run/secrets/phoenix-candidate/${name}";
                });
          };
        }
      ];
    };
  };

  den.aspects.user-workstation-whitesur.homeManager.imports = [
    inputs.nix-whitesur-config.homeManagerModules.default
    ../modules/_hm/workstation-desktop/desktop-whitesur.nix
  ];

  perSystem =
    { pkgs, ... }:
    let
      host = lib.getAttrFromPath destination config.flake;
      candidate = host.config;
      clanCandidate = config.flake.nixosConfigurations.phoenix.config;
      home = candidate.home-manager.users.deepwatrcreatur;
      inventory = import ../checks/emerald-home-inventory.nix;
      actual = inventory home;
      reference = builtins.fromJSON (builtins.readFile ../checks/phoenix-home-reference.json);
      expected = builtins.fromJSON (builtins.readFile ../checks/phoenix-home-expected-differences.json);
      differences = lib.mapAttrs (category: names: {
        missing = lib.subtractLists names reference.${category};
        extra = lib.subtractLists reference.${category} names;
      }) actual;
    in
    {
      legacyPackages.phoenixHomeInventory = actual;

      checks.phoenix-home-parity =
        if differences == expected then
          pkgs.runCommand "phoenix-home-parity" { } "touch $out"
        else
          throw "Phoenix Home Manager differences changed. Observed: ${builtins.toJSON differences}";

      checks.phoenix-candidate =
        assert candidate.networking.hostName == "phoenix";
        assert candidate.system.stateVersion == "25.05";
        assert candidate.boot.loader.limine.enable;
        assert
          candidate.boot.loader.limine.biosDevice
          == "/dev/disk/by-id/nvme-TEAM_TM8FPK002T_TPBF2401080020300197";
        assert candidate.boot.loader.limine.partitionIndex == 3;
        assert candidate.boot.loader.limine.efiInstallAsRemovable;
        assert candidate.boot.loader.limine.biosSupport;
        assert !candidate.boot.loader.efi.canTouchEfiVariables;
        assert
          builtins.sort builtins.lessThan candidate.boot.kernelModules == [
            "amdgpu"
            "atkbd"
            "br_netfilter"
            "bridge"
            "ctr"
            "kvm-amd"
            "loop"
            "veth"
            "xt_nat"
          ];
        assert
          builtins.sort builtins.lessThan candidate.boot.kernelParams == [
            "amdgpu.gfxoff=0"
            "amdgpu.runpm=0"
            "loglevel=4"
            "lsm=landlock,yama,bpf"
            "pcie_aspm=off"
            "root=fstab"
            "usbcore.autosuspend=-1"
          ];
        assert candidate.fileSystems."/".device == "/dev/disk/by-partlabel/disk-main-root";
        assert candidate.fileSystems."/".fsType == "btrfs";
        assert candidate.fileSystems."/boot".device == "/dev/disk/by-partlabel/disk-main-ESP";
        assert candidate.fileSystems."/boot".fsType == "vfat";
        assert candidate.fileSystems."/scratch".device == "/dev/disk/by-label/scratch";
        assert candidate.fileSystems."/data".device == "/dev/disk/by-label/data";
        assert candidate.fileSystems."/cloud".device == "//10.10.11.88/cloud";
        assert candidate.fileSystems."/storage".device == "//10.10.11.88/storage";
        assert lib.all (share: lib.elem "x-systemd.automount" candidate.fileSystems.${share}.options) [
          "/cloud"
          "/storage"
        ];
        assert candidate.networking.networkmanager.enable;
        assert
          candidate.networking.firewall.allowedTCPPorts == [
            22
            631
            3773
            5201
            24800
          ];
        assert candidate.services.tailscale.enable;
        assert candidate.services.printing.enable;
        assert candidate.programs.niri.enable;
        assert candidate.services.greetd.enable;
        assert candidate.services.omarchy-screen-mirroring.enable;
        assert candidate.services.omarchy-iphone-mirror.enable;
        assert candidate.services.flatpak.enable;
        assert (builtins.head candidate.nix.buildMachines).hostName == "10.10.11.55";
        assert candidate.nix.settings.netrc-file == "/run/secrets/phoenix-candidate/nix-ci-netrc";
        assert
          candidate.clan.core.vars.generators.workstation-user-secrets.files.rclone-conf.path
          == "/run/secrets/phoenix-candidate/rclone-conf";
        assert candidate.programs.strata.enable;
        assert home.programs.firefox.enable;
        assert home.programs.google-chrome.enable;
        assert home.programs.herdr.desktopApp.enable;
        assert home.programs.noctalia.enable;
        assert home.programs.vicinae.enable;
        builtins.seq candidate.system.build.toplevel.drvPath (
          pkgs.runCommand "phoenix-candidate" { } "touch $out"
        );

      checks.phoenix-clan-candidate =
        assert config.homelab.hosts.phoenix.clanCandidate;
        assert !config.homelab.hosts.phoenix.migrated;
        assert builtins.hasAttr "phoenix" config.flake.clan.inventory.machines;
        assert clanCandidate.networking.hostName == "phoenix";
        assert clanCandidate.system.stateVersion == "25.05";
        assert clanCandidate.boot.loader.limine.enable;
        assert
          clanCandidate.boot.loader.limine.biosDevice
          == "/dev/disk/by-id/nvme-TEAM_TM8FPK002T_TPBF2401080020300197";
        assert clanCandidate.fileSystems."/cloud".device == "//10.10.11.88/cloud";
        assert clanCandidate.fileSystems."/storage".device == "//10.10.11.88/storage";
        pkgs.runCommand "phoenix-clan-candidate" { } "touch $out";
    };
}
