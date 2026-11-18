# Migration plan

Goal: run the homelab from this repo on [clan-core](https://docs.clan.lol),
keeping [den](https://github.com/denful/den) aspects for host composition, and
retire `unified-nix-configuration` (below: "unified").

The work queue is in `.beads/` (`beads-rust ready`). This file explains the
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

## Routers

- Routers hold no outbound SSH keys and get only the vars they use (see
  unified's `docs/adding-a-nixos-host.md#router-hosts`).
- Migrate elitedesk (standby) before router, with console access ready.
- Never deploy a router change without the user available.

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
  resolved with no extra work. Deploy targets are derived from it.
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
