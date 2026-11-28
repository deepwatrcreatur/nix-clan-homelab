{ den, inputs, ... }:
{
  den.aspects.phoenix = {
    includes = with den.aspects; [
      nixos-base
      console-password
      nix-cache-auth
      remote-builder-client
      linuxbrew
      workstation-desktop
      desktop-niri-cosmic-fallback
      desktop-network-shares
      desktop-media-players
      hardware-printer-phoenix-m477
      btrfs-snapper
      safe-mode
      root-ssh-identity
      synology-shares
      workstation-user-secrets
      rclone-client
      vpn-unlimited-client
      mega-vpn-client
      workstation-herdr-mobile
      orca-ide
      t3code
    ];

    nixos = { lib, pkgs, ... }: {
      system.stateVersion = lib.mkForce "25.05";
      environment.systemPackages = [
        pkgs.graphite-cli
        pkgs.wezterm
        inputs.nix-iodyne.packages.${pkgs.stdenv.hostPlatform.system}.default
        inputs.nix-lazyrsync.packages.${pkgs.stdenv.hostPlatform.system}.default
        inputs.nix-lightpanda.packages.${pkgs.stdenv.hostPlatform.system}.lightpanda
      ];

      imports = [
        inputs.clan-core.inputs.disko.nixosModules.disko
        inputs.nixbit.nixosModules.nixbit
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

      nixbit = {
        enable = true;
        repository = "https://github.com/deepwatrcreatur/unified-nix-configuration.git";
        forceAutostart = true;
      };
    };
    provides.deepwatrcreatur.includes = with den.aspects; [
      user-workstation-shell
      user-workstation-developer
      user-workstation-desktop
      user-workstation-whitesur
    ];

    provides.deepwatrcreatur.homeManager.home.stateVersion = "25.11";

    provides.deepwatrcreatur.homeManager.home.file.".config/wezterm/wezterm.lua".text = ''
      local wezterm = require 'wezterm'
      local config = wezterm.config_builder()

      config.font = wezterm.font('JetBrains Mono', { weight = 'Regular' })
      config.font_size = 16.0
      config.window_background_opacity = 1.0
      config.window_decorations = 'RESIZE'
      config.window_close_confirmation = 'AlwaysPrompt'
      config.adjust_window_size_when_changing_font_size = false
      config.enable_tab_bar = false
      config.hide_tab_bar_if_only_one_tab = true
      config.tab_bar_at_bottom = false
      config.scrollback_lines = 5000

      config.colors = {
        foreground = "#db7ddd",
        background = "#111147",
        cursor_bg = "#53b397",
        cursor_fg = "#53b397",
        cursor_border = "#53b397",
        selection_bg = "#5ca8dc",
        selection_fg = "#d0beee",
        ansi = {
          "#111147",
          "#5ca8dc",
          "#53b397",
          "#249a84",
          "#db7ddd",
          "#d0beee",
          "#f9f3f9",
          "#a175d4",
        },
        brights = {
          "#111147",
          "#5cb5dc",
          "#52deb5",
          "#01f5c7",
          "#fa5dfd",
          "#c6a5fd",
          "#ffffff",
          "#b577fd",
        },
      }

      config.keys = {
        { key = 'q', mods = 'CTRL', action = wezterm.action.ToggleFullScreen },
        { key = '"', mods = 'CTRL', action = wezterm.action.ClearScrollback 'ScrollbackAndViewport' },
      }

      return config
    '';
  };

}
