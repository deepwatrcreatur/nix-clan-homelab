# 0005: Fleet alerting through the routers' Alertmanager

Status: **Accepted** (2026-11-27, operator: option B, the same ntfy topic as
router alerts, build now and deploy after the VRRP drill). Implemented in
`modules/aspects/fleet-alerting.nix`.
Context: [`docs/architecture.md`](../architecture.md#gaps-that-turned-out-to-be-filled-upstream-already),
[decision 0003](0003-upstream-first.md).

## Question

How should failed systemd units, full filesystems, SMART errors and
certificates near expiry on the migrated hosts reach the operator? The bead
asks to evaluate clan-core's `monitoring` service first, then fall back to the
smallest upstream pieces. Router monitoring stays in nix-router-optimized, and
both should feed the same place.

## What exists (checked 2026-11-27)

**clan-core `monitoring` service** (the revision this flake pins,
`clanServices/monitoring`):

- Marked **experimental** ("will change in the future").
- `client` role: Grafana **Alloy** on each machine collects node metrics and
  the journal, and pushes them over HTTP(S) with basic auth.
- `server` role (exactly one machine): **Mimir** (metrics), **Loki** (logs),
  nginx in front, optional **Grafana** with a provisioned dashboard and
  datasources. Mimir runs its ruler and Alertmanager components.
- **No alert rules and no notification channel are provisioned.** "Alerting"
  means Grafana's alerting is available; rules, contact points and an ntfy
  route would be ours to write and maintain.
- VM test: services start and the collector config exists. Nothing about
  alerts.

**nix-router-optimized `router-alerting`, already live on both routers**
(`modules/aspects/router-role.nix`):

- Prometheus (40 GB retention) and Alertmanager on each router.
- An **ntfy** relay with severity-based priority (clan var `ntfy-url`).
- A per-router **dead-man watchdog** to healthchecks.io, so a dead router or
  uplink is reported.
- Alertmanager clustering via `clusterPeers` for deduplication (not enabled
  yet, since each router so far alerts only about itself).
- `checks.router-alerting` asserts every router has ntfy and its own
  watchdog. NIC and SFP alert rules are already tested here
  (`checks.router-nic-alerts`).
- Node exporter on the routers with the `systemd` and `textfile` collectors.

**nixpkgs exporters:** `node` (with `--collector.systemd`: unit state;
filesystems), `smartctl`, `node-cert` (expiry of x509 certificates on disk,
such as ACME), `blackbox` (TLS expiry of live endpoints).

Not covered by any of them: **SSH CA host certificate** expiry (OpenSSH
certificates are not x509). Not needed today: Clan issues the host
certificates with `Valid: forever` (checked with `ssh-keygen -L`).

Node exporter today: `elitedesk` and `router` only. `clan-spike`,
`lattitude` and `phoenix` have none.

## Options

| | A. Clan `monitoring` | B. Extend the routers' stack | C. Clan for logs, B for alerts |
| --- | --- | --- | --- |
| Alert delivery | to build: Grafana rules, contact point, ntfy relay | exists: Alertmanager → ntfy, watchdog | B's |
| New services | Alloy everywhere; Mimir, Loki, nginx, Grafana (and its database) on one server | exporters on each host | A's, minus alerting |
| Single point of failure | the one server (the role allows one) | none: both routers scrape; clustered Alertmanagers dedupe while they can reach each other | B's for alerts |
| Who tells you the alerter is down | nothing yet | per-router healthchecks watchdog | B's |
| Maturity | experimental, will change | in use, checked | mixed |
| Logs | yes (Loki) | no | yes |
| "Same place" as router alerts | no, a second path | yes, the same Alertmanager | yes for alerts |

## Recommendation

**B now; C later only if central logs are wanted.**

Clan's service is the right tool for dashboards and log search, but for this
bead it adds a heavy single server, still leaves every alert rule and the
ntfy path to us, and would create a second alerting path beside the
routers', which already deliver to the phone and report their own death.
This stays within decision 0003: everything in B is upstream
(nix-router-optimized and nixpkgs exporters), plus the wiring that connects
them.

## Implementation

`modules/aspects/fleet-alerting.nix`:

1. **`fleet-metrics`** (included by `nixos-base`; skipped on routers, whose
   node exporter comes from nix-router-optimized): node exporter with the
   `systemd` collector (mount units included; node_exporter excludes them by
   default), and `smartctl` except in containers. Their ports accept only the
   routers' node addresses and the gateway address. A `raw`-table chain drops
   everyone else, IPv6 included, before tailscaled's `ts-input` chain or a
   trusted interface could accept them (nftables: a prerouting chain at raw
   priority).
2. **`fleet-alerting-router`** (included by `router-role`):
   - both routers scrape every migrated non-router host from
     `homelab.hosts`, as jobs `fleet-node` and `fleet-smartctl`, labelled
     `host` and `always_on`;
   - `smartctl`, and `node-cert` for Caddy's certificates (Caddy renews them
     on both routers), on the routers themselves;
   - `clusterPeers` set to the VRRP peers, cluster traffic pinned to the
     node address, admitted only from the peer, and dropped from anyone else
     at the start of the input chain (ahead of the trusted `tailscale0`).
3. **Rules** (`fleet.rules.json`, for routers too):
   - `HostDown`: an `always_on` host unscraped for 10 minutes; hosts with
     the `desktop` role are excluded;
   - `SystemdUnitFailed`: a unit failed for 5 minutes;
   - `FilesystemAlmostFull`: over 85 % for 15 minutes, pseudo filesystems
     and read-only mounts excluded;
   - `DiskSmartFailed`, `DiskCriticalWarning`, `DiskMediaErrors`;
   - `TlsCertificateExpiring`: within 14 days.
4. **Checks:** `checks.fleet-alert-rules` (promtool: each alert fires, and a
   desktop host, a healthy unit, a full tmpfs and a later certificate stay
   quiet), `checks.fleet-metrics` (every fleet host exports and is
   firewalled; every router scrapes exactly the fleet, loads the rules, runs
   the exporters and is clustered).
5. **Acceptance (from the bead), after the deploy:** with both routers up and
   clustered, a deliberately failed unit on clan-spike gives exactly one ntfy
   notification, and one resolved message after the unit is fixed.

Dropped from the proposal: the SSH certificate collector (the certificates do
not expire) and `node-cert` for NixOS ACME (no host uses it).

**Expect on the first deploy:** routers now alert on their own failed units
too, so any unit still failed 5 minutes after the deploy raises an alert.
`tailscaled-autoconnect.service` is failed on `router` today. The same
deploy carries its fix (nix-router-optimized #192, pinned since
nix-clan-homelab #79), and switching restarts the changed unit, so it should
clear rather than fire.

## Operator decisions (2026-11-27)

- Option B.
- Fleet alerts use the same ntfy topic as router alerts.
- Build now; deploy after the VRRP drill.
