# nix-clan-homelab work queue

This orphan branch holds only the beads queue (`.beads/`), not code. Agents
read and write it through `beads-q` (unified-nix-configuration
`programs.beads`), from any worktree of the repo:

```sh
beads-q ready --json
beads-q update <id> --claim --actor <you>
beads-q close <id> --reason "<what was done, PR link>" --actor <you>
```

Each write is committed and pushed here at once; a rejected push is retried
on the new tip, so a claim someone else already holds fails with
`CLAIM_CONFLICT`. Do not commit to this branch by hand, and never force-push
it. `checks/beads-integrity.py` runs on every push (`.github/workflows/`).

Seeded on 2026-11-26 from `main` (bead `nch-a9a.8`, discussion 01 in
`docs/discussions/` on `main`).
