{
  config,
  den,
  lib,
  ...
}:
let
  # WHY: separate host fixtures preserve the two independent greetd sessions.
  fixtures = {
    workstation-niri-eval = with den.aspects; [
      workstation-desktop
      desktop-niri-cosmic-fallback
      desktop-media-players
      btrfs-snapper
      safe-mode
      hardware-printer-phoenix-m477
      orca-ide
      t3code
    ];
    workstation-sway-eval = with den.aspects; [
      nixos-base
      desktop-sway
      desktop-media-players
    ];
  };
  destination = [
    "legacyPackages"
    "x86_64-linux"
  ];
in
{
  den.hosts.x86_64-linux = lib.mapAttrs (name: _: {
    intoAttr = destination ++ [ name ];
    users.deepwatrcreatur = { };
  }) fixtures;

  den.aspects = lib.mapAttrs (name: includes: {
    inherit includes;
    nixos = {
      fileSystems."/" = {
        device = "/dev/vda";
        fsType = "btrfs";
      };
      boot.loader.grub.enable = false;
      system.stateVersion = if name == "workstation-niri-eval" then "25.05" else "26.05";
      # WHY: Phoenix opts into the daemon through its developer home profile.
      home-manager.users.deepwatrcreatur = lib.optionalAttrs (name == "workstation-niri-eval") {
        services.t3code.enable = true;
      };
    };
  }) fixtures;

  perSystem = { pkgs, ... }: {
    checks = lib.mapAttrs (
      name: _:
      let
        host = lib.getAttrFromPath (destination ++ [ name ]) config.flake;
        cfg = host.config;
        home = cfg.home-manager.users.deepwatrcreatur;
        common = cfg.xdg.mime.defaultApplications."video/mp4" == "mpv.desktop";
        niri =
          cfg.services.pipewire.alsa.support32Bit
          && cfg.services.printing.enable
          && cfg.programs.niri.enable
          && home.programs.niri.settings.outputs."HDMI-A-1".scale == 1.0
          && home.programs.noctalia.settings.shell.panel.transparency_mode == "solid"
          && cfg.specialisation.cosmic.configuration.services.desktopManager.cosmic.enable
          && !cfg.specialisation.safemode.configuration.services.greetd.enable
          && cfg.services.snapper.configs.root.TIMELINE_LIMIT_HOURLY == 6
          && cfg.hardware.printers.ensureDefaultPrinter == "HP_PageWide_Pro_477dn_MFP_2658C2"
          && cfg.modules.desktop.apps.orca-ide.enable
          && builtins.elem 3773 cfg.networking.firewall.allowedTCPPorts
          && home.services.t3code.tailscale
          && lib.any (lib.hasInfix "--tailscale-serve") (lib.toList home.systemd.user.services.t3code.Service.ExecStart)
          # Review fixes: Ghostty is installed for its binds, and Noctalia's
          # notification layer is hidden from screencasts.
          && lib.any (p: (p.pname or "") == "ghostty") home.home.packages
          && lib.any (
            rule:
            rule.block-out-from or null == "screencast"
            && lib.any (m: builtins.match (m.namespace or "$^") "noctalia-notification" != null) rule.matches
          ) home.programs.niri.settings.layer-rules;
        sway =
          cfg.programs.sway.enable
          && cfg.services.greetd.settings.initial_session.user == "deepwatrcreatur"
          && home.wayland.windowManager.sway.config.modifier == "Mod4";
      in
      assert common && (if name == "workstation-niri-eval" then niri else sway);
      # WHY: force the NixOS and Home Manager closures to evaluate without building them.
      builtins.seq cfg.system.build.toplevel.drvPath (pkgs.runCommand name { } "touch $out")
    ) fixtures
    // {
      # WHY: the fixtures above only evaluate drvPaths, so a package that fails
      # to build (omasnap's sandboxed checkPhase, nch-sny.32) slips through.
      # Build in-repo packages for real.
      omasnap = pkgs.callPackage ./_packages/omasnap.nix { };
    };
  };
}
