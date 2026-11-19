# Router Failover Rehearsal Runbook

Status: **Runbook and Rehearsal Results Log Template**  
Related design: [`docs/router-election.md`](router-election.md)  
Related beads: `nch-sny.27` (rehearsal runbook), `nch-sny.26` (router aspect), `nch-sny.22` (router migration)

---

## 1. Purpose and Safety Boundaries

This runbook defines the exact procedure for rehearsing a router failover from the active primary router (`router`) to the standby router (`elitedesk`), verifying full network subsystem operation, and performing a controlled failback.

### Golden Safety Rules

1. **Never rehearse without operator console access**: Both routers must be accessible over the out-of-band management plane (`192.168.100.x`) or direct physical/VNC console before starting.
2. **Never duplicate configuration in logs**: The results log at the end of this document must record **observations, metrics, and timestamps only**. All configuration references must link directly to git commits and file paths.
3. **Never allow dual WAN link activation**: The ISP modem provides a single public DHCP lease locked to the Golden MAC (`02:76:c6:01:2a:b0`). At no time may both `router` and `elitedesk` have their WAN interfaces `UP` simultaneously.
4. **Deploy through deploy-rs**: All changes to router configuration must be committed locally and deployed using `deploy-rs` with magic rollback enabled.

---

## 2. Physical Setup and Topology Reference

```
                      ┌──────────────────────┐
                      │      ISP Modem       │
                      │ (Single DHCP/PD lease│
                      │  locked to Gold MAC) │
                      └──────────┬───────────┘
                                 │ RJ45
                                 ▼
                      ┌──────────────────────┐
                      │   Unmanaged Switch   │
                      │ (Isolated WAN Layer 2│
                      │   Broadcast Domain)  │
                      └────┬────────────┬────┘
           RJ45 (Copper)   │            │ RJ45 (2.5 Gbps)
             2.5 Gbps      │            │
                           ▼            ▼
             ┌───────────────────┐    ┌─────────────────────┐
             │       router      │    │    Second Switch    │
             │   (enp6s17 / igc) │    │  (Media Converter)  │
             └───────────────────┘    └──────────┬──────────┘
                                                 │ 10G-SR Fibre
                                                 ▼
                                      ┌─────────────────────┐
                                      │      elitedesk      │
                                      │ (enp1s0f0 / X520-2) │
                                      └─────────────────────┘
```

- **WAN Layer 2 Domain**: Dedicated unmanaged switch; completely isolated from LAN traffic.
- **`router` WAN**: Intel igc copper 2.5 Gbps port (`enp6s17`).
- **`elitedesk` WAN**: Intel X520-2 port 0 (`enp1s0f0`), connected via 10G-SR optical transceiver to a media converter switch running at 2.5 Gbps. Effective bandwidth: 2.5 Gbit/s.
- **Golden WAN MAC**: `02:76:c6:01:2a:b0`.
- **LAN Virtual IP (VIP)**: `10.10.10.1/16` floating on `enp6s16` (`router`) and `enp1s0f1` (`elitedesk`).
- **Management Plane**: Dedicated `192.168.100.0/24` network on `ens18` (`router`, `192.168.100.100`) and `eno1` (`elitedesk`, `192.168.100.98`).

---

## 3. Preconditions and Verification Checklist

Before initiating any failover test, complete and check every item below:

### 3.1 Out-of-band Management Access
- [ ] Connect to `router` over management plane:
  ```bash
  ssh deepwatrcreatur@192.168.100.100 "hostname && ip -br addr show dev ens18"
  ```
- [ ] Connect to `elitedesk` over management plane:
  ```bash
  ssh deepwatrcreatur@192.168.100.98 "hostname && ip -br addr show dev eno1"
  ```
- [ ] Confirm emergency console access is available (Proxmox web console for `router`, physical monitor/keyboard or AMT for `elitedesk`).

### 3.2 Git and Deployment State Parity
- [ ] Check deployed commit on both nodes to ensure matching generations:
  ```bash
  ssh deepwatrcreatur@192.168.100.100 "cat /run/current-system/nixos-version"
  ssh deepwatrcreatur@192.168.100.98 "cat /run/current-system/nixos-version"
  ```
- [ ] Verify both nodes were built from the same git commit and flake lock. Record the git commit SHA in the results log.

### 3.3 Standby Baseline Health Inspection (on `elitedesk`)
- [ ] WAN interface is administratively `DOWN`:
  ```bash
  ssh deepwatrcreatur@192.168.100.98 "ip -br link show dev enp1s0f0"
  # Expected: enp1s0f0 DOWN ...
  ```
- [ ] LAN VIP (`10.10.10.1/16`) is **absent** from `elitedesk`:
  ```bash
  ssh deepwatrcreatur@192.168.100.98 "ip -br addr show dev enp1s0f1"
  # Expected: enp1s0f1 UP 10.10.10.4/16 (VIP 10.10.10.1 MUST NOT be present)
  ```
- [ ] VRRP runtime role state is `backup`:
  ```bash
  ssh deepwatrcreatur@192.168.100.98 "cat /run/router-ha/role"
  # Expected: backup
  ```
- [ ] Single-active units are **inactive** on standby:
  ```bash
  ssh deepwatrcreatur@192.168.100.98 "systemctl is-active kea-dhcp4-server.service inadyn.service miniupnpd.service router-ipv6-ra-owner.service"
  # Expected: all return inactive
  ```
- [ ] Reverse path filtering is configured as loose (`rp_filter = 2`):
  ```bash
  ssh deepwatrcreatur@192.168.100.98 "sysctl net.ipv4.conf.all.rp_filter net.ipv4.conf.default.rp_filter"
  ```

### 3.4 Monitoring Station Setup
- [ ] On a test workstation connected to the LAN (e.g. `emerald` or `phoenix`), launch continuous ping sessions in separate terminal windows:
  ```bash
  # Monitor Gateway VIP reachability
  ping -i 0.2 10.10.10.1 | while read pong; do echo "$(date +%T.%N) $pong"; done

  # Monitor External IPv4 reachability
  ping -i 0.5 1.1.1.1 | while read pong; do echo "$(date +%T.%N) $pong"; done

  # Monitor External IPv6 reachability
  ping -6 -i 0.5 2606:4700:4700::1111 | while read pong; do echo "$(date +%T.%N) $pong"; done
  ```
- [ ] On `elitedesk` (via management SSH), start journal monitor:
  ```bash
  journalctl -f -u keepalived -u systemd-networkd -u kea-dhcp4-server
  ```

---

## 4. Rehearsal Execution Steps

### Stage 1: Record Baseline Metrics (Primary Active)
1. On `router`, query and record:
   - Current WAN IPv4 address and subnet: `ip -br addr show dev enp6s17`
   - Current default IPv4 route: `ip route show default dev enp6s17`
   - Delegated IPv6 prefix: `networkctl status enp6s17 | grep -i prefix`
   - Active DHCP leases count: `wc -l /var/lib/kea/kea-leases4.csv`
   - Current DNS resolution latency: `dig @10.10.10.1 google.com | grep "Query time"`

### Stage 2: Triggering Failover (Primary Demotion)
Simulate a primary failure or maintenance by stopping Keepalived on `router`:
```bash
ssh deepwatrcreatur@192.168.100.100 "sudo systemctl stop keepalived"
```

*Note: Stopping Keepalived triggers `keepalivedStopScript` (ExecStopPost), which demotes the node, releases the WAN link, and flushes conntrack state before `elitedesk` promotes.*

### Stage 3: Observing Standby Takeover (`elitedesk`)
Within 3 seconds of missed VRRP advertisements:
1. `elitedesk` transitions to `MASTER`.
2. `notify_master` script runs:
   - Sets `/run/router-ha/role` to `master`.
   - Commits replicated firewall state: `conntrackd -c`.
   - Clones Golden MAC: `ip link set enp1s0f0 address 02:76:c6:01:2a:b0`.
   - Brings WAN link up: `ip link set enp1s0f0 up`.
   - Restarts `systemd-networkd` to initiate DHCPv4 client and DHCPv6-PD.
   - Starts single-active units: `kea-dhcp4-server`, `inadyn`, `miniupnpd`, `router-ipv6-ra-owner`.
3. Keepalived adds `10.10.10.1/16` to `enp1s0f1` and emits gratuitous ARP.

---

## 5. Subsystem Observation and Acceptance Criteria

Run through the observation checklist immediately after promotion:

### 5.1 LAN Gateway Observation
- **Check VIP Assignment**:
  ```bash
  ssh deepwatrcreatur@192.168.100.98 "ip -br addr show dev enp1s0f1"
  ```
  *Acceptance*: `10.10.10.1/16` is bound to `enp1s0f1`.
- **Check Client ARP Cache**:
  On LAN test client:
  ```bash
  ip neigh show 10.10.10.1
  ```
  *Acceptance*: Hardware address matches `elitedesk` LAN MAC (`90:e2:ba:7f:e0:3d`).
- **Ping Loss Window**:
  Inspect continuous ping to `10.10.10.1`.
  *Acceptance*: Packet loss window is under 3 seconds.

### 5.2 WAN Connectivity Observation
- **Check WAN Link State and Cloned MAC**:
  ```bash
  ssh deepwatrcreatur@192.168.100.98 "ip -br link show dev enp1s0f0"
  ```
  *Acceptance*: State is `UP`; MAC address is exactly `02:76:c6:01:2a:b0`.
- **Check WAN DHCP Lease Acquisition**:
  ```bash
  ssh deepwatrcreatur@192.168.100.98 "ip -br addr show dev enp1s0f0; ip route show default dev enp1s0f0"
  ```
  *Acceptance*: Public IPv4 lease is bound, and default gateway routes via `enp1s0f0`.
- **Check Outbound IPv4 Connectivity**:
  ```bash
  ssh deepwatrcreatur@192.168.100.98 "ping -c 3 1.1.1.1"
  ```
  *Acceptance*: 0% packet loss to external internet targets.

### 5.3 IPv6 Prefix Delegation and SLAAC Observation
- **Check DHCPv6-PD Acquisition**:
  ```bash
  ssh deepwatrcreatur@192.168.100.98 "networkctl status enp1s0f0"
  ```
  *Acceptance*: Delegated prefix is assigned by ISP modem.
- **Check LAN IPv6 Address and Router Advertisements**:
  ```bash
  ssh deepwatrcreatur@192.168.100.98 "ip -6 -br addr show dev enp1s0f1; systemctl is-active router-ipv6-ra-owner.service"
  ```
  *Acceptance*: LAN interface has a global IPv6 address from the delegated prefix; `router-ipv6-ra-owner` is `active`.
- **Check LAN Client SLAAC Routing**:
  On LAN test client:
  ```bash
  ip -6 route show default
  ping -6 -c 3 2606:4700:4700::1111
  ```
  *Acceptance*: Client defaults to `elitedesk` link-local address; outbound IPv6 ping succeeds.

### 5.4 DHCP Leases Observation
- **Check Kea Daemon Status**:
  ```bash
  ssh deepwatrcreatur@192.168.100.98 "systemctl status kea-dhcp4-server.service --no-pager"
  ```
  *Acceptance*: `active (running)` without socket initialization errors.
- **Fresh Client Lease Test**:
  From an unassigned client device or test VM:
  ```bash
  sudo dhclient -r && sudo dhclient -v
  ```
  *Acceptance*: Client receives `DHCPOFFER` and `DHCPACK` with gateway `10.10.10.1` and DNS `10.10.10.1`.
- **Lease Database Invariant**:
  ```bash
  ssh deepwatrcreatur@192.168.100.98 "tail -n 10 /var/lib/kea/kea-leases4.csv"
  ```
  *Acceptance*: The new lease is recorded in the CSV lease store.

### 5.5 DNS Resolution Observation
- **Check Resolver Availability**:
  ```bash
  dig @10.10.10.1 google.com +short
  dig @10.10.10.1 router.deepwatercreature.com +short
  ```
  *Acceptance*: Both public recursion and internal homelab domain queries answer successfully.
- **Check Dynamic DNS Service**:
  ```bash
  ssh deepwatrcreatur@192.168.100.98 "systemctl status inadyn.service --no-pager"
  ```
  *Acceptance*: Inadyn successfully updates Cloudflare records if the external IP changed.

---

## 6. Failback Rehearsal Procedure

Once standby operation is verified, execute a controlled failback:

### Stage 1: Restart Primary Keepalived
On `router`:
```bash
ssh deepwatrcreatur@192.168.100.100 "sudo systemctl start keepalived"
```

### Stage 2: Observe Preemption Dynamics
- If `elitedesk` has higher priority (e.g. 110 vs 100), `elitedesk` **remains MASTER** and `router` joins as `BACKUP`. This proves higher-priority bare-metal preference.
- To test failback onto `router`, gracefully stop Keepalived on `elitedesk`:
  ```bash
  ssh deepwatrcreatur@192.168.100.98 "sudo systemctl stop keepalived"
  ```

### Stage 3: Demotion Verification on Standby (`elitedesk`)
Verify `notify_backup` / `keepalivedStopScript` on `elitedesk`:
- [ ] WAN interface immediately set to `DOWN`:
  ```bash
  ssh deepwatrcreatur@192.168.100.98 "ip -br link show dev enp1s0f0"
  # Must report DOWN
  ```
- [ ] Single-active units stopped:
  ```bash
  ssh deepwatrcreatur@192.168.100.98 "systemctl is-active kea-dhcp4-server.service"
  # Must report inactive
  ```
- [ ] VIP released from LAN interface:
  ```bash
  ssh deepwatrcreatur@192.168.100.98 "ip -br addr show dev enp1s0f1"
  # 10.10.10.1 must be gone
  ```

### Stage 4: Promotion Verification on Primary (`router`)
Verify `router` resumes full master responsibilities:
- [ ] VIP bound to `enp6s16`.
- [ ] WAN brought up on `enp6s17` with Golden MAC.
- [ ] Single-active units restarted.
- [ ] Measure total failback transition time and packet loss count on monitoring terminal.

### Stage 5: Normalization
Restart Keepalived on `elitedesk` so it resumes standby posture (`BACKUP`):
```bash
ssh deepwatrcreatur@192.168.100.98 "sudo systemctl start keepalived"
```

---

## 7. Rehearsal Results Log Template

> **Instructions for Operator**: Complete this section during and immediately following the rehearsal.  
> **RULE**: Do NOT paste raw configuration blocks. Link commit SHAs and repository file paths instead.

### 7.1 Rehearsal Metadata

| Attribute | Recorded Value |
|---|---|
| **Rehearsal Date & Time** | YYYY-MM-DD HH:MM UTC |
| **Lead Operator** | [Name / Handle] |
| **Reviewer / Witness** | [Name / Handle] |
| **Repository Git Commit** | [`[SHA-hash]`](file:///home/deepwatrcreatur/orca/workspaces/main/router-docs) |
| **Primary Node Tested** | `router` (Proxmox VM, management `192.168.100.100`) |
| **Standby Node Tested** | `elitedesk` (HP EliteDesk bare-metal, management `192.168.100.98`) |
| **Config Source File** | [`modules/hosts/elitedesk.nix`](file:///home/deepwatrcreatur/orca/workspaces/main/router-docs/modules/hosts/elitedesk.nix) |
| **Inventory Source File** | [`inventory/hosts.nix`](file:///home/deepwatrcreatur/orca/workspaces/main/router-docs/inventory/hosts.nix) |

### 7.2 Quantitative Measurement Matrix

| Subsystem / Metric | Target Threshold | Measured Value | Result (Pass / Fail) |
|---|---|---|---|
| **LAN VIP Migration Time** | < 3.0 seconds | ___ s | [ ] Pass  [ ] Fail |
| **LAN Ping Packet Loss** | < 5 packets dropped | ___ packets | [ ] Pass  [ ] Fail |
| **WAN Link Activation Time** | < 5.0 seconds | ___ s | [ ] Pass  [ ] Fail |
| **WAN DHCP Acquisition Time** | < 15.0 seconds | ___ s | [ ] Pass  [ ] Fail |
| **WAN Leased IPv4 Address** | Valid Public IP | ___.___.___.___ | [ ] Pass  [ ] Fail |
| **IPv6 Prefix Delegation** | Valid /56 or /64 | 2001:___ /___ | [ ] Pass  [ ] Fail |
| **IPv6 Client SLAAC Acquisition** | < 10.0 seconds | ___ s | [ ] Pass  [ ] Fail |
| **Fresh DHCP Lease Delivery** | < 2.0 seconds | ___ s | [ ] Pass  [ ] Fail |
| **DNS Resolution Latency** | < 50 ms | ___ ms | [ ] Pass  [ ] Fail |
| **Failback Switchover Time** | < 5.0 seconds | ___ s | [ ] Pass  [ ] Fail |
| **Total Service Disruption** | < 15.0 seconds | ___ s | [ ] Pass  [ ] Fail |

### 7.3 Detailed Subsystem Observations

#### LAN Gateway
- **VIP Migration Timestamp**: `HH:MM:SS.mmm`
- **ARP Table Observation**: [Record observed ARP hardware address and time to update on LAN client]
- **Notes**:

#### WAN Interface
- **Cloned MAC Verification**: `02:76:c6:01:2a:b0` [Confirmed / Divergent]
- **ISP Modem Response**: [Note if modem required a power cycle or leased immediately]
- **Notes**:

#### IPv6 Prefix Delegation
- **Delegated Prefix Received**: `[Prefix/Len]`
- **RA Delivery**: [Confirmed Router Advertisements received by client with matching prefix]
- **Notes**:

#### DHCP Leases
- **Kea Startup Duration**: `___ ms`
- **Fresh Client Test**: [IP address assigned to test client]
- **Lease Continuity**: [Confirmed existing client renewals or noted drops]
- **Notes**:

#### DNS Resolution
- **Internal Resolution**: [Confirmed `router.deepwatercreature.com` -> `10.10.10.1`]
- **External Resolution**: [Confirmed external lookup]
- **DDNS Update Status**: [Recorded inadyn journal log output]
- **Notes**:

#### Failback & Return to Normal
- **Preemption Behavior**: [Documented if higher priority preempted immediately or obeyed delay]
- **Demotion Cleanness**: [Confirmed standby WAN link down and Kea stopped]
- **Notes**:

### 7.4 Anomalies, Log Excerpts, and Follow-Up Items

```
[Record any unexpected journal warnings, timeouts, or transient packet drops here]
```

- **Identified Issues**:
  - Issue 1: ...
- **Follow-up Beads Created**:
  - `nch-sny.XX`: ...
