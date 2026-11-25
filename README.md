# nix-clan-homelab

The homelab's NixOS fleet, managed with [Clan](https://clan.lol) and composed
from [den](https://github.com/denful/den) aspects.

## Fleet inventory

`inventory/hosts.nix` supplies role membership, migration status and connection
addresses. Clan and deploy-rs use the inventory's `sshTarget` to connect and
`sshHostKeyAlias` to verify the host certificate. The alias is derived from the
inventory key and LAN domain. A router can therefore use its management IP
even when that IP has no DNS record.

Status: **spike**. Every host is still defined in
[unified-nix-configuration](https://github.com/deepwatrcreatur/unified-nix-configuration);
hosts move here one at a time. See [`docs/plan.md`](docs/plan.md) for the
phases and [`.beads/`](.beads/) for the work queue (`beads-rust ready`).
