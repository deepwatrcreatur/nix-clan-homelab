# Emerald migration and the home-environment port (handoff)

Status: **planned** (2026-11-20). Audience: the implementing agent (Codex)
and the maintainer. Read `AGENTS.md` and `docs/plan.md` first.

Beads:
- epic `nch-sny.37`: port the operator's home environment from unified;
- children of `nch-sny.20`: the emerald system port and switch.

`beads-rust show <id>` has the acceptance criteria for each.

## Why two parts

Emerald is the maintainer's daily desktop as well as the fleet's binary
cache and inference box. Its home-manager environment comes from unified,
and none of it exists here yet:
- **unified:** about 125 Nix files under `users/deepwatrcreatur/` and
  `modules/home-manager/`, plus user-level sops secrets;
- **here:** `user-server` gives bash, fish and htop.

Unified has no standalone `homeConfigurations` entry for the operator on
emerald, so the system can't move to clan while the home stays on unified.
The home environment has to be ported first (part 1). Phoenix needs the
same port before its migration.

The repo rule from `nch-sny.9` applies: **port modules into this repo; don't
import unified's source.** `inputs.unified` is `flake = false` and exists
only for the inventory comparison.

## Decisions already made (maintainer, 2026-11-20)

| Topic | Decision |
|---|---|
| Desktop | Keep KDE Plasma 6 + SDDM autologin, as today |
| SSH | Keys only: `PasswordAuthentication = false`, root by key only (fleet baseline). Unified's attic-cache module enabled password and root login; drop that. Graphical autologin and key logins are unaffected. |
| Legacy cache | Drop nix-serve (5000) and the nginx caching proxies (8080/8081). Nothing references them, and the nginx access log has been empty since 2026-09-16. Keep atticd (5001) and Attic Observatory (8082). |
| Switch | `boot` + reboot when the maintainer chooses; the previous generation stays in the boot menu. Not a live switch of the running desktop. |

## Reference build

Unified main builds emerald to the same closure as the running system
(`diff-closures` empty on 2026-11-20). Use it as the comparison target:

```bash
nix build github:deepwatrcreatur/unified-nix-configuration#nixosConfigurations.emerald.config.system.build.toplevel
```

nixpkgs differs (unified 2026-08-12, here 2026-11-16), so compare by name,
not by store path:
- systemd units (`ls $sys/etc/systemd/system`);
- `/etc` files;
- `environment.systemPackages` names;
- `home.packages` and `home.file` names;
- `fileSystems`, `boot.kernelParams` and `boot.kernelModules`;
- firewall ports.

Each difference must be either intended (one of the decisions above) or
fixed.

## Part 1: home-environment port (epic `nch-sny.37`)

Port into den aspects with `homeManager` classes, grouped as in unified:

| Group | Unified sources | Notes |
|---|---|---|
| Method and check | — | A flake check comparing the ported HM config for `deepwatrcreatur` on a fixture host against unified's emerald HM config: package names, `home.file` targets, `programs.*.enable`. Write this first; every later PR must keep it passing for its area. |
| Flake inputs | unified `flake.nix` | Only what the Linux home uses. Candidates: zellij-vivid-rounded, llm-agents, herdr, worktrunk, jj-starship, beads-rust, dmux-flake, fnox, nix-iodyne, nix-frankenterm, nix-cmux-tui, nix-index-database, hunk, plasma-manager, nix-whitesur-config. Check each against actual use. |
| Shell and CLI | `modules/home-manager/common/{fish,starship,atuin,bat,eza,fd-enhanced,fzf,ripgrep-enhanced,tmux-enhanced,helix,nushell,jj,just,grc,*-aliases,motd,platform,packages,env}.nix`, `modules/home-manager/{git,git-ssh-signing,ssh-agent}.nix`, `common/ssh-*.nix` | Largest group; split into two PRs if needed. |
| Developer and agents | `users/deepwatrcreatur/aspects/developer.nix`, `common/{coding-agents,agent-guards,beads,herdr,dmux,worktrunk,cass-session-search,orca-ide,npm,cargo-binstall,comma,repo-updater,nix-user-config,fnox,iodyne,frankenterm,cmux-tui}.nix` | `t3code-daemon` is already in `modules/_hm`. |
| Desktop user apps | `ghostty/`, `zen.nix`, browsers (Firefox, Chrome, Vivaldi), `bitwarden-cli.nix`, `rbw.nix`, `fastfetch.nix`, `linuxbrew.nix`, `rclone-scripts.nix`, `kde-plasma.nix` (plasma-manager) | `kde-plasma.nix` is imported by unified's `plasma-session-base`. |
| User secrets | `users/deepwatrcreatur/{sops.nix,secrets/}`, `modules/home-manager/user-secrets.nix` | github-token, atuin key, GPG private key, API keys (grok, openrouter, z-ai, opencode-zen, technitium), rclone.conf, bitwarden data. Decide the backend: clan vars owned by the user (preferred, one secrets system), or HM sops-nix keyed to the admins group. `owner:claude`: it handles decrypted values with the maintainer. |
| Verification | — | Deploy the ported user environment to `clan-spike` and log in. Shells, git signing, agents and secrets must work. |

Leave out darwin-only modules (`common-darwin.nix`, `attic-client-darwin`,
`xbar`, `env-darwin`), unused desktops (gnome, cinnamon, mate, xfce, lxde,
hyprland, rofi) and other hosts' files.

### Regenerate the Home Manager reference snapshot

From the homelab worktree, evaluate unified at the pinned reference revision.
This uses unified's own lockfile and extracts package names, enabled file
targets, and enabled programs for the operator on Emerald.

```bash
set -o pipefail
snapshot=$(mktemp)
nix eval --impure --json --expr '
  let
    unified = builtins.getFlake "git+file://${builtins.getEnv "HOME"}/flakes/unified-nix-configuration?rev=95d9b0ac1eaa2d0897ba399b3cafa0ae62bece4e";
    inventory = import ./checks/emerald-home-inventory.nix;
  in inventory unified.nixosConfigurations.emerald.config.home-manager.users.deepwatrcreatur
' | jq -S . > "$snapshot" &&
  cp "$snapshot" checks/emerald-home-reference.json
rm "$snapshot"
```

Update the pinned revision here if the baseline changes. To inspect the Clan
fixture's inventory, run
`nix eval --json .#legacyPackages.x86_64-linux.emeraldHomeInventory | jq -S .`.
As each group is ported, review the observed differences printed by the
parity check and update `checks/emerald-home-expected-differences.json`.
Run `nix build --no-link .#checks.x86_64-linux.emerald-home-parity` and
`nix flake check --no-build` to validate the result.

### Linux Home Manager input pins

The input port reuses unified's locked revisions for the Emerald baseline.
The shell and CLI port uses `jj-starship` and `zellij-vivid-rounded`.
Developer tooling uses `dmux-flake`, `fnox`, `herdr`, `hunk`,
`llm-agents`, `llm-agents-herdr-app`, `nix-cmux-tui`,
`nix-deepseek-harness`, `nix-frankenterm`, `nix-index-database`,
`nix-markit`, `nix-rtk`, `qmd` and `leaf`. Desktop integration uses
`plasma-manager` and the existing `nix-linuxbrew` and `zen-browser` pins.

Worktrunk and beads-rust come from unified's release-binary package
definitions. WhiteSur is wired into Phoenix, and Iodyne is absent from
Emerald's evaluated home inventory. Each of those choices follows the
audited Emerald configuration at the reference revision.

The `emerald-home-eval` fixture delivers the `user-workstation-shell`
aspect to the operator through den. The inventory covers Starship, Jujutsu,
bat, eza, fzf, rename, zoxide, Atuin, the enhanced fd and ripgrep
configurations, grc, tmux, the SSH login banner, Fish plugins, Nushell, Zsh,
terminal definitions for Ghostty and Kitty, Helix, shared CLI packages, Git
aliases and settings, and the SSH signing agent. The banner points at a
Clan build, and the shared shell environment sets `NH_FLAKE` to the Clan
main worktree. Git uses `gh` until the `gh-fnox` wrapper is ported under
`nch-sny.37.4`. Atuin key migration is tracked in `nch-sny.37.6`. The
rest of the shell and CLI port is tracked in `nch-sny.37.3`.

## Part 2: emerald system port (children of `nch-sny.20`)

Mapped from unified main on 2026-11-20.

### Host module `modules/hosts/emerald.nix`

- **Includes:** `nixos-base`, `console-password`, `nix-cache-auth`,
  `home-manager-users`, the ported user aspects, `desktop-media-players`,
  `t3code`, `orca-ide`, plus the new aspects below.
- **Hardware, verbatim:** copy `hosts/nixos/emerald/{disko,hardware-configuration,networking}.nix`
  to `machines/emerald/`.
  - Mounts must not change: btrfs subvolumes `@ @home @nix @snapshots`,
    `/big` by label, ZFS support with `networking.hostId = "49d7f964"`.
  - Don't add `machines/emerald/facter.json` in this step: clan would set
    `hardware.facter.reportPath` and change kernel modules. A facter switch
    can come later.
- **Host extras** from unified `den/hosts/emerald/default.nix`:
  - screen and iPhone mirroring (`nix-omarchy-*` inputs);
  - `programs.linuxbrew`, `programs.strata`, `nix-ld`;
  - the user's `linger`;
  - packages omasnap, flameshot, browsers;
  - `time.timeZone` and `i18n.defaultLocale = "en_CA.UTF-8"`.
- **`system.stateVersion`:** keep unified's value for emerald. Check the
  reference build; `attic-cache/configuration.nix` sets 25.05.

### New system aspects

| Aspect | From unified | Changes |
|---|---|---|
| `attic-server` | `hosts/nixos-lxc/attic-cache/modules/{build-server,configuration,users}.nix`, `den/aspects/attic-cache-*.nix` | Keep atticd (5001, settings, storage under `/var/lib/atticd`), `atticd-env`, `attic-init`, the `nixbuilder` user and `trusted-users`, `nix.gc` daily 3d, journald limits. Drop nix-serve, `nix-serve-keys`, nginx `cache-server`/`attic-cache` vhosts and their ports. SSH keys only. Drop the legacy `root@router` authorized key (routers hold no outbound keys). Keep the `nix-remote-builder` key so `remote-builder-client` hosts can build here. |
| `attic-observatory` | `modules/nixos/attic-observatory.nix` | `inputs.nix-attic-infra.nixosModules.attic-observatory`, theme x-dark, nginx on 8082. |
| `iperf3` | `modules/nixos/services/iperf3.nix` | Port the module; `bindProbeAddress` = emerald's IP from inventory. |
| `desktop-plasma` | `den/aspects/desktop-plasma.nix`, `modules/nixos/sessions/plasma-session-base.nix`, `plasma-kwallet-support.nix` | plasma-manager input; vicinae for the user. |
| `desktop-network-shares` | same name | gvfs, avahi, wsdd with pinned source port 37020 and firewall 3702/37020. |
| `synology-shares` | same name | CIFS automounts `/cloud`, `/storage` from 10.10.11.88; credentials from a clan var. |
| `rclone-client` | same name | rclone.conf from a clan var, linked for root. |
| `hardware-amdgpu-power-saving` | same name | Kernel params `amdgpu.ppfeaturemask=0xfff73fff amdgpu.runpm=0`. |
| `inference-ollama` | `den/aspects/inference-ollama.nix` | tesla-inference-flake module and overlays (`ollama-official-binaries`, `llama-cpp-tesla`, `gpu-tools`), the NVIDIA `legacy_580` driver for the Tesla P40, port 11434. |
| `inference-strata` | `den/aspects/inference-strata.nix` | `inputs.nix-strata.nixosModules.default`, overlay package `strata-inference-p40`, port 8000. |

### Secrets: agenix → clan vars

**GOTCHA:** unified's agenix installs emerald's secrets at
`/run/secrets/<name>`, which is sops-nix's directory under clan. They can't
coexist, so every one moves to a clan var in the same switch.

Import values with the documented pipe, never via disk:

```bash
age -d -i ~/.ssh/id_ed25519 secrets-agenix/<name>.age | nix develop -c clan-admin vars set emerald <generator>/<file>
```

| Unified agenix | Clan var |
|---|---|
| `attic-client-token` | `nix-cache-auth/attic-token` (existing shared generator; check it holds the same value) |
| `nix-ci-netrc` | `nix-cache-auth/netrc` (existing) |
| `attic-server-token` | new `attic-server/server-token` |
| `attic-jwt-secret` | new `attic-server/jwt-secret` (RS256 key, base64) |
| `github-token` | user-secrets group (part 1) |
| `rclone-conf` | new `rclone-client/conf` |
| `synology-smb-credentials` | new `synology-shares/credentials` (check the file exists in unified first) |

**SSH host key:** clan's `sshd` service keeps host keys in vars. Import
emerald's existing key, so other hosts' known_hosts and agenix recipients
don't break:

```bash
sudo cat /etc/ssh/ssh_host_ed25519_key | nix develop -c clan-admin vars set emerald openssh/ssh.id_ed25519
```

Check the generator and file names against `vars/per-machine/elitedesk/`.
`owner:claude`: this needs the maintainer and decrypted values.

### Switch and cleanup

1. Build, compare with the reference (above), fix or justify every
   difference.
2. With the maintainer: install the generation as the boot default
   (`clan machines update` with a boot action, or `nixos-rebuild boot` from
   the built closure). The maintainer reboots when convenient. The previous
   generation stays in the boot menu.
3. Verify after the reboot:
   - Plasma autologin and the user environment;
   - `attic` pushes and pulls from another host;
   - remote builds from a `remote-builder-client` host;
   - ollama and strata respond;
   - `/cloud` and `/storage` mount;
   - `systemctl --failed` is empty.
4. Remove emerald from unified in one coordinated change: den host, host
   files, agenix recipients plus a rekey, and the `inventory-matches-unified`
   pin here. Same pattern as `nch-sny.21`.

## Risks seen during mapping

- **nixpkgs jump** (August to November): Plasma, NVIDIA `legacy_580` and
  CUDA packages may change. Build the inference stack early.
- **Fleet substituters** point at emerald's Attic. A broken atticd slows
  every build, but hosts fall back to cache.nixos.org.
- **ConnectX-4 Lx:** emerald's card (firmware 14.32.1912) idles at about
  71 °C without direct airflow. It's unused today; add cooling before using
  it.
