# Self-hosted Nix CI on emerald (handoff)

Status: **accepted** (2026-11-20; decisions in
[ADR 0002](./decisions/0002-self-hosted-ci.md)). Beads: epic `nch-ktp` (`beads-q show nch-ktp`).
Audience: the agent implementing it (Codex) and the maintainer. Read this
whole page and `docs/plan.md` first.

## Goal

Build every flake check of the maintainer's repos on homelab hardware, report
status on GitHub pull requests, and push the results to the existing Attic
cache, so deploys and other machines reuse them. The maintainer asked for
"garnix"; read the next section before searching for a garnix installer.

## Why not garnix

garnix shut down its hosted service on 2026-07-15 (the team joined Shopify)
and released its code as `garnix-io/garnix-ci` (BSD-3-Clause). So it *can*
be self-hosted, but it is a poor fit here:

- **No upkeep upstream:** the code was dumped without history on
  2026-05-27, and nothing has changed since June. Active maintenance happens
  in forks; the most active is `OSSystems/garnix-ci`, with commits in
  November 2026.
- **Many moving parts:** it was garnix's own multi-tenant SaaS. A Haskell
  backend, a frontend, PostgreSQL, OpenSearch, DNS, a hosting gateway,
  monitoring and sops-managed secrets run as several machines. The README
  documents a development deployment in local VMs (nixos-compose), not a
  production install.
- **Webhooks:** the backend is driven by GitHub App webhooks, which
  conflicts with ADR 0002's choice of polling and no inbound access.
- **No migration benefit:** the repos use NixCI, not `garnix.yaml`.

Revisit if a fork turns it into a maintained, single-host NixOS module.
The repos already use a hosted service (NixCI, the `NixCI` check on PRs).

| Option | What it is | Verdict |
| --- | --- | --- |
| garnix-ci (open-sourced garnix) | garnix's SaaS stack, BSD-3, maintained in forks | Rejected for now (above). |
| **buildbot-nix** (nix-community) | NixOS module: Buildbot master and worker that evaluate a flake's `checks` with nix-eval-jobs, build them in the Nix sandbox, and post GitHub commit statuses. Login with GitHub, Gitea or OIDC. | **Recommended.** Closest to garnix/NixCI behaviour, packaged as a NixOS module, widely used (nix-community's own CI). |
| nixbot (Mic92) | Single-service rewrite of buildbot-nix by its author | Watch, don't adopt yet: newer, smaller user base. Re-check if buildbot-nix stalls. |
| Self-hosted NixCI | The vendor says NixCI can be self-hosted | Check licence and price before considering; it would keep the current check names. |
| GitHub Actions self-hosted runner (srvos role or juspay `github-nix-ci`) | A runner that executes workflow YAML | Needs per-repo workflows, and running arbitrary workflow code on emerald. Only if buildbot-nix is rejected. |
| Hydra | The NixOS project's CI | Its own README calls it unsuitable for new small deployments; heavy. Rejected. |
| Hercules CI | Hosted coordinator, self-hosted agent | Still depends on a hosted service. Rejected. |

## Placement: directly on emerald

emerald is a Ryzen 9 7950X3D (16 cores, 32 threads), 128 GB RAM, 4 TB and
2 TB NVMe. It already runs `atticd` (port 5001) and is the fleet's remote
builder (`nix.buildMachines` in unified points at 10.10.11.55, with the
`kvm` and `nixos-test` features). It is also the maintainer's desktop.

| Placement | For | Against |
| --- | --- | --- |
| **NixOS on emerald (recommended)** | KVM for NixOS VM tests without nested virtualisation. Shares the store with the Attic server and remote builds, so nothing is built twice. Nothing new to maintain. | Shares the desktop. Mitigated by the resource limits below. |
| Incus VM on emerald | Isolation from the desktop | NixOS VM tests need nested KVM (works on AMD, but slower and one more thing to break). A second store duplicates what the host already has. Incus is not set up anywhere yet. |
| VM on pve-rog | Keeps load off the desktop | Same nested-KVM cost, fewer resources, and builds no longer land in emerald's store and cache directly. |

Use an Incus VM only if the maintainer later wants CI isolated for security
reasons (see "Untrusted pull requests"), not for performance.

### Protecting the desktop

- Run the worker's builds through the host nix-daemon. Cap
  `nix.settings.max-jobs` and `cores` so a full CI run leaves headroom; start
  around `max-jobs = 6`, `cores = 4`, then measure.
- Give `nix-daemon.service` (and the buildbot worker unit) a lower
  `CPUWeight=` / `IOWeight=` than the user session, plus a `MemoryHigh=`
  around 64 GB so a runaway build cannot push the desktop into swap.
- Keep the build directory on the 4 TB NVMe and set a GC policy, for
  example `nix.gc` plus `min-free`/`max-free`, so CI cannot fill the disk
  that also holds the Attic store.
- Keep CI from building more than one heavy NixOS VM test at a time, or
  measure first. nix-router-optimized's VM tests start four VMs each.

## Where the configuration lives

emerald is not migrated yet (`nch-sny.20`). Until a host migrates, unified
stays authoritative for operating it (`docs/plan.md#inventory`). The
maintainer chose path 1 (ADR 0002).

1. **Chosen:** write the CI as a den aspect in this repo
   (`ci-buildbot-nix`), with secrets as clan vars, and deploy it with or
   after emerald's migration. No throwaway agenix work.
2. If CI is wanted before emerald migrates: put the same aspect in unified
   with agenix secrets, then port it during `nch-sny.20`. Not chosen: it
   doubles the secret work.

## Design

### Components

- **Buildbot master and worker** on emerald, from the buildbot-nix flake
  input (pin a release tag; read its README at that tag, since option names
  change between versions, and don't trust names quoted here).
- **GitHub App** owned by the maintainer's account, installed only on the
  repos to build. buildbot-nix uses it for commit statuses and repo
  discovery. OAuth login to the web UI goes through the same app, or through
  Authentik over OIDC (buildbot-nix supports an OIDC auth backend; prefer it,
  since every other homelab UI already logs in through Authentik).
- **Attic push**: after a successful build, push outputs to the existing
  cache with a dedicated Attic token that can push to this cache only. The
  repo already has the shared `nix-cache-auth/attic-token` var; create a
  separate CI token rather than reusing the admin one.

### Secrets (clan vars, generators on emerald only)

- GitHub App ID and private key (prompted)
- OAuth or OIDC client secret (prompted from GitHub, or from Authentik)
- Worker password shared by master and worker (generated)
- Attic CI push token (prompted, created with `atticadm`)

None of these go into the Nix store. Follow `docs/secrets.md`.

### Polling, no inbound access (decided)

The CI serves only the homelab, so nothing is exposed: no webhook route, no
tunnel, no router change. emerald polls GitHub for new commits, and the
GitHub App is used outbound only, to read repos and post commit statuses.
The web UI is reachable only from the LAN and Tailscale (the maintainer
reaches `*.deepwatercreature.com` remotely through Tailscale split DNS to
Technitium). The firewall on emerald limits the UI port to those ranges.

Verify at the pinned buildbot-nix version how polling works for GitHub
repos (its pull-based mode, or a polling change source):
- does it build every branch, or only the default branch?
- does it still post commit statuses through the GitHub App?

The maintainer's PRs come from branches in the same repo, so polling all
branches covers them. If statuses cannot be posted without webhooks, stop
and ask the maintainer: they may accept build results in the UI only, or
reconsider a webhook route.

### Untrusted pull requests

nix-router-optimized is public, and a fork's pull request would run its own
Nix code on emerald (VM tests get KVM). Polling only the maintainer's own
repos and branches never fetches fork PRs. Keep it that way, and note it in
the aspect with a `# SECURITY:` comment. Fork PRs, if any, stay on hosted
NixCI while it exists, or are reviewed before a maintainer pushes the
branch themselves.

### Repos to onboard

Start with `nix-router-optimized` (heavy VM tests; the best measure of
value), then `nix-clan-homelab`, then the rest of the maintainer's flakes
(`nix-agent-guides`, `nix-attic-infra`, `nix-ssh-keys-manager`,
`unified-nix-configuration` until it is archived).

### Relationship to NixCI

Run both for two weeks on nix-router-optimized and compare:
- wall-clock time per PR;
- flaky failures, especially VM tests;
- cache hits on later local builds.

Decision (ADR 0002): if emerald meets the acceptance criteria during the
trial, the maintainer reduces or ends the nix-ci.com plan and relies on
emerald. Record the measured numbers in ADR 0002 before changing the plan.
The PR rule from `AGENTS.md` still applies: a PR merges when every
required check passes and bot findings are answered.

## Acceptance

- A PR to nix-router-optimized shows a buildbot status per flake check,
  including the VM tests, and they pass on a known-good commit.
- A deliberately broken check turns its status red, and the PR shows it.
- After a green build, `nix build` of the same check on another homelab
  host fetches from Attic instead of building.
- With CI running a full nix-router-optimized build, emerald's desktop stays
  responsive. CPU weight and memory limits hold; check with `systemd-cgtop`.
- Nothing is reachable from the internet: no public DNS record or router
  route for the CI, and the UI port answers only LAN and Tailscale clients.
- New commits on the maintainer's branches start builds within the polling
  interval, and fork PRs are never built.
- No secret appears in the Nix store (`nix-store --query --references` on
  the system closure plus a grep for the App ID file contents).

## Decisions (ADR 0002)

1. Deploy with emerald's clan migration (path 1); no work in unified.
2. Polling and homelab-only access; no inbound route.
3. If the trial goes well, reduce or end the nix-ci.com plan.

## Sources

- garnix shutdown and open-source release: https://garnix.io/blog/shutting-down/
- garnix-ci source: https://github.com/garnix-io/garnix-ci
  (active fork: https://github.com/OSSystems/garnix-ci)
- NixCI comparison page (vendor claims about self-hosting):
  https://nix-ci.com/comparison/garnix
- buildbot-nix: https://github.com/nix-community/buildbot-nix
- nixbot: https://github.com/Mic92/nixbot
- srvos GitHub Actions runner role:
  https://nix-community.github.io/srvos/github_actions_runner
