# nixos-facter reports: review against unified (nch-sny.10)

Reports for the bare-metal NixOS hosts, collected 2026-11-18 with
nixos-facter 0.4.4 (read-only, as root) and committed as
`hardware/<host>.facter.json`. At migration, move the file to
`machines/<host>/facter.json`, where clan picks it up
(`hardware.facter.reportPath`).

GOTCHA: clan treats every directory under `machines/` as a machine, so
reports for hosts that are not clan machines yet must stay out of it.

LXC guests (vaglio, podman, homeserver, authentik-host) have no hardware of
their own and get no report.

## Method

For each host, evaluate a bare NixOS system with only the report
(`hardware.facter.reportPath`) and compare with unified's
`nixosConfigurations.<host>`: initrd modules, `boot.kernelModules`, CPU
microcode, `boot.extraModprobeConfig`.

## Findings

Ignored: btrfs/crc32c/sha256/xxhash64/blake2b and ext2/ext4 differences come
from filesystem config, not hardware.

Facter is better on: AMD microcode updates (emerald and phoenix had them off
in unified; lattitude already on).

Facter cannot provide these; they must move to host or role aspects:

| Host | Keep in config | Why |
| --- | --- | --- |
| elitedesk | `options ixgbe allow_unsupported_sfp=1` | Oracle X520 with third-party SFP+ shows no carrier otherwise |
| elitedesk, router | `options nf_conntrack hashsize=65536`; `act_bpf cls_bpf ifb sch_cake sch_fq sch_fq_codel tcp_bbr` | router role (traffic shaping), not hardware |
| emerald | nvidia modprobe options (`nvidia-drm fbdev=1 modeset=1`, uvm softdep); `zfs`, `tls` | driver policy and role |
| phoenix | `kvm-amd`; `bridge br_netfilter veth xt_nat ctr` | facter does not add KVM; container networking is a role |
| lattitude | `amdgpu`, `r8169` in initrd | early KMS and network in initrd are choices, not detection |
| emerald, lattitude, elitedesk, router | `usb_storage` in initrd | rescue boot from USB; facter only lists present devices |

Facter adds `i915`/`amdgpu`/`nvidia`/`thunderbolt` to the initrd where the
hardware exists; harmless.

## Privacy

Reports contain MAC addresses, disk serials and DMI data. The repo already
publishes MACs (NIC pinning) and disk ids (disko by-id paths); nothing in the
reports is a secret.
