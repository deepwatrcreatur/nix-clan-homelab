# Router Failover Rehearsal Runbook

Bead: `nch-sny.36`. Design and the later VRRP plan:
[`router-election.md`](router-election.md).

VRRP is not running yet, so failover is **manual**. Each router carries the
other role as a NixOS specialisation:

| Host | Normal role | Specialisation | Defined in |
| --- | --- | --- | --- |
| `router` (Proxmox VM) | primary | `standby` | unified `hosts/nixos/router/standby-specialisation.nix` |
| `elitedesk` (bare metal) | standby | `primary` | this repo, `modules/aspects/router-role.nix` (`routerRole.promoted`) |

Roles move with `switch-to-configuration test`, never `switch` or `boot`. No
deploy happens during a rehearsal, and **a reboot always returns a host to
its normal role**: that is the last-resort rollback.

## What moves

| | router `standby` | elitedesk `primary` |
| --- | --- | --- |
| WAN | `always-down` | DHCP on `enp1s0f1np1` with router's MAC `02:76:c6:01:2a:b0`, DUID-EN and IAID (inventory `router.takeover`), so the modem hands over the same IPv4 lease and `/56` |
| LAN address | `10.10.10.2/16`, default route via 10.10.10.1 | `10.10.10.1/16` first, plus its own `10.10.10.4/16` |
| Kea DHCPv4 | off | on, same pool and reservations |
| Router adverts and prefix delegation | off (a final lifetime-0 RA withdraws router) | on |
| UPnP, mDNS reflection | off | on |
| Technitium zones | keeps its primary copy | `/run/router-ha/role` = `master`, so the zone-HA owner promotes the secondary copies |

**Not covered by this first rehearsal:** elitedesk's `primary` leaves out
everything that needs credentials only an inventory primary holds. During
the window:

- Tailscale subnet routing and the exit node move with nothing: router's
  Tailscale keeps running and reaches the internet through elitedesk.
- Cloudflare DDNS stays off. The public IP should not change.
- Kea DDNS stays off, so new leases get no DNS names during the window.
- Pangolin, Suricata and EveBox stay off.

## Preconditions

- The operator is present, with console access: the Proxmox web console for
  router, and a monitor and keyboard for elitedesk.
- Both hosts run their current configuration, including the specialisation.
  Check with `ls /run/current-system/specialisation/` on each.
- elitedesk's WAN optic is cabled to the WAN switch.
- No other router change is in flight.

## Access during the rehearsal

Management IPs (`192.168.100.x`) are reached **through 10.10.10.1**, the
address that moves. Use the LAN addresses, which are on the same L2 as the
operator's workstation:

```sh
ssh -o HostKeyAlias=router    deepwatrcreatur@10.10.10.1   # before; 10.10.10.2 after
ssh -o HostKeyAlias=elitedesk deepwatrcreatur@10.10.10.4
```

**Run every role switch detached**, so a dropped SSH session cannot interrupt
activation halfway:

```sh
sudo systemd-run --unit=failover --collect <path>/bin/switch-to-configuration test
journalctl -u failover -f
```

## Procedure

### 1. Baseline (router primary)

Start monitors on a LAN workstation and record their timestamps:

```sh
ping -D -i 0.2 10.10.10.1          # gateway
ping -D -i 0.5 1.1.1.1             # IPv4 internet
ping -6 -D -i 0.5 2606:4700:4700::1111
```

On router, record the WAN IPv4 address (`ip -br addr show enp6s17`), the
delegated prefix (`journalctl -u systemd-networkd | grep 'delegated prefix' | tail -1`)
and the lease count (`wc -l /var/lib/kea/dhcp4.leases`).

### 2. Copy the Kea leases to elitedesk

elitedesk's Kea must not hand out addresses that router already leased:

```sh
ssh router sudo cat /var/lib/kea/dhcp4.leases > /tmp/dhcp4.leases
scp /tmp/dhcp4.leases elitedesk:/tmp/ && ssh elitedesk \
  'sudo install -D -m 0644 /tmp/dhcp4.leases /var/lib/kea/dhcp4.leases'
```

Check the Kea lease path and owner first (`systemctl cat kea-dhcp4-server`).

### 3. Demote router, then promote elitedesk

Order matters: **router's WAN must be down before elitedesk's comes up**,
because the modem has one lease.

```sh
# on router (via 10.10.10.1)
sudo systemd-run --unit=failover --collect \
  /run/current-system/specialisation/standby/bin/switch-to-configuration test
# wait until router answers on 10.10.10.2 and `ip -br link show enp6s17` is DOWN

# on elitedesk (via 10.10.10.4)
sudo systemd-run --unit=failover --collect \
  /run/current-system/specialisation/primary/bin/switch-to-configuration test
```

Then on elitedesk:

```sh
ip -br addr show enp1s0f0np0          # 10.10.10.1/16 and 10.10.10.4/16
ip -br link show enp1s0f1np1          # UP, 02:76:c6:01:2a:b0
ip -br addr show enp1s0f1np1          # the same public IPv4 as the baseline
ip route show default
sudo arping -U -c 3 -I enp1s0f0np0 10.10.10.1   # refresh client ARP caches
```

### 4. Observe

| Check | Pass |
| --- | --- |
| Gateway ping gap | under 10 s |
| WAN lease | the same IPv4 as the baseline, within 30 s |
| Delegated prefix | the same `/56` as the baseline |
| IPv4 and IPv6 internet from a client | resumes |
| `dig @10.10.10.1 google.com` and `dig @10.10.10.1 router.deepwatercreature.com` | both answer |
| A client renews or re-joins Wi-Fi | gets a lease from elitedesk's Kea |
| `cat /run/router-ha/role` on elitedesk | `master`; zones are Primary in Technitium |
| ntfy and the healthchecks watchdog | no false "router down" page, or the expected one |

### 5. Fail back

```sh
# on elitedesk (via 10.10.10.4): back to standby first, which drops the WAN
sudo systemd-run --unit=failback --collect \
  /nix/var/nix/profiles/system/bin/switch-to-configuration test
sudo systemctl stop technitium-zone-ha-owner   # demote the zones; it waits for router

# on router (via 10.10.10.2): back to primary
sudo systemd-run --unit=failback --collect \
  /nix/var/nix/profiles/system/bin/switch-to-configuration test
```

Then confirm that router holds 10.10.10.1, the WAN lease and the prefix, that
Kea is running, and that elitedesk's role file reads `backup`. Copy any
leases that elitedesk handed out back to router before restarting router's
Kea, or accept that those clients may re-DORA.

## Abort

At any step, return both hosts to normal in this order:

1. elitedesk: `/nix/var/nix/profiles/system/bin/switch-to-configuration test`
   (WAN down, LAN 10.10.10.4 only, Kea off).
2. router: `/nix/var/nix/profiles/system/bin/switch-to-configuration test`.
3. If SSH is gone, reboot from the console: both boot their normal role.

Abort when elitedesk gets no WAN lease within 60 s, internet does not come
back within 2 minutes, or anything unexpected happens.

## Results

Record each rehearsal here: date, commits of both repos, measured times and
the anomalies, with links to beads for follow-ups.
