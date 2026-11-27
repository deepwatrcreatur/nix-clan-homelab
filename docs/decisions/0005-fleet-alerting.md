# 0005: Fleet alerting through the routers' Alertmanager

Status: **Proposed** (2026-11-27, evaluation for `nch-a9a.5`; needs the
operator's decision).
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
certificates are not x509).

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
(nix-router-optimized and nixpkgs exporters). The only local code is one
small textfile collector for SSH certificate expiry, a named gap.

## Plan (B), once accepted

1. **Exporters on every migrated host** (a `fleet-metrics` aspect):
   - node exporter with `systemd`, `filesystem` and `textfile`;
   - `smartctl` exporter on hosts with disks;
   - `node-cert` on hosts holding ACME certificates.

   Ports open only to the two routers' LAN addresses.
2. **Both routers scrape** the fleet from `homelab.hosts`, so the target list
   cannot drift from the inventory. Set `clusterPeers` so the pair sends each
   notification once while the two can reach each other, and the survivor
   keeps sending. If their link splits while both still reach ntfy, each
   side sends: Alertmanager prefers a duplicate to a lost alert.
3. **Rules**, with `host` labels, tested with `promtool` like
   `router-nic-alerts`:
   - a unit in `failed` state for 5 minutes;
   - a filesystem over 85 % (tmpfs and the Nix store excluded);
   - SMART health failed, or NVMe media errors increasing;
   - an ACME certificate or SSH host certificate expiring within 14 days;
   - a host down for 10 minutes, excluding laptops (`lattitude`).
4. **SSH host certificate expiry:** a textfile collector that runs
   `ssh-keygen -L` on the host certificate and writes the `Valid: to` time as
   a metric. It is the one local piece; add a gaps-table row
   ("OpenSSH certs are not x509").
5. **Acceptance (from the bead):** with both routers up and clustered, a
   deliberately failed unit on clan-spike gives exactly one ntfy
   notification, and one resolved message after the unit is fixed.

## Decisions for the operator

- **B or A?** This record recommends B.
- **Deploy timing:** steps 1–3 change both routers (scrape config,
  clustering) and every host, so the deploy waits until the VRRP drill is
  over.
- **Notifications:** fleet alerts on the same ntfy topic as router alerts
  (simplest), or on a separate topic.
