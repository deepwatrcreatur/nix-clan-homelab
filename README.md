# nix-clan-homelab

The homelab's NixOS fleet, managed with [Clan](https://clan.lol) and composed
from [den](https://github.com/denful/den) aspects.

Status: **migration in progress**. Unified remains authoritative for hosts
whose migration beads are still open; migrated hosts are composed and deployed
from this repository. See [`docs/plan.md`](docs/plan.md) for the migration
order and current host notes. The work queue lives on the `beads-queue` branch
(`beads-q ready`).
[`docs/architecture.md`](docs/architecture.md) explains the goals, why the
repo builds on Clan, den and beads, and which gaps it fills itself.
[`docs/inventory.md`](docs/inventory.md) maps host metadata to its readers.
