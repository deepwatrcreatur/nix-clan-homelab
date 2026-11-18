# HP Compaq Elite 8300 SFF (i7-3770, 16 GB, UEFI). First bare-metal clan
# machine (nch-sny.21). It runs no router services yet: those wait for the
# router aspects, so it is neither primary nor standby for now.
{ den, ... }:
{
  den.aspects.elitedesk = {
    # SECURITY: router-class host: no nix-cache-auth or remote-builder-client
    # (routers hold no outbound keys or fleet credentials).
    includes = [ den.aspects.nixos-base ];
    nixos =
      { lib, ... }:
      {
        imports = [ ../../machines/elitedesk/disko.nix ];
        system.stateVersion = "26.05";

        # GOTCHA: the X520-2 is Oracle-branded (subsystem 108e:7b11); ixgbe
        # refuses its third-party SFP+ modules without this, and the LAN port
        # shows no carrier.
        boot.extraModprobeConfig = "options ixgbe allow_unsupported_sfp=1";
        # WHY: rescue boot from USB; facter lists only present devices.
        boot.initrd.availableKernelModules = [ "usb_storage" ];

        # GOTCHA: multi-homed: emerald reaches the management address via
        # router, but replies to 10.10.0.0/16 leave by the LAN port, so strict
        # reverse-path filtering dropped them (found on first boot).
        networking.firewall.checkReversePath = "loose";
        networking.useDHCP = false;
        networking.useNetworkd = true;
        systemd.network = {
          # INVARIANT: names pinned by MAC, matching unified's router role.
          links = {
            "10-wan".matchConfig.MACAddress = "90:e2:ba:7f:e0:3c";
            "10-wan".linkConfig.Name = "enp1s0f0";
            "10-lan".matchConfig.MACAddress = "90:e2:ba:7f:e0:3d";
            "10-lan".linkConfig.Name = "enp1s0f1";
            "10-mgmt".matchConfig.MACAddress = "24:be:05:06:9b:09";
            "10-mgmt".linkConfig.Name = "eno1";
          };
          networks = {
            # WHY: the deploy and SSH path; the onboard NIC needs no SFP quirk.
            "20-mgmt" = {
              matchConfig.Name = "eno1";
              address = [ "192.168.100.98/24" ];
              linkConfig.RequiredForOnline = "routable";
            };
            "20-lan" = {
              matchConfig.Name = "enp1s0f1";
              address = [ "10.10.10.4/16" ];
              gateway = [ "10.10.10.1" ];
              dns = [ "10.10.10.1" ];
              linkConfig.RequiredForOnline = "no";
            };
            # INVARIANT: WAN stays down. With DHCP it could take the modem's
            # single lease from the live router.
            "20-wan" = {
              matchConfig.Name = "enp1s0f0";
              linkConfig.ActivationPolicy = "down";
              linkConfig.Unmanaged = true;
            };
          };
        };

        # SECURITY: data disks are mounted, never formatted (see disko.nix).
        # WHY: nofail so a dead data disk cannot stop the host booting.
        fileSystems = {
          "/var/log/router" = {
            device = "/dev/disk/by-uuid/9eb87956-80bb-4ae5-9bc5-c82f71126574";
            fsType = "xfs";
            options = [ "noatime" "nofail" ];
          };
          "/srv/pxe" = {
            device = "/dev/disk/by-uuid/5d5b08ec-7c3d-4094-a133-28ef5c910d4c";
            fsType = "ext4";
            options = [ "noatime" "nofail" ];
          };
          "/big" = {
            device = "/dev/disk/by-uuid/02d78132-0124-4ff1-900e-8196d108fb31";
            fsType = "btrfs";
            options = [ "subvol=@big" "compress=zstd" "noatime" "nofail" ];
          };
        };
      };
  };
}
