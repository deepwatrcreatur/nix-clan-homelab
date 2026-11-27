# ASRock Z170 Gaming-ITX/ac (i7, 32 GB, UEFI), two igc 2.5 GbE ports and an
# onboard e1000e. Installed by unified; joined clan as a VRRP member
# (nch-sny.36.6, docs/router-vrrp.md).
{ den, ... }:
{
  den.aspects.router = {
    # SECURITY: routers receive only the NixCI user-cache token, not the
    # Attic push token or Emerald builder key.
    includes = with den.aspects; [
      nixos-base
      console-password
      router-role
      nix-ci-cache-auth
    ];
    nixos =
      { config, lib, ... }:
      {
        imports = [ ../../machines/router/disko.nix ];
        # INVARIANT: the stateVersion router was installed with (unified).
        system.stateVersion = "25.05";

        # WHY: unified boots router with Limine from the 1 GB ESP at /boot;
        # switching boot loaders on a live router is its own change.
        boot.loader = {
          grub.enable = false;
          limine.enable = true;
          efi.canTouchEfiVariables = false;
        };
        boot.kernelParams = [
          # WHY: serial console for recovery without a monitor.
          "console=ttyS0,115200"
          # WHY: Energy Efficient Ethernet on the I225/I226-V caused link
          # flaps and drops (unified hardware-configuration.nix).
          "igc.eee_enable=0"
          "pcie_port_pm=off"
        ];
        hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

        # SECURITY: the spinning disk is mounted, never formatted (see disko.nix).
        # WHY: nofail and automount, as unified mounted them, so a dead disk
        # cannot stop the router booting.
        fileSystems = {
          "/var/log/router" = {
            device = "/dev/disk/by-partlabel/disk-logs-logs";
            fsType = "ext4";
            options = [
              "noatime"
              "nofail"
              "x-systemd.automount"
            ];
          };
          "/srv/pxe" = {
            device = "/dev/disk/by-partlabel/disk-pxe-images-images";
            fsType = "ext4";
            options = [
              "noatime"
              "nofail"
              "x-systemd.automount"
            ];
          };
        };
      };
  };
}
