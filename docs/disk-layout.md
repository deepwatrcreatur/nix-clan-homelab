# Disk layout convention

All newly provisioned machines and reinstalled hosts in this repository follow
a unified disk layout convention for Disko and GRUB.

## Why this convention exists

UEFI firmware requires an EFI System Partition (ESP) formatted as FAT (vfat).
However, FAT is a legacy filesystem without journaling:
- If a machine loses power, crashes, or is forcefully stopped while the FAT
  filesystem is mounted read-write, the filesystem metadata can easily become
  corrupted.
- On Linux, this frequently results in the filesystem being remounted read-only
  or failing filesystem checks on subsequent boots. During the spike VM testing
  ([`docs/plan.md#nch-sny2-install-with-clan--nixos-facter-done`](plan.md#nch-sny2-install-with-clan--nixos-facter-done)),
  stopping the VM before a clean unmount left the ESP corrupt, causing the next
  deploy to fail in `grub-install` with a read-only `/boot`.

To eliminate this vulnerability, we separate the EFI System Partition from `/boot`:
1. `/boot` stays on the journaled root filesystem (`ext4`). Kernels, initrds, and
   GRUB configuration files (`/boot/grub/grub.cfg`) are written to the journaled
   filesystem, protecting them from corruption across power loss.
2. The ESP is mounted at `/boot/efi` instead of `/boot`.
3. BIOS-only VMs do not need an ESP at all; they receive a 1M BIOS boot
   partition (`EF02`) and avoid FAT entirely.

### Why automount

The ESP mount uses systemd automount options:
`noauto, x-systemd.automount, x-systemd.idle-timeout=60, umask=0077`.
The partition remains unmounted during normal operation and is mounted on
demand only when accessed (e.g. when `grub-install` updates EFI binaries
during a deployment). Once bootloader installation finishes and 60 seconds
of inactivity elapse, systemd unmounts it automatically. Keeping the ESP
unmounted minimizes the window of vulnerability to power loss.

### GRUB and UEFI boot

On EFI systems, GRUB installs into the ESP via `boot.loader.efi.efiSysMountPoint`.
Setting `boot.loader.grub.efiInstallAsRemovable = true` installs the EFI binary
to the default fallback path (`EFI/boot/bootx64.efi`), ensuring the machine boots
even if NVRAM boot entries are lost or unwritable in virtualized environments.
Because GRUB is installed as an EFI application, `boot.loader.grub.device` is set
to `"nodev"`.

## Layout specification

### EFI hosts (`efi = true`)

- **Partition table:** GPT
- **Partitions:**
  1. `ESP`: 512 MB, type `EF00`, formatted `vfat`, mounted at `/boot/efi` with
     `mountOptions = [ "noauto" "x-systemd.automount" "x-systemd.idle-timeout=60" "umask=0077" ]`.
  2. `root`: remainder (100%), formatted `ext4`, mounted at `/`.
- **Bootloader configuration:**
  - `boot.loader.grub.enable = true`
  - `boot.loader.grub.efiSupport = true`
  - `boot.loader.grub.efiInstallAsRemovable = true` (ensures bootability across NVRAM resets)
  - `boot.loader.grub.device = "nodev"` (EFI installation installs to ESP; no MBR write)
  - `boot.loader.efi.efiSysMountPoint = "/boot/efi"`

### BIOS-only VMs (`efi = false`)

- **Partition table:** GPT
- **Partitions:**
  1. `boot`: 1 MB, type `EF02` (BIOS boot partition), priority 1, unformatted (for GRUB core.img).
  2. `root`: remainder (100%), formatted `ext4`, mounted at `/`.
- **Bootloader configuration:**
  - `boot.loader.grub.enable = true`
  - `boot.loader.grub.efiSupport = false`
  - `boot.loader.grub.device = device` (writes MBR/core image to the target drive)
  - No ESP or `boot.loader.efi` settings.

## Shared helper

The layout is implemented by the shared helper in
`modules/_lib/disko-layout.nix` (and exposed via `flake.lib.diskoLayout`).

Each machine's `machines/<name>/disko.nix` calls the helper with its target disk:

```nix
# WHY: docs/disk-layout.md
let
  diskoLayout = import ../../modules/_lib/disko-layout.nix;
in
diskoLayout {
  device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi0";
  efi = true;
}
```

## Migration

Existing hosts adopt this layout when reinstalled during migration (bead `nch-sny.24`).
The disposable spike VM `clan-spike` serves as the initial testbed.
