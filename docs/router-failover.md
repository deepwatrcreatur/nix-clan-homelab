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
| LAN address | `10.10.10.2/16`, default route via 10.10.10.1 | `10.10.10.1/16` only; its own `10.10.10.4` is dropped so the gateway is the kernel's primary address and Kea's server identifier |
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

| Host | Before the switch | While elitedesk is primary |
| --- | --- | --- |
| router | `10.10.10.1` | `10.10.10.2` |
| elitedesk | `10.10.10.4` | `10.10.10.1` |

```sh
ssh -o HostKeyAlias=router    deepwatrcreatur@<address>
ssh -o HostKeyAlias=elitedesk deepwatrcreatur@<address>
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

### 2. Hand the Kea leases to elitedesk

elitedesk's Kea must not hand out addresses that router already leased.
Kea runs with `DynamicUser`, so its state is in `/var/lib/private/kea`, and
its memfile backend keeps live leases in rotated files (`dhcp4.leases.1`,
`.2`, `.completed`) as well as in `dhcp4.leases`. Copy all of them, with Kea
stopped so nothing is leased after the snapshot, and pipe them host to host
so no copy is left on the workstation:

```sh
ssh router 'sudo systemctl stop kea-dhcp4-server'   # stays stopped: standby disables it
ssh router "sudo sh -c 'cd /var/lib/private/kea && tar -cf - dhcp4.leases*'" \
  | ssh elitedesk "sudo sh -c 'install -d -m 0700 /var/lib/private/kea \
      && rm -f /var/lib/private/kea/dhcp4.leases* \
      && tar -C /var/lib/private/kea -xf -'"
```

systemd chowns the directory to Kea's dynamic user when Kea starts.

### 3. Demote router, then promote elitedesk

Order matters: **router's WAN must be down before elitedesk's comes up**,
because the modem has one lease.

```sh
# on router (via 10.10.10.1)
sudo systemd-run --unit=failover --collect \
  /run/current-system/specialisation/standby/bin/switch-to-configuration test
```

**Gate:** do not go on until router's switch has finished (`journalctl -u
failover` ends with the activation) and router answers on `10.10.10.2`, with
`ip -br link show enp6s17` DOWN and no `10.10.10.1` in `ip -br addr`.

```sh

# on elitedesk (via 10.10.10.4)
sudo systemd-run --unit=failover --collect \
  /run/current-system/specialisation/primary/bin/switch-to-configuration test
```

Then on elitedesk (now at `10.10.10.1`):

```sh
ip -br addr show enp1s0f0np0          # 10.10.10.1/16 only
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

The same order in reverse: elitedesk lets go completely before router takes
over again.

```sh
# on elitedesk (via 10.10.10.1): back to standby, which drops the WAN,
# 10.10.10.1 and Kea; it comes back on 10.10.10.4
sudo systemd-run --unit=failback --collect \
  /nix/var/nix/profiles/system/bin/switch-to-configuration test
```

**Gate:** on elitedesk (via `10.10.10.4`), `journalctl -u failback` shows the
activation finished, `ip -br link show enp1s0f1np1` is DOWN, `ip -br addr`
has no `10.10.10.1`, `systemctl is-active kea-dhcp4-server` is inactive and
`cat /run/router-ha/role` reads `backup`. Only then:

```sh
# hand the leases elitedesk issued back to router while router's Kea is off
ssh elitedesk "sudo sh -c 'cd /var/lib/private/kea && tar -cf - dhcp4.leases*'" \
  | ssh router "sudo sh -c 'rm -f /var/lib/private/kea/dhcp4.leases* \
      && tar -C /var/lib/private/kea -xf -'"

# on router (via 10.10.10.2): back to primary
sudo systemd-run --unit=failback --collect \
  /nix/var/nix/profiles/system/bin/switch-to-configuration test

# on elitedesk, once router holds 10.10.10.1 again: demote the DNS zones
# (the owner checks that router answers before handing them back)
sudo systemctl stop technitium-zone-ha-owner
```

Then confirm that router holds 10.10.10.1, the WAN lease and the prefix, and
that Kea is running.

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
