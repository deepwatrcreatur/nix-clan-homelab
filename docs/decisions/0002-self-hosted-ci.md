# 0002: Self-hosted CI with buildbot-nix on emerald

Status: **Accepted** (2026-11-20, user decision; bead nch-ktp.1).
Design: [`docs/self-hosted-ci.md`](../self-hosted-ci.md).

## Decision

- Run buildbot-nix directly on emerald (not an Incus or pve-rog VM). garnix
  was the starting request, but it is hosted-only.
- Build it as a den aspect in this repo with clan vars, deployed with or
  after emerald's migration (`nch-sny.20`). Nothing is added to unified.
- Poll GitHub; no webhook route and no public exposure. The UI is for LAN
  and Tailscale clients only. Fork pull requests are never built on emerald.
- Trial emerald alongside nix-ci.com on nix-router-optimized. If it meets
  the acceptance criteria in the design doc, reduce or end the nix-ci.com
  plan.

## Consequences

- No CI on homelab hardware until emerald is migrated.
- Builds start after the polling interval, not instantly.
- The router needs no change for CI.

## Trial results

To be filled in by `nch-ktp.6`: PR wall-clock time, flaky failures and
cache hits, emerald versus nix-ci.com.
