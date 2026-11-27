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
   **Done 2026-11-25/26** (nch-sny.36.7). The modem kept 99.237.231.178 and
   2607:fea8:a4c5:3600::/56 through every step. Gaps from emerald (1 s
   probes):

   | Step | Gateway | DNS | IPv4 | IPv6 |
   | --- | --- | --- | --- | --- |
   | stop keepalived on MASTER | 0 | 0 | 3.5 s | 3.7 s |
   | fail-back (preempt after 300 s) | 0 | 0 | 0 | 0.3 s |
   | MASTER's WAN cable pulled | | | about 7 s | |
   | MASTER power cut | 3.2 s | 2.2 s | 6.7 s | **90 s, then flapping for 2.5 min** |
   | fail-back after the power cut | 0 | 0 | 0 | 2.8 s |

   Pulling the WAN cable put elitedesk in FAULT with its priority pinned to 1
   for 900 s, as designed. Kea went PARTNER-DOWN on the survivor and back to
   hot-standby when the partner returned; zones were promoted and demoted
   each time.

   **IPv6 after the MASTER dies (fixed).** Each member used to advertise
   itself from its own link-local address. A demotion sends a zero-lifetime
   RA, but a MASTER that loses power cannot, so SLAAC clients kept its route
   (router lifetime 1800 s) while neighbor discovery sat in DELAY.
   nix-router-optimized #193 (clan #81) has the MASTER advertise from
   `fe80::1`, which moves with VRRP; clients keep one route `via fe80::1`.
   Power cut repeated 2026-11-27: gateway 3.2 s, DNS 2.2 s, IPv4 6.7 s,
   **IPv6 7.0 s**; the lease and /56 kept; fail-back 1.3 s IPv4, 1.5 s IPv6.

   **Rebooted member preempting without the 300 s hold (fixed in code,
   not yet drilled).** In the repeat, elitedesk's keepalived started (5 s
   boot timer) 8 s after its LAN carrier came up, heard no adverts for
   3.5 s and became MASTER on the master-down timer, which `preempt_delay`
   does not cover. router heard elitedesk's first advert 14 s after that
   carrier: the switch port was likely not forwarding yet (spanning-tree
   delay). nix-router-optimized #196 holds keepalived's start until it
   captures a VRRP advert for our VRID on the LAN, or `peerWaitSec` passes;
   clan sets 60 s on paired members and 0 on a lone member
   (`checks.router-vrrp`: "keepalived waits for the peer iff paired"). A
   member with a live peer starts as soon as its port forwards. The cost:
   when both routers cold-start together (a house power cut), neither hears
   the other until one gives up, so the gateway comes up to 60 s later than
   before. Making both router ports edge/portfast on the switch still
   shortens every boot. nch-sny.36.11.

   **The real cause: elitedesk never hears VRRP multicast.** Deploying
   #196 on 2026-11-27 showed the gate on elitedesk waiting the full 60 s
   while router sent adverts every second. From a LAN host, UDP multicast,
   protocol-112 broadcast and unicast all reached elitedesk, but no
   protocol-112 multicast did (224.0.0.1, .18, .19), even with the group
   joined: its NIC's `rx_multicast_phy` stayed flat through a 2000-packet
   burst that router received. Something on the LAN drops it on the way
   to elitedesk's port; router hears elitedesk fine, so the drop is
   one-way. A freshly started elitedesk therefore always took over after
   about 3 s, and the pair only looked healthy because router heard the
   higher priority and stepped aside. Spanning tree was not the cause.
   The path from router to elitedesk crossed sw-main (TE6) and two more
   switches. "Unknown multicast: flood" on sw-main did not help; after one
   switch was removed (leaving the Dell N1124T-ON), router's adverts
   reached elitedesk, but test packets from a LAN host still did not.
   Instead of depending on switch settings, VRRP now goes unicast to the
   peer's LAN address (nix-router-optimized `unicastPeers`;
   `checks.router-vrrp`: "VRRP adverts go unicast to each peer's LAN
   address").

   Switching the live pair: a unicast node drops multicast adverts and the
   reverse, so a half-switched pair has two MASTERs. Mask keepalived on
   the BACKUP (`systemctl mask --runtime --now keepalived`), deploy it,
   deploy the MASTER, then unmask and start the BACKUP. Deploy elitedesk
   over its LAN address (`deploy .#elitedesk --hostname 10.10.10.4`):
   this workstation reaches the management address only through the
   gateway, and that path breaks while the VIP moves.

   The first power-cut attempt (router as MASTER) cost about 10 minutes for
   an unrelated reason: elitedesk's WAN cable had worked loose at its NIC
   after the cable-pull step, so as MASTER it got no DHCP answer. Check WAN
   cabling before a drill. The loose cable also raised elitedesk's WAN
   carrier once while it was BACKUP.

## Abort

At any step: fence router (`sudo touch /var/lib/router-failover/demoted`),
stop keepalived on it, then deploy elitedesk's previous generation
(`mode = "primary"`) with `fleet-deploy` or its boot menu. elitedesk then holds
the gateway statically again, as after the 2026-11-24 move. The marker keeps
router's keepalived off across reboots under both unified and clan (a
`ConditionPathExists` on the unit, `checks.router-vrrp`); remove it only when
router may compete for the gateway again.
