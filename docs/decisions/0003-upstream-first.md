# 0003: Upstream first; local code only for named gaps

Status: **Accepted** (2026-11-25, user decision).
Context: [`docs/architecture.md`](../architecture.md#gaps-and-how-we-fill-them).

## Decision

Build on clan-core, den, beads_rust, nixpkgs and nix-router-optimized
rather than growing a homelab-specific framework. Do not fork them.

Local code is allowed when a framework has a gap that blocks real work.
Each such piece:

- is listed in the gaps table in `docs/architecture.md`, with the upstream
  issue or PR if one exists and the condition for deleting it;
- carries a `# UPSTREAM:` comment where it works around upstream behaviour;
- is offered upstream once it has proven itself, when it is general.

## Why

- A fork must be rebased on every upstream release; a contribution costs
  once.
- The 2026-11-25 review found that three planned local systems (backups,
  monitoring, lock updates) already existed in clan-core or common tools,
  and that both beads id collision bugs were fixed upstream in a release
  this repo had not picked up.
- Fewer bespoke parts means less for agents and the operator to learn and
  maintain.

## Consequences

- New work starts with a search of upstream sources, recorded in the bead.
- Some fixes wait on upstream maintainers; the local fill stays until then.
- Pinned tools need deliberate upgrades (`nch-a9a.7` for beads_rust), or
  the repo carries workarounds for bugs already fixed.
