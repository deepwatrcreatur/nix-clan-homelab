# HP Compaq Elite 8300 SFF (i7-3770, 16 GB, UEFI).
{ den, ... }:
{
  den.aspects.elitedesk = {
    # SECURITY: router-class host: no nix-cache-auth or remote-builder-client
    # (routers hold no outbound keys or fleet credentials).
    includes = [
      den.aspects.nixos-base
      den.aspects.router-role
    ];
    nixos = {
      imports = [ ../../machines/elitedesk/disko.nix ];
      system.stateVersion = "26.05";

      # GOTCHA: the X520-2 is Oracle-branded (subsystem 108e:7b11); ixgbe
      # refuses its third-party SFP+ modules without this, and the LAN port
      # shows no carrier.
      boot.extraModprobeConfig = "options ixgbe allow_unsupported_sfp=1";
      # WHY: rescue boot from USB; facter lists only present devices.
      boot.initrd.availableKernelModules = [ "usb_storage" ];

      # SECURITY: data disks are mounted, never formatted (see disko.nix).
      # WHY: nofail so a dead data disk cannot stop the host booting.
      fileSystems = {
        "/var/log/router" = {
          device = "/dev/disk/by-uuid/9eb87956-80bb-4ae5-9bc5-c82f71126574";
          fsType = "xfs";
          options = [
            "noatime"
            "nofail"
          ];
        };
        "/srv/pxe" = {
          device = "/dev/disk/by-uuid/5d5b08ec-7c3d-4094-a133-28ef5c910d4c";
          fsType = "ext4";
          options = [
            "noatime"
            "nofail"
          ];
        };
        "/big" = {
          device = "/dev/disk/by-uuid/02d78132-0124-4ff1-900e-8196d108fb31";
          fsType = "btrfs";
          options = [
            "subvol=@big"
            "compress=zstd"
            "noatime"
            "nofail"
          ];
        };
      };
    };
  };
}
