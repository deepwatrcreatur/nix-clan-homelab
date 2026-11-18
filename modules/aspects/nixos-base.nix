# Baseline NixOS configuration shared by all fleet hosts.
# Ported from unified den/aspects/nixos-base.nix, folding in the initial base aspect.
{ den, ... }:
{
  den.aspects.nixos-base = {
    includes = [ den.aspects.home-manager-users ];

    nixos =
      { config, lib, pkgs, ... }:
      {
        imports = [
          ../_nixos/fish-interactive-bash-login.nix
          ../_nixos/dev-tools.nix
          ../_nixos/nix-tools.nix
          ../_nixos/utility-packages.nix
        ];

        time.timeZone = lib.mkDefault "America/Toronto";
        i18n.defaultLocale = lib.mkDefault "en_US.UTF-8";
        i18n.extraLocales = [
          "en_US.UTF-8/UTF-8"
          "en_CA.UTF-8/UTF-8"
        ];

        services.openssh.enable = true;
        # WHY: operators log in with SSH keys only and have no password, so
        # wheel must not need one (same policy as unified's hosts).
        security.sudo.wheelNeedsPassword = false;

        nixpkgs.config.allowUnfree = true;

        nix.settings = {
          experimental-features = [
            "nix-command"
            "flakes"
            "impure-derivations"
            "ca-derivations"
            "pipe-operators"
          ];

          download-buffer-size = 1048576000;
          http-connections = 50;
          max-jobs = "auto";
          cores = 0;
          builders-use-substitutes = true;
          keep-outputs = true;
          keep-derivations = true;

          show-trace = true;
          warn-dirty = false;
          flake-registry = "";

          trusted-users = [
            "root"
            "@wheel"
          ];

          substituters = [
            "http://attic-cache:5001/cache-local"
            "http://10.10.11.55:5001/cache-local"
            "https://cache.nix-ci.com"
            "https://cache.nixos.org"
            "https://cache.numtide.com"
            "https://nix-community.cachix.org/"
            "https://hyprland.cachix.org/"
          ];

          trusted-public-keys = [
            "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
            "cache-local:pTXNNDRUFiGxQZmx7SAN4Pl82mDrZcbVq7H5nyFXfM8="
            "cache-local:GozZz7XFsUZ7xI5o/Q36JA/BFfjzONWOjiqC+zAhp2g="
            "nix-ci:g3xV5BDTLtIBZr/A00IU1x0EtKKlb7YLgBN2SgYgM6A="
            "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
            "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
            "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
          ];

          # Cache credentials: the nix-cache-auth aspect, included per host.
          # TODO(nch-sny.11): declarative root / user passwords via agenix/clan vars
        };

        programs.fish.enable = true;

        environment.etc."gitconfig".text = ''
          [url "ssh://git@github.com/"]
            insteadOf = https://github.com/
          [url "https://github.com/Homebrew/"]
            insteadOf = https://github.com/Homebrew/
        '';

        programs.nh = {
          enable = true;
          clean.enable = true;
          clean.extraArgs = "--keep-since 4d --keep 3";
        };

        services.fstrim = {
          enable = lib.mkDefault true;
          interval = lib.mkDefault "weekly";
        };

        services.earlyoom = {
          enable = true;
          freeMemThreshold = 5;
          freeSwapThreshold = 10;
          enableNotifications = false;
          extraArgs = [
            "--avoid"
            "^(sshd)$"
          ];
        };

        zramSwap.enable = lib.mkDefault true;
      };
  };

  # WHY: hosts written against the spike's `base` aspect keep evaluating.
  den.aspects.base = den.aspects.nixos-base;
}
