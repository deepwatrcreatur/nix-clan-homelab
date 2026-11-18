/**
  Generate a Disko and GRUB configuration following the homelab disk layout convention.

  For EFI hosts (`efi = true`), allocates an EFI System Partition (type EF00) mounted
  at `/boot/efi` with automount and idle-timeout options, keeping `/boot` on the
  journaled root filesystem. For BIOS hosts (`efi = false`), allocates a 1M BIOS boot
  partition (type EF02) and no ESP.

  # Inputs

  `device`
  : (String) Path to the target block device (e.g. `"/dev/disk/by-id/..."`).

  `efi`
  : (Boolean, optional, default: `true`) Whether this is an EFI host.

  `diskName`
  : (String, optional, default: `"main"`) The Disko disk attribute name under `disko.devices.disk`.

  `espSize`
  : (String, optional, default: `"512M"`) Size of the EFI System Partition.

  # Type

  ```
  diskoLayout :: AttrSet -> NixOS Module
  ```
*/
{
  device,
  efi ? true,
  diskName ? "main",
  espSize ? "512M",
}:
# WHY: docs/disk-layout.md
{
  boot.loader = {
    grub = {
      enable = true;
      efiSupport = efi;
      # WHY: docs/disk-layout.md#grub-and-uefi-boot
      # Removable media path ensures bootability even if NVRAM variables are not writable.
      efiInstallAsRemovable = efi;
      # INVARIANT: in EFI mode, GRUB installs into the ESP via efiSysMountPoint;
      # in BIOS mode, GRUB installs its MBR and core.img to the disk device.
      device = if efi then "nodev" else device;
    };
  } // (if efi then {
    efi.efiSysMountPoint = "/boot/efi";
  } else { });

  disko.devices.disk.${diskName} = {
    inherit device;
    type = "disk";
    content = {
      type = "gpt";
      partitions =
        (if efi then {
          ESP = {
            size = espSize;
            type = "EF00";
            priority = 1;
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot/efi";
              # WHY: docs/disk-layout.md#why-automount
              # FAT lacks journaling; keeping it unmounted except during bootloader
              # writes prevents corruption on unexpected power loss or reboot.
              mountOptions = [
                "noauto"
                "x-systemd.automount"
                "x-systemd.idle-timeout=60"
                "umask=0077"
              ];
            };
          };
        } else {
          boot = {
            size = "1M";
            type = "EF02";
            priority = 1;
          };
        })
        // {
          root = {
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
            };
          };
        };
    };
  };
}
