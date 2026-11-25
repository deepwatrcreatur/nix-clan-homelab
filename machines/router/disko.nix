# router OS disk only, matching the layout unified installed (its
# hosts/nixos/router/disko.nix); the partition and subvolume names must stay
# as they are, because fileSystems are derived from them.
# SECURITY: disko formats every disk listed here. The spinning disk (router
# logs and PXE images) is mounted by partition label in
# modules/hosts/router.nix and must never be added to this file.
{
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/disk/by-id/nvme-WDS500G3X0C-00SJG0_21107G804181";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          name = "ESP";
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [
              "fmask=0077"
              "dmask=0077"
            ];
          };
        };
        root = {
          size = "100%";
          content = {
            type = "btrfs";
            extraArgs = [ "-f" ];
            subvolumes =
              let
                opts = [
                  "compress=zstd"
                  "noatime"
                ];
              in
              {
                "@" = {
                  mountpoint = "/";
                  mountOptions = opts;
                };
                "@home" = {
                  mountpoint = "/home";
                  mountOptions = opts;
                };
                "@snapshots" = {
                  mountpoint = "/.snapshots";
                  mountOptions = opts;
                };
              };
          };
        };
      };
    };
  };
}
