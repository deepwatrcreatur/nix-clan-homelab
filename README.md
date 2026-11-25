# nix-clan-homelab

The homelab's NixOS fleet, managed with [Clan](https://clan.lol) and composed
from [den](https://github.com/denful/den) aspects.

Status: **spike**. Every host is still defined in
[unified-nix-configuration](https://github.com/deepwatrcreatur/unified-nix-configuration);
hosts move here one at a time. See [`docs/plan.md`](docs/plan.md) for the
phases and [`.beads/`](.beads/) for the work queue (`beads-rust ready`).

## Keep flake inputs for offline work

On an operator machine, run `nix build .#flake-inputs --out-link ./result-flake-inputs`
while online. The output links to each distinct locked source, including
transitive inputs and non-flake inputs such as the Unified inventory snapshot.
Keep the output link to protect those sources from Nix garbage collection.
Rebuild the link after a lockfile update to retain the new pins. Remove the
link when those pins no longer need to be kept.

This retains source trees for offline evaluation of the checkout. Offline
builds also need their build dependencies or prebuilt closures in the store.
