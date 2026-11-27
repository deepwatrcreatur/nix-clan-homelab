# Architecture

What this repo is for, what it builds on, and where it fills gaps in the
tools it builds on. For the migration itself see [`plan.md`](plan.md); for
individual decisions see [`decisions/`](decisions/).

## Goals

1. **One repo describes the whole fleet.** Every NixOS host, its users, its
   secrets and its place on the network come from this flake. Hand-edited
   state on a host is a bug.
2. **A host can be rebuilt from nothing.** Install, hardware detection,
   secrets and host identity come from the repo plus the operator's keys.
   State a rebuild cannot recreate is backed up (`nch-a9a.1`).
3. **Least privilege by construction.** A machine receives only the secrets
   its own config declares; routers get only what routing needs.
4. **Changes to live hosts are safe and visible.** Every change lands by PR
   with review bots. The network edge has rollback and a standby. You can
   see what a deploy will change before it runs.
5. **Agents do most of the work, under rules.** Work is queued as beads,
   claimed, done in a worktree, reviewed, merged. The rules live in
   [`AGENTS.md`](../AGENTS.md).
6. **As little bespoke machinery as possible.** Build on maintained
   frameworks. Write local code only for a gap, say why, and say what would
   let us delete it ([decision 0003](decisions/0003-upstream-first.md)).

## Layers

| Concern | Owner | Where |
| --- | --- | --- |
| Machine lifecycle: install, facter hardware reports, vars (secrets), SSH host certificates, routine deploys | [clan-core](https://docs.clan.lol) | `modules/clan.nix`, `machines/`, `vars/`, `sops/` |
| Composition of hosts, users and Home Manager | [den](https://github.com/denful/den) aspects | `modules/den.nix`, `modules/aspects/`, `modules/hosts/` |
| File layout | flake-parts + import-tree: every file under `modules/` is a module; paths with a `_` component are skipped and hold plain NixOS/HM modules | `modules/_nixos/`, `modules/_hm/` |
| Fleet facts: addresses, roles, DNS and SSH targets, appliances | local typed inventory (`homelab.hosts`) | `inventory/hosts.nix`, `modules/inventory.nix` |
| Router behaviour (zones, DNS, DHCP, VRRP) | [nix-router-optimized](https://github.com/deepwatrcreatur/nix-router-optimized), the operator's own flake | consumed by `router-role` |
| Router deploys with rollback | deploy-rs | `modules/deploy-rs.nix` |
| Work queue | [beads_rust](https://github.com/Dicklesworthstone/beads_rust) via `beads-q` | `beads-queue` branch |
| CI | NixCI now; buildbot-nix on emerald planned ([decision 0002](decisions/0002-self-hosted-ci.md)) | `nch-ktp` |

### Why Clan

Clan replaced a pile of scripts in unified: identity generation, rekeying,
hand-written hardware config, a known_hosts generator and
`nixos-rebuild --target-host` loops. Its vars give per-machine secret scope
for free, and its SSH CA removed stored host keys. The spike that decided
this is in [decision 0001](decisions/0001-clan.md).

### Why den on top of Clan

Clan decides which machines exist and how they get secrets and deploys. It
says little about composing a machine from reusable parts. den aspects do
that, and they already worked in unified, so hosts kept their structure.
An aspect can also add itself to a group (`router-hardening` joins
`router-role`) so host files do not change when a feature is added.

### Why beads

A queue in the repo (on its own branch) keeps the work, its dependencies and
its history in git, readable by any agent without a service or login.
Its strongest feature is graph-aware task selection (`ready --json`,
blockers, `bv`), which GitHub Issues, git-bug and Markdown files lack.
[Discussion 01](discussions/01-beads-rust-task-tracker.md) re-examined the
choice against those and Linear/Symphony and kept beads_rust, with the
queue on its own `beads-queue` branch written only by `beads-q`
(moved there on 2026-11-26). GitHub Issues is the fallback if the exit criteria there
trip.

## Gaps and how we fill them

Each local piece names the gap, the upstream status and what lets us delete
it. Items marked *proposed* are open PRs, not on `main` yet.

| Gap | Upstream status | Local fill | Exit condition |
| --- | --- | --- | --- |
| `clan machines update` has no rollback; a lockout survives reboot | clan-core [#3078](https://git.clan.lol/clan/clan-core/issues/3078), open; NixOS boot counting [nixpkgs#447173](https://github.com/NixOS/nixpkgs/pull/447173) | `fleet-deploy` sends `router` hosts through deploy-rs (magic rollback), others through Clan (`modules/deploy.nix`) | Clan rollback lands: drop deploy-rs |
| No check that a host is healthy after a deploy | same issue | `fleet-deploy` compares failed units before and after and prints the rollback (`scripts/deploy-health.py`); router probes (WAN, DNS, DHCP) not yet | Clan gains a post-activation check |
| No preview of what a deploy changes | none filed | *proposed* `fleet-deploy --diff` (#59) | Offer upstream as a `clan machines` option once proven |
| Clan vars need the admin age key; we do not want a key file on disk | by design, Clan leaves key handling to the operator | `clan-admin` wrapper derives it from the operator SSH key per command (`modules/clan.nix`) | none planned; it is small |
| Clan empties the global flake registry, so `nix run foo#` does not resolve | by design | *proposed* `flake-registry` aspect pins locked inputs on workstations (#60) | none planned |
| Clan's inventory covers machines it manages, not appliances, cameras or APs | out of scope for Clan | `homelab.hosts` inventory feeds Clan machine tags, SSH targets, deploy dispatch, router pairing and checks. DHCP reservations and DDNS still come from unified's `lib/hosts.nix` (`router-role`) | `nch-a9a.6`: one source, no reads from unified, less overlap with Clan's inventory |
| Beads and comment ids from separate clones collide; fresh clones then fail to import | fixed in beads_rust v0.7.0 ([#486](https://github.com/Dicklesworthstone/beads_rust/issues/486), [#512](https://github.com/Dicklesworthstone/beads_rust/issues/512)); this repo packages v0.7.6, older clones still run 0.1.45 | `checks/beads-integrity.py` on every push to `beads-queue` (GitHub Actions on that branch) | Kept permanently as a guard against writes that bypass `beads-q` ([discussion 01](discussions/01-beads-rust-task-tracker.md)); `nch-a9a.7` rolls 0.7 out |
| A beads claim is only local until it is pushed | upstream design | `beads-q` pushes each write to `beads-queue` and retries on the new tip, so a taken claim fails with `CLAIM_CONFLICT` | none needed; race test `nch-a9a.9` confirms it |
| Coding agents run expensive or unsafe commands | not a framework concern | `agent-guard` hook in the developer Home Manager profile | none |
| No hardening defaults for routers | srvos and the nixpkgs hardened profile exist | *proposed* `router-hardening` aspect (#61) | `nch-sny.42`: compare with srvos; move generic parts to nix-router-optimized |

### Gaps that turned out to be filled upstream already

Found during the 2026-11-25 review, before any local code was written:

- **Backups.** clan-core ships a `borgbackup` service, `clan.core.state`
  declarations and `clan backups create/list/restore`. `nch-a9a.1` uses them.
- **Monitoring.** clan-core ships a `monitoring` service (Alloy, Mimir,
  Loki, Grafana; experimental), with no alert rules or notification channel.
  `nch-a9a.5` evaluated it: [decision 0005](decisions/0005-fleet-alerting.md)
  proposes routing fleet alerts through the routers' existing Alertmanager
  instead.
- **Lock updates.** `update-flake-lock` and buildbot-nix schedules exist.
  `nch-a9a.4` uses one of them.

## Rules that follow

- Before writing a module, a script or a check, look in clan-core,
  nixpkgs, srvos and the tool's own tracker. Record what you found in the
  bead.
- Contribute fixes upstream instead of forking. Keep a local workaround
  only with a `# UPSTREAM:` comment naming the issue or PR.
- Router fixes go to nix-router-optimized, not into overrides here.
- When an upstream fix lands, delete the local fill in the same PR that
  bumps the input.
