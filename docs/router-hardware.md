# Router hardware

What the router hosts run on, and how its health is watched.

## elitedesk

| Part | Detail |
|---|---|
| Chassis | HP Compaq Elite 8300 SFF, i7-3770, 16 GB |
| NIC | NVIDIA/Mellanox ConnectX-4 Lx MCX4121A-ACAT (ex-Huawei, crossflashed to stock PSID `MT_2420110034`), firmware 14.32.1912 since 2026-11-20 |
| Slot | CPU x16 slot, link 8 GT/s x8 (63 Gb/s). The chipset slot gave only 5 GT/s x4. |
| LAN | port 0, `enp1s0f0np0`, 5 m passive DAC to the LAN switch |
| WAN | port 1, `enp1s0f1np1`, 10G-SR optic to the WAN switch |
| Management | onboard `eno1` (Intel 82579LM) |
| Cooling | a fan blows directly on the NIC; its chip runs about 56 °C idle and 66 °C with the link up |

The Oracle-branded Intel X520 it replaced dropped off PCIe twice
(nch-sny.31) and lost TCP replies (nch-sny.34). Firmware backups of both
ConnectX cards (elitedesk and emerald) are on emerald in
`~/nic-firmware-backups/`, next to the NVIDIA MFA archive used to update
elitedesk, which has no internet on its management network.

## Monitoring

`router-role` enables `router.monitoring.hardwareSensors` (from
nix-router-optimized; upstream doc `docs/router-hardware-monitoring.md`):

- **Collector:** a timer runs `router-hw-sensors` every minute. It reads the
  ConnectX chip temperature and the SFP diagnostics (module temperature,
  RX/TX optical power) into node_exporter's textfile directory.
- **Dashboard:** Grafana's "Router Hardware" dashboard (`/d/router-hardware`
  on `grafana.<domain>`) graphs those next to the CPU and board
  temperatures.
- **Thresholds:** NIC chip 85/95 °C, SFP module 70/80 °C. The card's own
  warning and critical thresholds are 95 and 105 °C.

`checks.router-hw-sensors` fails the flake check if a router host loses
the timer, the textfile collector or the dashboard.

Check by hand on a router:

```bash
cat /run/router-hw-sensors/router_hardware.prom
sudo devlink health show            # mlx5 firmware health reporters
sudo lspci -vv -s 01:00.0 | grep LnkSta
```

A virtual router (the current primary on pve-rog) has no ConnectX card or
SFP, so only the hwmon panel shows data there.
