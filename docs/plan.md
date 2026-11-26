# Migration plan

Goal: run the homelab from this repo on [clan-core](https://docs.clan.lol),
keeping [den](https://github.com/denful/den) aspects for host composition, and
retire `unified-nix-configuration` (below: "unified").

The work queue is on the `beads-queue` branch (`beads-q ready`). This file explains the
phases and the decisions the beads refer to.

## What Clan replaces

| Concern | unified today | Here |
| --- | --- | --- |
| Add / install a machine | `just gen-identity`, `just install`, `docs/adding-a-nixos-host.md` | `clan machines create` / `install` (nixos-anywhere + nixos-facter) |
| Hardware config | hand-edited `hardware-configuration.nix` | `facter.json` per machine |
| Secrets | agenix, recipient groups in `secrets.nix`, `just rekey` | clan vars (generators, sops backend); each machine gets only what it declares |
| SSH host trust | `ssh-keys/*-host-*.pub` + nix-ssh-keys-manager known_hosts | clan `sshd` service: CA-signed host certificates |
| Deploy | `nixos-rebuild --target-host` loops | `clan machines update` (deploy-rs for routers if the spike says so) |
| Host composition | den aspects | den aspects (unchanged), fed into `clan.machines.<name>.imports` |
| Inventory | `lib/hosts.nix` + `den/inventory/` + derived lists | one inventory with roles |

## Spike

One disposable VM, `clan-spike`, on pve-rog (a VM, not an LXC: nixos-anywhere
needs kexec and a real disk). Beads `nch-sny.1` to `.6` each answer one
question:

1. Do den-built modules work as clan machine imports? (skeleton)
2. Does `clan machines install` with nixos-facter replace our install flow?
3. Do clan vars coexist with agenix during migration, and how are machines
   added and removed?
4. Does the sshd service remove host-key prompts without a key list?
5. What happens when a deploy breaks networking? Is deploy-rs still needed
   for the routers?
6. Do den's users and Home Manager wiring work under clan; what happens to
   darwin hosts and standalone homes?

The decision bead (`nch-sny.7`) blocks everything else. Its outcome goes in
`docs/decisions/0001-clan.md`.

## Fallback

If Clan is a no-go, stay on unified and adopt the pieces separately:
agenix-rekey (or nixos-artifacts) for secrets, nixos-facter, deploy-rs, an SSH
CA key held as a secret, and a single inventory. The foundation beads keep
their meaning; only their location changes.

## Migration order

Foundations first (inventory, ported aspects, secrets by domain, facter
reports, SSH CA, deploy tooling), then hosts from least to most critical:
vaglio, podman, homeserver, authentik-host, lattitude, phoenix, emerald,
elitedesk, router. unified is archived last.

The workstation rollout starts with Lattitude (`nch-sny.18`), followed by
`pve-strix` (`nch-sny.39`), `pve-rog` (`nch-sny.40`), Phoenix
(`nch-sny.19`), and Emerald (`nch-sny.20`). On the two Proxmox nodes the
scope is the root standalone Home Manager profile. Proxmox VE, storage,
networking, services, and boot configuration stay in place. Lattitude's
repository-only kiosk comparison is tracked in `nch-sny.18.1`.

### Lattitude kiosk comparison

The `lattitude-kiosk` flake check evaluates a den fixture with Lattitude's
disk, hardware and Ethernet modules copied from unified
`5e70e2a069dbb2116e03adf6f2c44a4b2a219848`. The comparison matched the
local Btrfs and EFI mounts and options, wired address, systemd-boot,
Sway autologin, zram, and NixOS and Home Manager state versions.

The fixture reuses the workstation shell and Worktrunk. Unified also
includes the common coding-agent packages, fnox, Bitwarden, rclone sync
helpers, and Fastfetch configuration. The fixture adds the shared Git SSH
doctor and Jujutsu. Qutebrowser is excluded because this nixpkgs pin marks it
insecure. The Lattitude Clan candidate now composes the workstation shell,
developer, and desktop aspects, carries over the Nightscout and Strata system
integrations, and retains Lattitude's kiosk settings. It evaluates both
Synology automounts using `synology-shares/credentials`. Its Clan machine key
and recipients for declared shared vars were generated for Lattitude; Emerald
remains admin-only. The comparison fixture stays outside Clan inventory.
Unified remains in the repository until the migration bead is complete.

### Lattitude live-system comparison

The candidate toplevel was compared read-only against Lattitude's actual
`/run/current-system` (`nixos-system-lattitude-26.05.20260812.9f78f44`), not
Emerald's local generation. The candidate builds as
`nixos-system-lattitude-26.05.20261116.f684076`. It retains the active
Tailscale, CUPS/HP printer queue, Avahi discovery, Snapper snapshots, and
systemd-networkd wait-online behavior. Its wired network file matches the
Realtek MAC and retains `10.10.11.47/16`, DHCP, gateway, and DNS; the Tailscale
networkd file remains present. The two Synology CIFS mounts use automounts and
the Clan credentials file.

The old NixCI netrc copy unit is replaced by the Clan vars path
`/run/secrets/vars/nix-cache-auth/netrc`. The candidate also updates the
kernel from 6.18.44 to 6.18.63 and firmware from 20260810 to 20261019; these
take effect after a reboot. The closure diff contains about 600 package and
unit lines, including the migrated Home Manager tools.

On 2026-11-23 the Clan generation was activated without rebooting Lattitude.
The active system is
`/nix/store/g2m1y9brrqrr2grjw5ng9sqfqnvqkaax-nixos-system-lattitude-26.05.20261116.f684076`.
After activation, `systemctl is-system-running` was `running`, there were no
failed units, and Tailscale, CUPS, Avahi, the primary user's Home Manager,
root's Home Manager, networkd wait-online, both Snapper timers, and the `cloud`
and `storage` CIFS automounts were active. Both HP printer queues remained
enabled and idle. The machine uptime increased across both switches, confirming
that it was not rebooted.

The first switch exposed an empty `home-manager-root.service`: the Clan base
aspect had set its environment but had not defined the root profile. The root
profile is now ported with fish, lsd, sops, SSH-signed Git, Fastfetch, Zellij,
and terminfo; the resulting root activation service is valid and active. The
old root `.sops.yaml` convenience file and `NH_FLAKE` path remain deferred to
the user-secret and root-checkout follow-up. The first correction briefly
omitted Elitedesk's new NixCI auth aspect from the local flake only, so Clan
would not prompt for its still-undecided token; the aspect was restored after
Lattitude's update. Review later removed it again until `nch-sny.38` provides
the dedicated read-only token path. No Elitedesk configuration or credential
was changed.

### PVE-Strix standalone Home Manager candidate

The PVE-Strix root Home Manager profile is exposed as the standalone den home
`root@pve-strix`. It imports the existing Unified root and Proxmox profile
modules while the PVE system configuration remains under Unified. The
candidate uses the same Unified and fnox revisions as Unified's current lock
file. Its evaluated Home Manager package list, managed file targets, account
name, `/root` home directory, and state version (`25.11`) match
`homeConfigurations.pve-strix-root` in Unified. The candidate activation
package builds successfully.

The PVE-Strix aspect replaces Unified's empty `DRY_RUN` compatibility hook
with a no-op. Home Manager detects dry-run mode by checking whether the
variable exists, so exporting an empty value would have skipped managed-file
links and other activation actions. The Attic config is rendered from its
immutable template after Home Manager links files and materializes user
secrets, then written with mode `0600`; this preserves token substitution
without leaving placeholders active or using a stale token. A restrictive
umask keeps intermediate rendered files private too. The parity check keeps
these activation invariants in place.

The `pve-strix-home-parity` flake check preserves the package-name and managed
file-target inventories as SHA-256 snapshots in
`checks/pve-strix-home-reference.json`, along with the account invariants.
Regenerate the snapshot after reviewing an intentional profile change with:

```sh
nix eval --json '.#homeConfigurations."root@pve-strix"' --apply 'c: let h = c.config; packages = builtins.sort builtins.lessThan (map (p: p.pname or p.name) h.home.packages); files = builtins.sort builtins.lessThan (builtins.attrNames h.home.file); in { username = h.home.username; homeDirectory = h.home.homeDirectory; stateVersion = h.home.stateVersion; packageCount = builtins.length packages; packageNamesHash = builtins.hashString "sha256" (builtins.toJSON packages); fileTargetCount = builtins.length files; fileTargetsHash = builtins.hashString "sha256" (builtins.toJSON files); }' > checks/pve-strix-home-reference.json
```

The standalone root Home Manager profile was activated on PVE-Strix as
generation 34 on 2026-11-23. Its managed files and user-secret activation
completed, SSH remained reachable, and `/etc/nix/machines` now points to
Emerald at `10.10.11.55`. The Attic config is rendered with mode `0600`. The
No system configuration was activated and the host was not rebooted. This
verifies only root Home Manager; Proxmox VE, networking, storage, services,
and boot configuration stay in place.

### PVE-Rog standalone Home Manager candidate

The root Home Manager profile is exposed as `root@pve-rog` and reuses the
Proxmox root profile from the pinned Unified input. Its account, state version,
121 package names, and 58 managed file targets match Unified's
`homeConfigurations.pve-rog-root`; the targeted parity check preserves that
snapshot and the activation-order and private Attic-config invariants. Refresh
the baseline after reviewing an intentional Unified profile change with:

```sh
nix eval --json '.#homeConfigurations.pve-rog-root' --apply 'c: let h = c.config; packages = builtins.sort builtins.lessThan (map (p: p.pname or p.name) h.home.packages); files = builtins.sort builtins.lessThan (builtins.attrNames h.home.file); in { username = h.home.username; homeDirectory = h.home.homeDirectory; stateVersion = h.home.stateVersion; packageCount = builtins.length packages; packageNamesHash = builtins.hashString "sha256" (builtins.toJSON packages); fileTargetCount = builtins.length files; fileTargetsHash = builtins.hashString "sha256" (builtins.toJSON files); }' | jq . > checks/pve-rog-home-reference.json
```

Live inspection on 2026-11-24 found PVE-Rog Home Manager generation 26 and
`/etc/nix/machines` already targeting Emerald at `10.10.11.55`. Its active
Attic config is a symlink to a read-only store template that still contains an
unresolved token placeholder. The candidate renders the config after secret
activation and writes the result with mode `0600`. It was activated as
Home Manager generation 27 on 2026-11-24. SSH remained reachable, uptime
increased, the Attic config is now a regular mode-`0600` file with no active
placeholder, and `/etc/nix/machines` still targets Emerald. Home Manager
stopped and restarted the root user's `ssh-agent.service` during its user
systemd reload; the SSH daemon was not targeted. No Proxmox system
configuration was activated and the host was not rebooted. Proxmox VE,
networking, storage, and boot remain out of scope.

## Inventory

Edit `inventory/hosts.nix` for host addresses, SSH settings, and roles. The
typed `homelab.hosts` option lives in `modules/inventory.nix`. Set `migrated`
when a host is ready for den and Clan. Clan currently imports x86_64 NixOS
hosts and uses their roles as inventory tags. Clan and deploy-rs share the
SSH user and endpoint from inventory. For `clan-spike`, that endpoint is its
DHCP-registered name, `clan-spike.deepwatercreature.com`.

The `inventory-matches-unified` flake check imports the pinned unified data
files and compares active hosts and role memberships. Archived `ruby` and
`sapphire` records preserve unified's legacy builder client names.
`attic-cache` is emerald's legacy cache alias. Until a host migrates, unified
remains authoritative for operating it.

## Routers

- Routers hold no outbound SSH keys and get only the vars they use (see
  unified's `docs/adding-a-nixos-host.md#router-hosts`).
- Migrate elitedesk (standby) before router, with console access ready.
- Never deploy a router change without the user available.
- VRRP pair design, ownership and rollout: [`router-vrrp.md`](router-vrrp.md).

### Router role and elitedesk standby (nch-sny.26)

The den router aspect reads the mode, interface names and MACs, addresses,
WAN bandwidth and VRRP priority from inventory. Elitedesk is a manual spare.
The WAN is cabled to the ISP modem through a WAN-only unmanaged switch and a
second switch acting as a media converter. Its X520 port 0 uses 10G-SR fibre,
with a 2.5 Gbit RJ45 inter-switch link limiting the end-to-end rate. Leave WAN
administratively down until the user approves failover testing.

Clan configures the LAN default route through the live router and keeps SSH
reachable on the management interface with loose IPv4 reverse-path filtering.
The router aspect uses Clan vars for the Technitium password and SNMP
community. It supplies file paths through the router modules' `*File`
options, without agenix compatibility aliases. Primary mode also declares the
Kea TSIG, Cloudflare, and Tailscale credentials. The primary router migration
and VRRP operation are separate work. User passwords remain tracked in
nch-sny.11.

Evaluated both flakes' `nixosConfigurations.elitedesk.config` (unified at
`dc759e8dc76a3095d6a13c994271a68124b23dc5`). Firewall lists below are
deduplicated and sorted.

| Evaluated option | Unified | Clan |
| --- | --- | --- |
| Router networking, firewall, homelab, observability, Pangolin, SNMP, Technitium and SSH | Enabled | Enabled |
| Kea, DDNS, UPnP, mDNS reflection and Tailscale | Disabled | Disabled |
| WAN device, activation policy, DHCP | `enp1s0f0`, `down`, `yes` | `enp1s0f0`, `always-down`, `no` |
| LAN and management device/address | `enp1s0f1` / `10.10.10.4/16`, `eno1` / `192.168.100.98/24` | Same |
| LAN and management IPv6 RA | Disabled | Disabled |
| `router-firewall.trustedTcpPorts` | 80, 443, 3000, 3001, 3002, 5380, 8888, 9090, 16000, 19999, 26000, 53443 | Same |
| `router-firewall.trustedUdpPorts` | 69, 123, 161, 4011 | Same |
| `networking.firewall.checkReversePath` | `true` | `loose`, with matching kernel settings under the router nftables firewall |
| Technitium scopes, reservations, NTP servers, forced blocklist refresh | `{}`, `{}`, `[]`, `false` | Same |
| Technitium bootstrap password secret and API key secret name | `technitium-admin-password`, `null` | Same names, using a Clan var for the password |
| Router VPN | Enabled with placeholder WireGuard peers | Disabled |

The `router-standby` flake check evaluates WAN activation, DHCP and the
exclusive service settings for migrated standby hosts. Use
`nix develop -c fleet-deploy --dry-run elitedesk` to verify dispatcher routing
through deploy-rs.

## Emerald and the home environment

Emerald, the desktop that also serves the Attic cache and runs inference,
waits for the operator's home-manager environment to be ported (epic
`nch-sny.37`). Phoenix needs the same port. Handoff with decisions, the
mapped system port and the secrets plan:
[`emerald-migration.md`](./emerald-migration.md).

## Self-hosted CI

Separate from the migration: buildbot-nix on emerald, building flake checks
for GitHub PRs and pushing to Attic (garnix's open-sourced code was a poor fit). Handoff:
[`self-hosted-ci.md`](./self-hosted-ci.md), epic `nch-ktp`. Deploying it waits
for emerald's migration (`nch-sny.20`).

## Who does what

- `owner:any`: any agent (Claude, Codex, agy) may claim it.
- `owner:claude`: touches decrypted secrets or live hosts; Claude does it
  with the user's approval.
- `live`: changes a running machine.

## Spike findings

### nch-sny.1: skeleton (done)

- Layout: flake-parts with import-tree over `modules/` (dendritic). `modules/den.nix`
  declares hosts and users; `modules/clan.nix` turns every `x86_64-linux` den
  host into a clan machine; aspects live in `modules/aspects/` and `modules/hosts/`.
- Join point: den hosts set `intoAttr = [ ]`, and each `clan.machines.<name>`
  imports `config.den.hosts.<system>.<name>.mainModule`. Clan is the only
  producer of `nixosConfigurations`; den produces none.
- den sets `nixpkgs.hostPlatform` only when it instantiates the host, so the
  clan wrapper sets it (`lib.mkDefault host.system`). facter.json will set it
  for real machines.
- den warned that a user's nixos content reaches hosts only via a transition
  default ending 2027-01-01 (denful/den#694); we include
  `den.batteries.user-aspects` on hosts explicitly.
- Verified in `clan-spike`: hostname, base aspect, primary-user groups,
  authorized keys from the user aspect, Home Manager packages, disko root.
  Partly answers nch-sny.6: den users and Home Manager work under clan.
- unified's `den/` is a local den-inspired framework, not upstream den.
  Porting aspects (`nch-sny` foundation bead) means rewriting them as
  `den.aspects.*`, not importing unified's files.

### nch-sny.2: install with clan + nixos-facter (done)

`clan-spike` is VM 100 on pve-rog (2 cores, 4 GB, 32 GB on local-lvm,
vmbr0). Steps, all from emerald:

1. `nix build .#installer-iso` (NixOS minimal ISO + clan's installer module;
   root accepts the operator keys), copy to pve-rog `local:iso`.
2. `qm create` with `--boot 'order=scsi0;ide2' --start 1`: the blank disk
   falls through to the ISO now, and the installed system boots from disk
   after clan's reboot. Find the DHCP address with `ip neigh` on router (MAC
   from `qm config`).
3. Check the installer's host key before trusting the address: on the VM
   console run `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` and compare
   it with what `ssh-keyscan <ip> | ssh-keygen -lf -` prints from emerald.
   The key is ephemeral (new on every ISO boot), so it is checked once here
   rather than stored.
4. `clan machines install clan-spike --target-host root@<ip>
   --update-hardware-config nixos-facter --phases disko,install,reboot
   --host-key-check none --yes`.
   - kexec skipped: the installer already runs NixOS.
   - Keep the reboot phase. Skipping it and force-stopping the VM left the
     ESP's FAT filesystem corrupt (grub-install later failed on a read-only
     /boot); clan's reboot unmounts and syncs first.
   - A host already running another Linux uses the default phases
     (`kexec,disko,install,reboot`): kexec boots the installer in memory and
     the final reboot boots the installed system from its own disk, so no
     boot-order change is needed.

Observations:

- Clan collects facter.json first and builds with it, then commits three
  things itself: `machines/<m>/facter.json`, `inventory.json` (install time)
  and a non-secret `vars/per-machine/<m>/state-version`. The commits use the
  local git identity and no trailers; review them before pushing.
- No identity or rekey step was needed. That is the comparison point for
  nch-sny.3, when the first secret var arrives.
- `hardware.facter.reportPath` is set automatically when facter.json exists.
- Compared with unified (`just gen-identity`, `just rekey`, `just install`,
  hardware-configuration.nix by hand): one command plus VM plumbing. A host
  already running Linux needs only steps 3-4, with kexec.
- Open for nch-sny.4/.5: root has no authorized keys (the clan `sshd` service
  sets them), and the address is a dynamic lease; `clan machines update`
  needs a target host.

### nch-sny.3: clan vars beside agenix (done)

- Admins: `clan secrets users add <name> --age-key <age1...>` with the age
  key derived from the operator SSH public key (`ssh-to-age`). Two users,
  `deepwatrcreatur` (emerald/phoenix key) and `deepwatrcreatur-stable`, both
  in group `admins`.
- Clan encrypts only to the admin running the command unless told otherwise;
  `clan.core.sops.defaultGroups = [ "admins" ]` (modules/clan.nix) makes
  every var readable by both operators. Existing vars were re-encrypted with
  `clan vars fix`; the machine age key needed
  `clan secrets groups add-secret admins <machine>-age.key`.
- Clan's CLI reads admin keys only from `SOPS_AGE_KEY` / `SOPS_AGE_KEY_FILE`
  (not sops's SSH-key or `SOPS_AGE_KEY_CMD` paths). The dev shell's
  `clan-admin` wrapper derives `SOPS_AGE_KEY` from `~/.ssh/id_ed25519` per
  invocation, so no age key file exists anywhere.
- Recipients, verified per file: per-machine vars = admins + that machine;
  shared CA private key = admins only (machines cannot read it).
- Add a machine: declare the den host, `clan-admin vars generate <m>`
  (creates the machine's age key and all its vars), `clan-admin machines
  install`. No `secrets.nix` groups, no rekey of other machines' secrets.
- Remove: `clan machines delete <m>` drops its inventory entry, sops key and
  vars. Shared secrets stay encrypted to its key until a future
  `clan vars prune`; re-generate shared vars after removing a machine that
  had them.
- agenix coexistence works with the clan-managed host key as agenix's
  identity, but only after a fix: agenix decrypts before sops-nix's
  `setupSecrets`, so on first boot it found no identity and failed silently
  (no failed unit, only an activation-snippet error). Fix in
  `modules/hosts/clan-spike.nix`: host key `neededFor = "users"` (installed by
  `setupSecretsForUsers`) and `agenixInstall.deps = [ "setupSecretsForUsers" ]`.
  Verified after a cold boot: both secrets decrypt, agenix logs no warnings.
  This belongs in a shared aspect for every migrated host that still uses
  agenix.

### nch-sny.4: sshd service and host certificates (done)

- `inventory.instances.sshd` (modules/clan.nix): server role on all machines
  with root keys for both operators; client role on all machines (trusts the
  CA for `*.deepwatercreature.com`).
- `meta.domain = "deepwatercreature.com"`, the zone Technitium serves; Kea
  DDNS already registers DHCP clients, so `clan-spike.deepwatercreature.com`
  resolved with no extra work. The inventory records this name as the deploy endpoint.
- Verified: with only `@cert-authority *.deepwatercreature.com <CA>` in
  known_hosts and `StrictHostKeyChecking=yes`, SSH to the new machine
  succeeds with no stored host key and no prompt. Host keys are vars, so the
  reinstall kept the same key (fingerprint matched the repo).
- emerald trusts the CA through one line in `~/.ssh/known_hosts_dynamic`
  until it is a clan machine (client role).
- Certificates are issued "valid forever"; revocation would need
  `@revoked` lines. Non-clan hosts (Proxmox nodes) can be signed by hand:
  `clan-admin vars get` the CA key into memory, `ssh-keygen -s <ca> -h -I
  <host> -n <host>.deepwatercreature.com <host-key.pub>`, then
  `HostCertificate` in their sshd_config.
- Certificates cover names, not IPs: connect by DNS name (or HostKeyAlias).

### nch-sny.5: deploy and rollback (done)

Test change: a firewall that closes port 22 to new connections. The
deploy's own SSH session survives it (conntrack), the classic way to lock
yourself out of a router.

**`clan machines update`** (clan_lib/machines/update.py: sets the profile,
runs `switch-to-configuration boot`, then `switch` under `systemd-run`):

- Reported success (exit 0). New SSH connections timed out.
- A reboot did not help: the broken generation is already the boot default.
- Recovery needs the console (pick the previous generation in GRUB) or a
  reinstall. On the spike, reinstall took a few minutes and kept the host
  keys (vars).

**deploy-rs** (`modules/deploy-rs.nix`: a node per clan machine, same
closure, `nix run github:serokell/deploy-rs -- .#<m>`):

- Works on clan-built systems; clan vars need no extra step because sops
  secrets are in the store and the machine key is already on the host.
  Run `clan-admin vars generate` before deploying new vars.
- Magic rollback: activation, failed confirmation over a new SSH connection,
  switch back to the previous profile and re-activate it. Access returned
  without intervention (about 2.5 minutes including the confirm timeout).
- GOTCHA: rollback only re-activates a generation deploy-rs itself
  deployed. The first attempt rolled back onto clan's install generation,
  which has no `deploy-rs-activate`; re-activation failed and the broken
  system stayed the boot default. Make one known-good deploy-rs deploy right
  after install, while the console is still at hand.
- clan and deploy-rs can alternate on the same machine (clan deployed
  cleanly after deploy-rs).

**Decision for nch-sny.7:** routers (elitedesk, router) deploy with
deploy-rs; everything else with `clan machines update`. Firewall,
networking and sshd changes to any host should also go through deploy-rs.

### nch-sny.6: den users, Home Manager and darwin under clan (done)

- NixOS (verified on clan-spike): den users, `primary-user` groups, the
  user's own nixos content (via `den.batteries.user-aspects`) and Home
  Manager all work inside clan machines.
- Darwin (evaluation only, on a throwaway branch): a den host under
  `den.hosts.aarch64-darwin` with `intoAttr = [ ]`, mapped into clan with
  `inventory.machines.<m>.machineClass = "darwin"`, becomes
  `darwinConfigurations.<m>`; the full system derivation evaluates with the
  den user and Home Manager wired in. Needs: a nix-darwin input,
  `aarch64-darwin` in `systems`, `system.stateVersion` (an integer on
  darwin), and `darwin.users.users.<u>.home = "/Users/<u>"` in the user
  aspect (nix-darwin leaves it null, and Home Manager takes it from there).
  Clan supports `clan machines update` and vars on darwin; the first
  nix-darwin install stays manual (clan docs, guides/macos).
- Standalone homes (Proxmox root homes): den keeps producing
  `homeConfigurations` itself (homes keep their default `intoAttr`); clan
  does not manage them. Needs a den aspect per user with
  `den.batteries.define-user`; root's `home.homeDirectory` defaults to
  `/home/root` and must be overridden to `/root`.
- Recommendation: one repo for everything. NixOS and darwin machines go
  through clan; Proxmox node homes stay den-only and are deployed as today
  (`home-manager switch`, e.g. via the existing Ansible playbook).

### nch-sny.25: secret-free workstation aspects

The eval fixtures compose the Phoenix and Lattitude desktop selections through
den. Both publish under `legacyPackages.x86_64-linux` for `nix flake check`
and stay outside Clan inventory.

| Sample from unified | Port checked by |
| --- | --- |
| Phoenix PipeWire 32-bit ALSA and CUPS printing | `workstation-niri-eval` |
| Phoenix Niri HDMI-A-1 at 1.0 scale, solid Noctalia panel, COSMIC fallback and safe-mode without greetd | `workstation-niri-eval` |
| Phoenix root Snapper hourly retention of six and the HP PageWide default CUPS queue | `workstation-niri-eval` |
| Phoenix Orca enabled and T3 Code TCP 3773 with Tailscale Serve | `workstation-niri-eval` |
| Lattitude Sway greetd autologin and Mod4 keybindings | `workstation-sway-eval` |
| Both hosts default to mpv for MP4 | Both checks |

T3 Code's daemon retains its separate Home Manager opt-in, as in Phoenix's
developer home. Phoenix's Limine overrides, disk layout and other leaf-host
settings belong to the host migration. The workstation port leaves attic
authentication, remote-builder and SSH identities, password wiring, and the
share and VPN aspects to the vars work. Unified-specific activation scripts,
Nixbit's reference to the old repo, the WezTerm/Zellij launcher, and Phoenix's
inline systemd SSH proxy workaround are outside the port.

### Bare-metal install findings (nch-sny.21, elitedesk)

Found while preparing the first bare-metal install, testing on clan-spike
first (now UEFI/OVMF so the ESP convention is exercised):

- **kexec from a clan machine fails.** nixos-images' kexec `run` copies
  `/etc/ssh/ssh_host_*` into the new system and its initrd
  (`restore-state-from-initrd`) exits 1 when there are none; the installer
  lands in emergency mode with no network. Clan's sshd keeps host keys in
  vars, so a clan-managed host has none. Before reinstalling a clan machine
  in place, run `ssh-keygen -A` on it. Hosts still on unified have the keys
  and are unaffected. Verified: with the keys present the installer came up
  in about 20 s with the same host key and static address.
- **Hosts without internet need a local kexec tarball.** elitedesk (standby,
  WAN down, no default route) cannot download the image. Build it on the
  workstation and pass it:
  `nix build github:nix-community/nixos-images#kexec-installer-nixos-stable-noninteractive`,
  then `clan machines install ... --kexec <result>/nixos-kexec-installer-noninteractive-x86_64-linux.tar.gz`.
- **Proxmox applies boot-order changes only at a cold start**; `qm reset`
  keeps the old order. Use `qm stop` + `qm start`.
- **ESP convention verified on UEFI:** `/boot` on ext4 root, `/boot/efi` an
  idle automount, `switch-to-configuration boot` reinstalls GRUB. An
  accidental hard kill of the VM left root replaying its journal and the ESP
  untouched (no FAT dirty-bit warnings), which is the point of the layout.
- **SSH certificates vs addresses:** certificates name
  `<machine>.<domain>`; targets that are addresses (elitedesk's management
  IP has no DNS record) pass `HostKeyAlias=<machine>.<domain>` (set for all
  machines in `modules/clan.nix` and `modules/deploy-rs.nix`).
- **Data disks are never in disko.** elitedesk's disko file names only the
  OS SSD; sdb and sdc are `fileSystems` by UUID with `nofail`. Check with
  `grep -oE '/dev/disk/by-id/[^ ]+' $(nix build --print-out-paths
  .#nixosConfigurations.<m>.config.system.build.diskoScript)` before
  installing.
