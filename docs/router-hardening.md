# Router hardening

`modules/aspects/router-hardening.nix` is included by `router-role`.

## What comes from upstream

The kernel settings come from nix-router-optimized's
[`router-security-hardened`](https://github.com/deepwatrcreatur/nix-router-optimized/blob/main/docs/router-security-hardened.md)
(`kernelHardening`), following [decision 0003](decisions/0003-upstream-first.md).
It was extended for this repo in nix-router-optimized #191:

- `kptr_restrict`, `dmesg_restrict`, unprivileged BPF off, `bpf_jit_harden`,
  `suid_dumpable = 0`, the `fs.protected_*` sysctls;
- no ICMP redirects or source routes, SYN cookies, RFC 1337;
- uncommon protocol modules (TIPC, RDS, AX.25, X.25 and others) and desktop
  peripherals refused even on explicit `modprobe`;
- `rpFilter = "loose"` here, because VRRP members and a standby routing via
  its peer receive traffic asymmetrically. A `router-rp-filter-reset` unit
  makes a changed value reach existing interfaces without a reboot.

Settings it does not cover stay in the aspect: SSH no longer advertises
keyboard-interactive authentication (PAM already refused it), and the NixOS
option manual is not built.

Ping stays answered (`allowPing` defaults to true); the dashboard and
alerting probe the routers.

## Left out on purpose

The first version of this aspect was selected from
[RGBCube/ncc](https://github.com/RGBCube/ncc/blob/55a077a/modules/linux-kernel.mod.nix).
These ncc settings are still not used:

| ncc setting | Why not here |
| --- | --- |
| `kernel.sysrq = 0`, `sysrq_always_enabled=0` | The console is the routers' recovery path. |
| `lockdown=confidentiality`, `module.sig_enforce=1` | Needs signed modules; blocks tools used to debug the NICs. |
| `net.core.bpf_jit_enable = false`, `kernel.ftrace_enabled = false` | The JIT is on the packet path; `bpf_jit_harden` covers the spraying risk. Tracing is used for NIC faults. |
| `page_poison=1`, `slab_nomerge`, `page_alloc.shuffle=1` | Cost on every packet allocation, unmeasured on the i7-3770. |
| Blacklisted `cifs`, `nfs`, `udf`, `sctp` and others | Used on some hosts, or may be needed by PXE media and VPN work. |

Upstream's default list does block `thunderbolt`, `bluetooth`, `uvcvideo` and
FireWire. Neither router uses them; remove an entry with
`services.router-security-hardened.kernelHardening.blacklistedModules` if one
ever does.

## Rollback

`unprivileged_bpf_disabled = 1` cannot be set back to 0 without a reboot.
The other sysctls apply on activation; a rollback restores only values the old
generation sets, so reboot to return the rest to kernel defaults.
