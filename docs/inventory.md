# Host inventory

`inventory/hosts.nix` is the source for homelab host identity, connectivity,
classification, and per-host router hardware. `modules/inventory.nix` adds
derived identity and deployment fields; `inventory-matches-unified` checks
the legacy overlap while Unified remains authoritative for unmigrated systems.

| Field | Source | Readers |
| --- | --- | --- |
| Inventory key | Attribute name in `inventory/hosts.nix` | `homelab.hosts`, den host composition, Clan machine names, deploy outputs |
| `kind`, `system` | `inventory/hosts.nix` | den host definitions, Clan machine platform, inventory parity check |
| `addresses.ip`, `addresses.hostname`, `addresses.sshHostname` | `inventory/hosts.nix` | Read-only `sshTarget`, router role, user SSH config, Clan and deploy targets |
| `sshTarget` | Derived from `addresses.sshHostname`, then `addresses.hostname`, then `addresses.ip` | Clan target, deploy-rs target, fleet deploy and status, user SSH config |
| `inventoryName`, `fqdn`, `sshHostKeyAlias` | Derived from inventory key and `homelab.domain` | Clan target, deploy-rs, fleet deploy/status, managed SSH config |
| `sshUser` | `inventory/hosts.nix` (default `deepwatrcreatur`) | Clan target, fleet deploy/status, managed SSH config, parity check |
| `aliases` | `inventory/hosts.nix` | Managed SSH config, cache alias validation, parity check |
| `cacheAliases` | `inventory/hosts.nix` | Builder/cache host parity with Unified |
| `description` | `inventory/hosts.nix` | Inventory parity with Unified |
| `roles` | `inventory/hosts.nix` | Clan tags, den role composition, deployment backend derivation, router-class and builder grouping checks |
| `deployBackend` | Derived from `roles` (`router` uses deploy-rs; other roles use Clan) | `fleet-deploy` dispatch |
| `router` | `inventory/hosts.nix` | Router-role composition, topology, router validation checks |
| `router.ddnsServices` | `inventory/hosts.nix` | Cloudflare DDNS labels in the router role; parity check against Unified |
| `dhcpReservation` | `inventory/hosts.nix` | Kea reservation generation; parity check against Unified |
| `homelab.networks` | `inventory/networks.nix` | Router LAN and management subnets |
| `includeSsh` | `inventory/hosts.nix` | Managed user SSH config and known-host generation, parity check |
| `archived` | `inventory/hosts.nix` | Active inventory and deployment filtering |
| `clanCandidate`, `migrated` | `inventory/hosts.nix` | Offline candidate checks, Clan composition and deployment gating |

`includeDns` was removed: no DNS renderer consumes it, so the flag only made
the parity comparison track data with no effect. DNS records are owned by the
Technitium zone configuration; DHCP reservations use each host's explicit
`dhcpReservation` plus `addresses.ip`.

The router aspect now reads DHCP reservation, Cloudflare DDNS labels, and
subnet facts from NCH inventory. `inventory-matches-unified` checks the
overlapping reservation and DDNS values until their migration bead is closed.
