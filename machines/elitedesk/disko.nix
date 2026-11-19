# elitedesk OS disk only.
# SECURITY: disko formats every disk listed here. The data disks (sdb: router
# logs and PXE images, sdc: /big) are mounted by UUID in
# modules/hosts/elitedesk.nix and must never be added to this file.
import ../../modules/_lib/disko-layout.nix {
  device = "/dev/disk/by-id/ata-T-FORCE_240GB_TPBF2311070050100823";
  efi = true;
}
