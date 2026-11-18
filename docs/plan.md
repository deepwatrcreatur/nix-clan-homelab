# Migration plan

Goal: run the homelab from this repo on [clan-core](https://docs.clan.lol),
keeping [den](https://github.com/denful/den) aspects for host composition, and
retire `unified-nix-configuration` (below: "unified").

The work queue is in `.beads/` (`beads-rust ready`). This file explains the
phases and the decisions the beads refer to.

## What Clan replaces

| Concern | unified today | Here |
| --- | --- | --- |
| Add / install a machine | `just gen-identity`, `just install`, `docs/adding-a-nixos-host.md` | `clan machines create` / `install` (nixos-anywhere + nixos-facter) |
| Hardware config | hand-edited `hardware-configuration.nix` | `facter.json` per machine |
| Secrets | agenix, recipient groups in `secrets.nix`, `just rekey` | clan vars (generators, sops backend); each machine gets only what it declares |
| SSH host trust | `ssh-keys/*-host-*.pub` + nix-ssh-keys-manager known_hosts | clan `sshd` service: CA-signed host certificates |
| Deploy | `nixos-rebuild --target-host` loops | `clan machines update` (deploy-rs for routers if the spike says so) |
| Host composition | den aspects | den aspects (unchanged), fed into `clan.machines.<name>.imports` |
| Inventory | `lib/hosts.nix` + `den/inventory/` + derived lists | one inventory with roles |

## Spike

One disposable VM, `clan-spike`, on pve-rog (a VM, not an LXC: nixos-anywhere
needs kexec and a real disk). Beads `nch-sny.1` to `.6` each answer one
question:

1. Do den-built modules work as clan machine imports? (skeleton)
2. Does `clan machines install` with nixos-facter replace our install flow?
3. Do clan vars coexist with agenix during migration, and how are machines
   added and removed?
4. Does the sshd service remove host-key prompts without a key list?
5. What happens when a deploy breaks networking? Is deploy-rs still needed
   for the routers?
6. Do den's users and Home Manager wiring work under clan; what happens to
   darwin hosts and standalone homes?

The decision bead (`nch-sny.7`) blocks everything else. Its outcome goes in
`docs/decisions/0001-clan.md`.

## Fallback

If Clan is a no-go, stay on unified and adopt the pieces separately:
agenix-rekey (or nixos-artifacts) for secrets, nixos-facter, deploy-rs, an SSH
CA key held as a secret, and a single inventory. The foundation beads keep
their meaning; only their location changes.

## Migration order

Foundations first (inventory, ported aspects, secrets by domain, facter
reports, SSH CA, deploy tooling), then hosts from least to most critical:
vaglio, podman, homeserver, authentik-host, lattitude, phoenix, emerald,
elitedesk, router. unified is archived last.

## Routers

- Routers hold no outbound SSH keys and get only the vars they use (see
  unified's `docs/adding-a-nixos-host.md#router-hosts`).
- Migrate elitedesk (standby) before router, with console access ready.
- Never deploy a router change without the user available.

## Who does what

- `owner:any`: any agent (Claude, Codex, agy) may claim it.
- `owner:claude`: touches decrypted secrets or live hosts; Claude does it
  with the user's approval.
- `live`: changes a running machine.
