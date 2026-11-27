# Phoenix migration candidate

The source comparison is Unified commit
`2eccceae94485ecfd2d72cc5fb1c1adabe613e72`, matching the `unified-pve` pin.
The comparison fixture is exposed as
`legacyPackages.x86_64-linux.phoenix-candidate`. Phoenix is also registered
as a Clan inventory candidate so its machine composition can be evaluated,
but `migrated` remains false and the fleet deployment dispatcher rejects it.
Unified remains authoritative, and the comparison fixture is not a deployment
target.

`modules/hosts/phoenix.nix` is shared by the Clan machine and the
`legacyPackages.x86_64-linux.phoenix-candidate` fixture, which adds inert
secret paths for evaluation. The shared aspect composes the ported workstation
base, Niri/Noctalia/COSMIC fallback, networking, media, printer, snapshot,
safe-mode, builder, cache, share, developer, desktop and user-secret aspects.
The Phoenix disk, hardware and networking modules are copied into `machines/`.
WhiteSur desktop settings are ported into `modules/_hm/workstation-desktop/`
and its upstream inputs are pinned to the Unified revisions. The OpenLogi
NixOS module now points directly to the `packaging` subflake at the previously
locked revision, avoiding its deprecated root-flake alias.

The check asserts the Phoenix hostname, Limine device and partition, scratch
and data filesystems, Synology share mounts, NetworkManager firewall ports,
Tailscale, printing, Niri, phone mirroring, remote builder, cache netrc path,
Strata, and key Home Manager applications. The targeted check also evaluates
the complete system toplevel derivation.

## Secret handling and deployment blockers

The fixture supplies inert `/run/secrets/phoenix-candidate/...` paths for
Clan-backed settings so the configuration can be evaluated without Clan
machine state. These are paths only; no secret contents are read, generated,
or decrypted. They make the candidate unsuitable for deployment. A live
Phoenix configuration must use actual Clan var paths and pass `clan-admin vars
check phoenix` before deployment.

Phoenix now has a Clan machine age identity and state-version var. Generating
the machine identity added Phoenix as a recipient to the existing shared
vars declared by its aspects: console password hashes, cache credentials,
builder key, Synology credentials, and all 13 workstation credentials. Clan
re-encrypted those files for the new recipient; no plaintext files were
written.

Phoenix's existing Ed25519 SSH host private key was streamed from the live
host into `clan-admin vars set`, then the public key and host certificate were
stored as Clan vars. The Clan key fingerprint matches the key on Phoenix and
the key currently presented by SSH. `clan-admin vars check phoenix` reports
all vars present and valid, and the real Phoenix toplevel evaluates. No vars
were uploaded to Phoenix, and it has not been deployed or activated.

Unified also installs a stable root SSH client key at
`/root/.ssh/id_ed25519`. Phoenix's live key fingerprint matches Unified's
`root-stable-identity.pub`. The `root-ssh-identity` aspect now declares a
shared Clan var and exposes it at the same path with root-only permissions.
Its existing private key was streamed into the encrypted Clan var; no
plaintext file was written. The GPG recovery key is not part of this
migration.

The source WhiteSur configuration names a wallpaper under the old Unified
checkout, but that image is absent from the Unified worktree and this repo.
Supply or choose a wallpaper before using that setting after migration.

## Known comparison differences

The system comparison uses matching Unified/NCH attributes for the Phoenix
state version, Limine settings, kernel modules and parameters, hostname,
NetworkManager, firewall ports, filesystems, Tailscale, Flatpak, printing and
both phone-mirroring services. CIFS mount options match except for the
credential path, which is a runtime Clan var in the live candidate and an
inert fixture path during this check.

The logical system package inventory has 327 names in both Unified and the
candidate after restoring `graphite-cli`, `iodyne`, `lazyrsync`,
`lightpanda`, `nixbit` and `wezterm`. NixOS's `command-not-found` helper is
the one candidate-only package and remains enabled.

The Home Manager snapshot has 102 file targets, 184 package names and 57
enabled programs in Unified. The candidate has 104 file targets, 184 package
names and 55 enabled programs. It currently records these differences:

| Area | Missing from candidate | Extra in candidate |
|---|---|---|
| Files | — | `.config/fnox/clan-defaults.toml`, `.config/git/github-token` |
| Packages | `beads-q`, `install-brew-packages` | `git-ssh-doctor`, `vivaldi` |
| Enabled programs | `linuxbrew`, `ssh-known-hosts-manager` | — |

Regenerate the Unified reference only after reviewing an intentional profile
change. The command writes the sorted Unified inventory to
`checks/phoenix-home-reference.json`:

```sh
nix eval --impure --json --expr '
  let
    unified = builtins.getFlake "git+file:///home/deepwatrcreatur/flakes-worktrees/unified-nix-configuration/main?rev=2eccceae94485ecfd2d72cc5fb1c1adabe613e72";
    inventory = import ./checks/emerald-home-inventory.nix;
  in inventory unified.nixosConfigurations.phoenix.config.home-manager.users.deepwatrcreatur
' | jq -S . > checks/phoenix-home-reference.json
```

Capture the sorted candidate inventory with:

```sh
nix eval --json .#legacyPackages.x86_64-linux.phoenixHomeInventory \
  | jq -S . > /tmp/phoenix-home-candidate.json
```

Compare each `files`, `packages`, and `enabledPrograms` list with the reference,
review every changed name, then update
`checks/phoenix-home-expected-differences.json` with the intended deltas.

This work does not mark Phoenix migrated, change Unified's authoritative host
config, activate a generation, change boot defaults, reboot, restart services,
or deliver Clan vars to Phoenix. Resolve or accept the listed desktop and
package differences before migrating Phoenix.

Build-only validation:

```sh
nix build --no-link --max-jobs 2 --cores 2 .#checks.x86_64-linux.phoenix-home-parity .#checks.x86_64-linux.phoenix-candidate .#checks.x86_64-linux.phoenix-clan-candidate
nix build --no-link --max-jobs 2 --cores 2 .#legacyPackages.x86_64-linux.phoenix-candidate.config.system.build.toplevel
```

The focused Phoenix checks also pass alongside
`checks.x86_64-linux.emerald-home-parity`. After generating Phoenix's machine
vars, `nix flake check --no-build` passes, including evaluation of the real
Phoenix toplevel. It reports the repo's existing `boot.zfs.forceImportRoot`
and unknown-output warnings. The fixture toplevel build does not exercise or
satisfy Clan machine var requirements.
