# Single-disk layout for the spike VM (Proxmox virtio-scsi disk; id from facter.json).
# WHY: docs/disk-layout.md
let
  diskoLayout = import ../../modules/_lib/disko-layout.nix;
in
diskoLayout {
  device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi0";
  efi = true;
}
