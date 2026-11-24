# Router Failover Rehearsal Runbook

Bead: `nch-sny.36`. Design and the later VRRP plan:
[`router-election.md`](router-election.md).

VRRP is not running yet, so failover is **manual**. Each router carries the
other role as a NixOS specialisation:

| Host | Normal role | Specialisation | Defined in |
| --- | --- | --- | --- |
| `router` (bare metal) | primary | `standby` | unified `hosts/nixos/router/standby-specialisation.nix` |
| `elitedesk` (bare metal) | standby | `primary` | this repo, `modules/aspects/router-role.nix` (`routerRole.promoted`) |

Roles move with `switch-to-configuration test`, never `switch` or `boot`. No
deploy happens during a rehearsal.

What a reboot does differs per host:

- **elitedesk** reboots into standby. If it was primary, the network loses its
  gateway until router is promoted again.
- **router** remembers that it was demoted. Standby activation writes
  `/var/lib/router-failover/demoted`, and a boot guard keeps a reset router off
  the WAN and `10.10.10.1` until someone runs its primary
  `switch-to-configuration test` (unified
  `docs/router-source-of-truth.md#a-reboot-of-a-demoted-router-stays-demoted`,
  nch-sny.36.2). Rehearsal 1 had no guard: the router was reset, came back
  primary and both routers were active.

**Stop conditions, at every step:** a `switch-to-configuration` that exits
non-zero (each switch runs as its own unit; see
[Access during the rehearsal](#access-during-the-rehearsal)), a gate that does
not pass within its timeout, or anything unexpected. Then go to [Abort](#abort).

**Do not reset or reboot the demoted router during the window.** To abort
when SSH is gone, use router's console (monitor and keyboard) and run the
commands under Abort; a reset is the last resort.

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

- The operator is present, with console access: a monitor and keyboard for
  both router (bare metal since its move off Proxmox) and elitedesk.
- Both hosts run their **current generation**, not an older one picked from
  the boot menu: an older generation carries older specialisations
  (rehearsal 3). `preflight.sh` checks this, that elitedesk is a clean
  standby, that router has no demoted marker, and that both are idle.
- Router's own LAN settings in standby come from unified
  `docs/router-source-of-truth.md#which-file-configures-the-lan` (unified
  #262 or later deployed).
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
activation halfway. Give each switch its own unit name, and keep the unit
after it exits (`--remain-after-exit`, no `--collect`) so its exit status can
still be read when you reconnect on the new address:

```sh
sudo systemd-run --unit=<name> --remain-after-exit <path>/bin/switch-to-configuration test
journalctl -u <name> -f
systemctl show -p SubState,Result,ExecMainStatus <name>
# pass: SubState=exited, Result=success, ExecMainStatus=0
# SubState=running means activation is still going: wait, do not proceed
```

Unit names used below: `fo-demote` and `fo-promote-N` (cutover),
`fb-elitedesk-N` and `fb-router-N` (fail back), `ab-elitedesk-N` and
`ab-router-N` (abort), `rescue-promote-N` (elitedesk promoted again because
router could not take over). `N` counts retries: a switch that fails with
`Could not acquire lock` is retried once the host is idle. After the window,
clear them with `sudo systemctl stop <name>` and `sudo systemctl reset-failed`.

## Procedure

Run the rehearsal with the scripts in
[`scripts/router-failover/`](../scripts/router-failover/), from a LAN
workstation in Bash. They run the commands in the steps below, gate every
step with a timeout, and **abort automatically when a gate fails**: a failed
demote puts router back to primary; a failed promotion or fail back returns
to whichever host can hold the gateway, and promotes elitedesk again if
router cannot. In rehearsals 2 and 3 the operator's script stopped on a
failed gate and left the network with no gateway for 15 and 18 minutes.

```sh
eval "$(scripts/router-failover/preflight.sh | tail -1)"   # sets FAILOVER_DIR
scripts/router-failover/cutover.sh
# observe (step 4)
scripts/router-failover/failback.sh
```

Each run logs to `$FAILOVER_DIR/rehearsal.log`. To exercise an abort path
on purpose, set `FAILOVER_FORCE_FAIL` to `demote`, `promote`,
`fb-elitedesk` or `fb-router`: that gate fails after its action ran, so the
abort runs for real (a short outage). The manual commands below remain the
reference for the consoles.

### 1. Baseline (router primary)

Start the monitors on the workstation as transient user units, so they
survive a dropped terminal and write to files. In rehearsal 1 backgrounded
pings died at the cutover and recorded nothing.

```sh
loginctl show-user "$USER" -p Linger     # must be Linger=yes, or the
                                         # monitors stop with the last session
# if not: sudo loginctl enable-linger "$USER"
d=~/failover-$(date +%F-%H%M); mkdir -p "$d"
systemd-run --user --unit=fo-gw   sh -c "ping -D -O -i 0.2 10.10.10.1 > $d/gw.log 2>&1"
systemd-run --user --unit=fo-v4   sh -c "ping -D -O -i 0.5 1.1.1.1 > $d/v4.log 2>&1"
systemd-run --user --unit=fo-v6   sh -c "ping -6 -D -O -i 0.5 2606:4700:4700::1111 > $d/v6.log 2>&1"
# afterwards: systemctl --user stop fo-gw fo-v4 fo-v6
```

`-O` logs every missed reply, so gaps can be read off the timestamps.

On router, record the WAN IPv4 address (`ip -br addr show enp6s17`), the
delegated prefix (`journalctl -u systemd-networkd | grep 'delegated prefix' | tail -1`)
and the lease count
(`sudo sh -c 'cat /var/lib/private/kea/dhcp4.leases* | wc -l'`).

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
sudo systemd-run --unit=fo-demote --remain-after-exit \
  /run/current-system/specialisation/standby/bin/switch-to-configuration test
```

**Gate (timeout 60 s):** router's switch has finished with status 0
(`systemctl show -p SubState,Result,ExecMainStatus fo-demote` reads
`exited`, `success`, `0`; rehearsal 1 exited 4, nch-sny.36.1), router answers on `10.10.10.2`,
`ip -br link show enp6s17` is DOWN, there is no `10.10.10.1` in `ip -br addr`,
and `/var/lib/router-failover/demoted` exists. Promote elitedesk **at once**:

```sh
# on elitedesk (via 10.10.10.4)
sudo systemd-run --unit=fo-promote --remain-after-exit \
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
sudo systemd-run --unit=fb-elitedesk --remain-after-exit \
  /nix/var/nix/profiles/system/bin/switch-to-configuration test
```

**Gate:** on elitedesk (via `10.10.10.4`), `fb-elitedesk` finished with
`SubState=exited`, `Result=success` and `ExecMainStatus=0`, `ip -br link show enp1s0f1np1` is DOWN, `ip -br addr`
has no `10.10.10.1`, `systemctl is-active kea-dhcp4-server` is inactive and
`cat /run/router-ha/role` reads `backup`. Give elitedesk's WAN port its own
MAC back (standby leaves router's MAC on the down link):

```sh
sudo ip link set enp1s0f1np1 address "$(ethtool -P enp1s0f1np1 | awk '{print $3}')"
```

Only then:

```sh
# before router's Kea serves again: every lease router still had active must
# also be in elitedesk's files, for the same client. Compare first, because
# the copy below replaces router's files. The files are an append log with
# superseded records (and Kea's cleanup may compact elitedesk's), so reduce
# each side to the latest record per address; for router keep only leases
# that have not expired.
latest='{ if ($1 != "address" && $5 >= until[$1]) { until[$1] = $5; mac[$1] = $2 } }
        END { for (a in until) if (!active || until[a] > systime()) print a "," mac[a] }'
set -o pipefail
ssh router "sudo sh -c 'cat /var/lib/private/kea/dhcp4.leases*'" \
  | gawk -F, -v active=1 "$latest" | sort > /tmp/r.leases || echo STOP: router read failed
ssh elitedesk "sudo sh -c 'cat /var/lib/private/kea/dhcp4.leases*'" \
  | gawk -F, -v active=0 "$latest" | sort > /tmp/e.leases || echo STOP: elitedesk read failed
wc -l /tmp/r.leases /tmp/e.leases        # both non-empty; router's near the baseline
comm -23 /tmp/r.leases /tmp/e.leases     # must print nothing; otherwise stop
comm -13 /tmp/r.leases /tmp/e.leases     # leases elitedesk issued or renewed

# hand the leases elitedesk issued back to router while router's Kea is off
ssh elitedesk "sudo sh -c 'cd /var/lib/private/kea && tar -cf - dhcp4.leases*'" \
  | ssh router "sudo sh -c 'rm -f /var/lib/private/kea/dhcp4.leases* \
      && tar -C /var/lib/private/kea -xf -'"

# on router (via 10.10.10.2): back to primary; this also clears the
# demoted marker
sudo systemd-run --unit=fb-router --remain-after-exit \
  /nix/var/nix/profiles/system/bin/switch-to-configuration test
systemctl show -p SubState,Result,ExecMainStatus fb-router   # exited, success, 0

# bounce router's WAN once the switch has finished: after the MAC moved
# back in rehearsal 1 the ISP gateway did not answer until the link went
# down and up
sudo ip link set enp6s17 down && sleep 2 && sudo ip link set enp6s17 up
sudo networkctl reconfigure enp6s17

# on elitedesk, once router holds 10.10.10.1 again: demote the DNS zones
# (the owner checks that router answers before handing them back)
sudo systemctl stop technitium-zone-ha-owner
```

Then confirm that router holds 10.10.10.1, the WAN lease and the prefix
(within 60 s of the bounce), that Kea is running, and that
`/var/lib/router-failover/demoted` is gone.

## Abort

At any step, return both hosts to normal in this order:

1. elitedesk, detached (WAN down, LAN 10.10.10.4 only, Kea off), then
   check `ab-elitedesk` from `10.10.10.4`. Then demote its zones and give its
   WAN port its own MAC back; returning to standby does neither:

   ```sh
   sudo systemd-run --unit=ab-elitedesk --remain-after-exit \
     /nix/var/nix/profiles/system/bin/switch-to-configuration test
   sudo systemctl stop technitium-zone-ha-owner
   sudo systemctl start technitium-zone-ha-reconcile   # zones back to Secondary
   sudo ip link set enp1s0f1np1 down
   sudo ip link set enp1s0f1np1 address "$(ethtool -P enp1s0f1np1 | awk '{print $3}')"
   ```

2. Lease handback, only while router's Kea is still stopped
   (`systemctl is-active kea-dhcp4-server` on router reads `inactive`): compare
   and copy elitedesk's leases as in [Fail back](#5-fail-back). If router's Kea
   is already serving (an abort after fail back), skip the copy: it would
   replace newer renewals with stale records.
3. router, detached, then the WAN bounce from [Fail back](#5-fail-back):

   ```sh
   sudo systemd-run --unit=ab-router --remain-after-exit \
     /nix/var/nix/profiles/system/bin/switch-to-configuration test
   ```
4. If SSH is gone, use the consoles (monitor and keyboard on each host) and
   run the same commands. Reboot only as the
   last resort: elitedesk comes back standby, and router comes back standby
   too while its demoted marker exists (remove it from the console with
   `sudo rm /var/lib/router-failover/demoted` before rebooting it). Booting an
   older generation from router's boot menu restores the gateway (it predates
   the guard) but leaves the marker: remove it before the next reboot.

Abort when elitedesk gets no WAN lease within 60 s, internet does not come
back within 2 minutes, or a stop condition is met.

## Results

Record each rehearsal here: date, commits of both repos, measured times and
the anomalies, with links to beads for follow-ups.

### Rehearsal 1: 2026-11-22, aborted

unified 8fc3c0c (#251), clan 254771f (#34). Outage about 14 minutes
(15:43:04 to 15:56:51 EST).

Worked:

- Lease handoff: 78 lines, including `dhcp4.leases.2`.
- router standby: WAN down, `10.10.10.2`, Kea, UPnP and inadyn off.
- elitedesk primary got the **same IPv4** (99.237.231.178/23) from the modem
  with router's MAC, DUID and IAID; Kea came up, the zones were promoted
  through the role file, internet from elitedesk at 16 ms.

Failed:

1. router's standby switch exited 4 (`inadyn.timer` had a bad unit file
   setting) although the role change applied. Fixed in unified #260
   (nch-sny.36.1); a non-zero exit is now a stop condition.
2. The router VM was hard-reset from outside at 15:47:16 and 15:47:53, booted
   primary at 15:49:11 and took `10.10.10.1` and the WAN back while elitedesk
   was being promoted at 15:50:44 (late: the operator session to router had
   stalled). Both routers were active; aborted at 15:52:24 by returning
   elitedesk to standby. Fixed by the demoted-boot guard, unified #261
   (nch-sny.36.2), and the "do not reset" rule above.
3. After the abort router's WAN got no reply from the ISP gateway until its
   link was bounced (15:56:37). The bounce is now part of fail back and abort.
4. The workstation ping monitors died at the cutover. They now run as
   transient user units that log to files.

Cleanup after the abort: elitedesk's zones back to Secondary (reconcile), its
WAN MAC reset to its own, and all 8 leases it issued copied into router's Kea.

### Rehearsal 2: 2026-11-23, cutover passed, fail back failed

unified 2eccceae (#260, #261), clan 2b5c77c (#41).

Worked:

- Cutover: `fo-demote` exited 0, elitedesk promoted 6 s later with the same
  IPv4 and `/56`. Gateway gap 4.4 s, IPv4 internet gap 5.0 s. Kea served
  leases, DNS answered, zones promoted.
- Boot guard: router rebooted while demoted came back with the WAN down and
  only `10.10.10.2`; `10.10.10.1` stayed on elitedesk's MAC throughout.

Failed:

1. IPv6 gap 83 s: the demoted router kept sending RAs. Its standby
   overrides sat on a network file networkd ignores; fixed in unified #262.
2. The router (bare metal, not the Proxmox VM the runbook assumed) waited in
   its boot menu until the operator picked an entry; cause not found
   (`timeout: 5`, default entry correct).
3. Fail back: the boot-time standby activation was still running (90 s
   `tailscaled-autoconnect` timeout: standby had no default route, unified
   #262). `fb-router` failed at once with `Could not acquire lock` after
   elitedesk had already let go, and the operator script waited on the wrong
   address instead of retrying or aborting. No gateway from 22:28:17 to
   22:43:17, until the operator booted an older router generation.

### Rehearsal 3: 2026-11-24, aborted at the demote

Same commits. The router had been running an older generation since the
recovery; it was switched back to its current one with `test`.

1. `fo-demote` exited 4: the switch started the boot guard (not yet running
   on that boot), which found the marker the activation had just written and
   failed. The role change itself applied. Fixed in unified #262: the guard
   acts only while booting.
2. The operator script stopped on the failed gate without aborting: no
   gateway from 06:31:42 to 06:49:21, until the operator booted an older
   router generation. Generation 28 restored IPv4 but emerald had no DNS
   (it resolves through Tailscale); a later one restored everything.
3. The scripts are now in `scripts/router-failover/` and abort on every
   failed gate. The marker left behind by both recoveries was removed by
   hand.
