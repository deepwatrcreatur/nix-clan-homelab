{ inputs }:
{
  pkgs,
  lib,
  ...
}:

{
  imports = [
    inputs.nix-snapd.nixosModules.default
    inputs.nix-linuxbrew.nixosModules.default
    inputs.openlogi.nixosModules.default
    ./snap.nix
    ./keyboard-glitches.nix
  ];

  services.tailscale.enable = true;
  virtualisation.docker = {
    enable = true;
    package = pkgs.docker_29;
  };

  programs.linuxbrew = {
    enableSystemSetup = true;
    owner = "deepwatrcreatur";
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.limine.enable = false;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.bootspec.enable = true;
  boot.growPartition = true;
  boot.loader.timeout = 7;
  boot.loader.systemd-boot.consoleMode = "auto";

  boot.kernelModules = [ "amdgpu" ];
  # WHY: disabling power gating, runtime PM and ASPM avoids RX 6600 reset
  # failures and a black screen with PCIe passthrough.
  boot.kernelParams = [
    "amdgpu.gfxoff=0"
    "amdgpu.runpm=0"
    "pcie_aspm=off"
  ];
  boot.blacklistedKernelModules = [
    "virtio_gpu"
    "bochs_drm"
    "qxl"
  ];

  hardware.enableRedistributableFirmware = true;
  hardware.nvidia.open = false;

  services.xserver = {
    videoDrivers = [ "amdgpu" ];
    xkb.options = "caps:none";
  };
  hardware.graphics = {
    enable = true;
    extraPackages = [ pkgs.rocmPackages.clr.icd ];
  };

  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;

    extraConfig.pipewire."92-low-latency" = {
      "context.properties" = {
        "default.clock.rate" = 48000;
        "default.clock.quantum" = 1024;
      };
    };

    extraConfig.pipewire-pulse."99-no-flat-volume" = {
      "pulse.properties" = {
        "pulse.flat-volume" = false;
      };
    };
  };

  services.orca.enable = false;
  services.speechd.enable = false;

  services.openssh.enable = true;
  services.openssh.settings.AcceptEnv = [
    "LANG"
    "LC_*"
    "COLORTERM"
    "TERM_PROGRAM"
    "TERM_PROGRAM_VERSION"
  ];
  services.logind.settings.Login.HandleLidSwitch = "ignore";
  security.sudo.wheelNeedsPassword = false;

  # WHY: Bash remains the login shell for noninteractive SSH commands.
  custom.fishInteractiveShell.users = [ "deepwatrcreatur" ];

  users.users.deepwatrcreatur = {
    isNormalUser = true;
    extraGroups = [
      "networkmanager"
      "wheel"
      "lp"
      "docker"
      "video"
      "render"
    ];
  };

  services.displayManager.autoLogin.enable = true;
  services.displayManager.autoLogin.user = "deepwatrcreatur";

  services.printing.enable = true;

  environment.systemPackages = with pkgs; [
    at-spi2-core
    baobab
    bubblewrap
    celluloid
    deluge
    distrobox
    dosfstools
    ffmpeg
    ffmpegthumbnailer
    filezilla
    gnome-disk-utility
    gparted
    mpv
    nautilus
    nushell
    nvtopPackages.amd
    parted
    pavucontrol
    rclone-browser
    remmina
    realvnc-vnc-viewer
    transmission_4-gtk
    usbutils
    vlc
    vscode.fhs
    inputs.strata.packages.${pkgs.stdenv.hostPlatform.system}.default
    inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.default
    xdg-desktop-portal-gtk
    satty
    (pkgs.callPackage ../_packages/omasnap.nix { })
    gthumb
    ventoy-full
    wiremix
    yt-dlp
    vivaldi
  ];

  programs.nix-ld.enable = true;
  virtualisation.podman.enable = true;
  services.qemuGuest.enable = true;

  programs.openlogi.enable = true;
  systemd.user.services.openlogi-agent.environment.LD_LIBRARY_PATH = lib.makeLibraryPath [
    pkgs.wayland
    pkgs.libxkbcommon
    pkgs.vulkan-loader
    pkgs.libGL
  ];

  users.users.deepwatrcreatur.linger = true;

  myModules.snap = {
    enable = true;
    classicPackages = [ "icloud-for-linux" ];
  };

  myModules.keyboardGlitches.enable = true;

  nix.settings.fallback = true;
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.permittedInsecurePackages = [
    "ventoy-1.1.12"
  ];

  home-manager.backupFileExtension = "hm-backup";
  services.resolved.enable = true;
  system.stateVersion = lib.mkDefault "25.05";
}
