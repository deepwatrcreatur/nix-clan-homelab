# nix-clan-homelab

The homelab's NixOS fleet, managed with [Clan](https://clan.lol) and composed
from [den](https://github.com/denful/den) aspects.

Status: **spike**. Every host is still defined in
[unified-nix-configuration](https://github.com/deepwatrcreatur/unified-nix-configuration);
hosts move here one at a time. See [`docs/plan.md`](docs/plan.md) for the
phases and [`.beads/`](.beads/) for the work queue (`beads-rust ready`).
[`docs/architecture.md`](docs/architecture.md) explains the goals, why the
repo builds on Clan, den and beads, and which gaps it fills itself.
