# Router VRRP Pair

Bead: `nch-sny.36` (VRRP drill). Design background:
[`router-election.md`](router-election.md). How other HA routers solve the
single-WAN-address problem, and why `router-ha` works the way it does:
nix-router-optimized
[`docs/router-ha-prior-art.md`](https://github.com/deepwatrcreatur/nix-router-optimized/blob/main/docs/router-ha-prior-art.md).

`router.mode = "vrrp"` makes a host a member of a VRRP pair. keepalived (via
nix-router-optimized's `router-ha`) decides which member is MASTER: it holds
the gateway 10.10.10.1, raises the WAN with the modem's MAC and DHCP
identity, and runs the services that must exist once. The other member keeps
its WAN down and stays ready to take over without a deploy.

elitedesk has been a lone member since 2026-11-25 (rollout step 2).
`checks.router-vrrp` evaluates it in three layouts (preferred with a peer,
backup to a peer, alone) plus its real inventory entry.

## What a member gets

| Concern | On a `vrrp` member | Notes |
| --- | --- | --- |
| Gateway 10.10.10.1/16 | keepalived adds it on the MASTER | each member keeps its own `lanAddress` |
| WAN | `router-ha.wan`: `ActivationPolicy=manual`; MASTER sets `takeover.wanMac` and starts DHCP | the network keeps the modem's DUID-EN and IAID; they win over router-ha's derived DUID |
| Dead WAN on the MASTER | `wan.healthCheck`: yields to the peer, pins itself low | only when paired; a lone member keeps the gateway and DNS through an ISP outage |
| Fail-back | waits `vrrpPreemptDelay` (300 s) as BACKUP | |
| Boot | WAN never required for `network-online` | a BACKUP's WAN is down |
| BACKUP's own internet | LAN route via the VIP, metric 2000 | on the MASTER the WAN's DHCP route wins |
| Credentials | all primary ones, plus the shared `router-vrrp-password` | a member becomes MASTER without a deploy |
| Transitions | applied in order through keepalived's notify FIFO | nix-router-optimized #186 (pinned) |

## Ownership

| Service | Placement | Mechanism |
| --- | --- | --- |
| Kea DHCPv4 | both members, Kea HA **hot-standby** (preferred member primary) | `router-kea.dhcp4.ha`; only when paired |
| Kea D2 | both, updates sent to the VIP (`follow-vip`); a lone member runs it on the MASTER only | `router-kea.ddns.ha.mode` |
| Technitium zones | Secondary of the VIP on every member; the MASTER promotes its copy | `zoneReplication.ha`; only when paired |
| Technitium | both; listens on loopback, the VIP, the node's LAN and management addresses and `::` | replies to D2 come from the VIP |
| Dynamic DNS updates | accepted from loopback, the VIP and both members' LAN addresses, TSIG-signed | `rfc2136.zones.<zone>.updateNetworkACL`; only when paired |
| Static DNS records | written by the zone owner; a Secondary skips them, promotion rewrites them | nix-router-optimized #188 (pinned) |
| inadyn (Cloudflare DDNS) | MASTER | `router-ddns.ha.singleActiveOwner` |
| miniupnpd | MASTER | `router-upnp.ha.singleActiveOwner` |
| IPv6 router advertisements | MASTER is the default router | `routerAdvertisements.mode = "vrrp-owner"` |
| Avahi reflector | MASTER | `singleActiveUnits`; two reflectors would reflect each other |
| Pangolin and gerbil | preferred member, while MASTER | `singleActiveUnits`; the database and WireGuard key live there |
| Caddy, iventoy, Tailscale, Suricata, monitoring, SNMP, NTP | both | Caddy and iventoy answer on the VIP; Tailscale runs one subnet router per member |

When the preferred member is not MASTER, Pangolin's public tunnels and PXE
images are unavailable. That is accepted: neither matters during a short
failover.

## Rollout

Each live step needs the operator at both consoles and an agreed window
(docs/plan.md#routers). Record measurements in `nch-sny.36`.

1. **This change**: the mode and its check. No host changes.
2. **elitedesk alone** (`mode = "vrrp"`, no peer): generate
   `router-vrrp-password` (`clan-admin vars generate elitedesk`), then
   `fleet-deploy elitedesk`. Expected: a gateway gap of a few seconds while
   keepalived elects itself (every member starts BACKUP because of
   `preemptDelay`), and a WAN bounce as the MASTER transition reapplies the
   cloned MAC and restarts DHCP with the same identity. Kea keeps running
   alone; zones stay Primary.
   **Done 2026-11-25** (clan #64). Gaps seen from emerald: about 8.5 s for the
   gateway and 7.5 s for DNS on the VIP, while networkd had dropped the old
   static 10.10.10.1 and keepalived waited out its boot delay. Internet was
   lost for about 1.2 s, during the WAN bounce. IPv4 stayed the same, but the
   /56 changed: activation reconfigured the up WAN and networkd's DHCP clients
   sent RELEASE. nix-router-optimized #189 stops that (`SendRelease=no`); take
   it in the pin before any later deploy that touches the WAN.
3. **router into clan** (code): inventory entry with `mode = "vrrp"`,
   priority 100, devices and disks from unified's bare-metal config (igc
   LAN/WAN, e1000e management, Limine), its existing SSH host key imported.
   Read-only hardware checks on router first (`ip -br link`, `lsblk`,
   facter). The gateway address must come from the network, not from the
   `router` host entry, once `router` is a member.
   **Done 2026-11-25** (nch-sny.36.6): `modules/hosts/router.nix`,
   `machines/router/` (NVMe-only disko matching unified's layout, facter),
   `homelab.gateway`. router's fstab and kernel parameters match the running
   system exactly. Its existing ed25519 host key is imported and it has its
   own healthchecks.io check. **From this change on, elitedesk evaluates as
   paired**, so its next deploy is step 4; do not deploy elitedesk for
   anything else in between.
4. **Pair** (live): deploy elitedesk paired (Kea HA waits for its partner,
   then serves alone), then deploy router; its keepalived stays off while the
   demoted marker exists, so remove the marker and `systemctl start
   keepalived` once router's services look right.
   router's first clan deploy replaces unified's whole configuration, so do
   it with its console at hand. Upload its machine age key first
   (`clan-admin vars upload router`): deploy-rs does not, and sops-nix needs
   it to decrypt the vars. The pin includes nix-router-optimized #189,
   so a WAN reconfigure no longer releases the lease.
   **Done 2026-11-25.** elitedesk's paired deploy kept the /56 and the IPv4
   lease; gaps were about 7.5 s for the gateway and 5 s for internet and DNS,
   and Kea paused DHCP for about 20 s (WAITING, then PARTNER-DOWN) until
   router joined as its hot-standby partner. router's first clan switch
   failed twice and kept running the new generation: an expired shared
   Tailscale key, bare `pangolin`/`gerbil` units (#67), then tailscaled still
   retrying the old key (restart it once after replacing the key). With the
   marker removed, router's keepalived came up BACKUP with no client-visible
   gap.
   Expected: router BACKUP, Kea `hot-standby` on both, zones Secondary on
   router.
5. **Drill**, measuring gateway, IPv4, IPv6, DNS and DHCP gaps from a LAN
   client and the emerald monitors:
   - `systemctl stop keepalived` on the MASTER, then start it (fail-back after
     300 s);
   - pull the MASTER's WAN cable (health check yields);
   - cut the MASTER's power, then boot it (it returns as BACKUP);
   - check the modem kept the IPv4 lease and the /56 at every step.

## Abort

At any step: fence router (`sudo touch /var/lib/router-failover/demoted`),
stop keepalived on it, then deploy elitedesk's previous generation
(`mode = "primary"`) with `fleet-deploy` or its boot menu. elitedesk then holds
the gateway statically again, as after the 2026-11-24 move. The marker keeps
router's keepalived off across reboots under both unified and clan (a
`ConditionPathExists` on the unit, `checks.router-vrrp`); remove it only when
router may compete for the gateway again.
