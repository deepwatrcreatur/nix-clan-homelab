# Phoenix migration candidate

The source comparison is Unified commit
`2eccceae94485ecfd2d72cc5fb1c1adabe613e72`, matching the `unified-pve` pin.
The comparison fixture is exposed as
`legacyPackages.x86_64-linux.phoenix-candidate`. Phoenix is also registered
as a Clan inventory candidate so its machine composition can be evaluated,
but `migrated` remains false and the fleet deployment dispatcher rejects it.
Unified remains authoritative, and the comparison fixture is not a deployment
target.

`modules/phoenix-candidate-check.nix` composes the ported workstation base,
Niri/Noctalia/COSMIC fallback, networking, media, printer, snapshot, safe-mode,
builder, cache, share, developer, desktop and user-secret aspects. The Phoenix
disk, hardware and networking modules are copied into `machines/`. WhiteSur
desktop settings are ported into `modules/_hm/workstation-desktop/` and its
upstream inputs are pinned to the Unified revisions.

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

The Clan machine configuration currently cannot evaluate its final toplevel:
Clan reports that the `openssh` generator's `ssh.id_ed25519.pub` file is
missing and recommends `clan vars generate`. That generated host-key var and
all other vars are outside the offline wiring bead. The `phoenix-clan-candidate`
check therefore validates inventory and machine options without forcing the
secret-dependent toplevel. Do not treat it as ready to deploy.

The required console password, cache netrc and Attic token, Emerald builder
SSH key, Synology credentials, and 13 workstation credentials are Clan vars
with shared generators. The workstation credential values are already
imported under `vars/shared/workstation-user-secrets`; `vars check lattitude`
reports them present and valid. Phoenix is in the Clan inventory but its vars
have not been generated or recipient-checked. The missing `openssh` public-key
file currently blocks toplevel evaluation. No vars were generated or
decrypted; the maintainer must coordinate host-key generation, recipient
checks and first live delivery. The GPG recovery key is not part of this
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

The logical system package inventory has 327 names in Unified and 321 in the
candidate. The candidate is missing `graphite-cli`, `iodyne`, `lazyrsync`,
`lightpanda`, `nixbit` and `wezterm`; `command-not-found` is extra. These are
reviewed differences to resolve or explicitly retain before Phoenix is marked
migrated.

The Home Manager snapshot has 102 file targets, 184 package names and 57
enabled programs in Unified. The candidate has 103 file targets, 184 package
names and 55 enabled programs. It currently records these reviewed differences:

| Area | Missing from candidate | Extra in candidate |
|---|---|---|
| Files | `.config/wezterm/wezterm.lua` | `.config/fnox/clan-defaults.toml`, `.config/git/github-token` |
| Packages | `install-brew-packages` | `git-ssh-doctor`, `vivaldi` |
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
or decrypt secrets. Resolve or accept the listed desktop and package
differences and coordinate the missing Clan vars before migrating Phoenix.

Build-only validation:

```sh
nix build --no-link --max-jobs 2 --cores 2 .#checks.x86_64-linux.phoenix-home-parity .#checks.x86_64-linux.phoenix-candidate .#checks.x86_64-linux.phoenix-clan-candidate
nix build --no-link --max-jobs 2 --cores 2 .#legacyPackages.x86_64-linux.phoenix-candidate.config.system.build.toplevel
```

`nix develop -c clan-admin vars check lattitude` reports all Lattitude vars
present and valid. A later sequential `nix flake check --no-build` also
evaluated `checks.x86_64-linux.lattitude-host` successfully and proceeded to
`checks.x86_64-linux.pve-strix-home-parity`, where it fails while evaluating
fnox's generated config because the `fnox-config-template.toml.drv` store path
is invalid. That broader check failure is unrelated to Lattitude's secrets;
the Phoenix checks are run directly so it does not hide their result.
