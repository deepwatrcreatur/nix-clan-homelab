# fnox survey: where ad hoc secret handling remains

Survey for bead `nch-a67.4` (epic `nch-a67`), 2026-11-27. It inventories how
agents and operators get secrets today and ranks what should move to fnox. It
implements nothing beyond one local fix (item 1). Rules for agents are in
nix-agent-guides
[`guides/secrets.md`](https://github.com/deepwatrcreatur/nix-agent-guides/blob/main/guides/secrets.md).

Scope: unified-nix-configuration, nix-clan-homelab, nix-router-optimized,
nix-agent-guides, fnox-flake and nix-attic-infra (`git grep` on `main`),
the bare repos and worktrees under `~/flakes`, agent configs on emerald
(Claude Code, opencode), and fnox 1.19's commands. Secret values were never
printed; files were checked by name, length and shape.

## Boundary

| Secret is used by | Tool |
| --- | --- |
| a command run by an agent or the operator | fnox, scoped to that command |
| a system service | clan vars (nix-clan-homelab) or agenix (unified) |

User API keys come from agenix user secrets (unified,
`~/.local/share/agenix-user-secrets/*`) or systemd credentials (Clan
workstations, `modules/_nixos/workstation-user-secrets.nix`) and are seeded
into fnox. The seed source is authoritative, and the goal is that fnox is
the only interface agents use. Current exceptions: the Clan wrappers in item
8, and the keys in item 4 that fnox does not declare.

## Ranked findings

| # | Finding | Where | Proposal | Bead |
| --- | --- | --- | --- | --- |
| 1 | GitHub tokens embedded in two `origin` URLs (`https://oauth2:<token>@…`), in plaintext in `.git/config` | `~/flakes/agent-roundtable`, `~/flakes/tesla-inference-flake` | **Fixed 2026-11-27**: URLs reset to plain HTTPS; the global `url.insteadOf` now sends them over SSH, and `ls-remote` works. No other remote carries credentials. Rotation is not required by the token stance (not publicly exposed). | none |
| 2 | Activation scripts write the GitHub token into `~/.config/nix/nix.conf` (`access-tokens`) and Attic tokens into `/nix/var/determinate/netrc`, using plain `fnox get` (no `--if-missing error`, so a broken fnox yields the literal `age`), a hardcoded `~/.config/sops/age/keys.txt` gate that ignores `programs.fnox.ageKeyFile`/`sshIdentity`, and a fallback that `cat`s the token file | unified `modules/home-manager/common/nix-user-config.nix` | Use `fnox -c "$FNOX_CONFIG" --if-missing error get`, take the identity from `programs.fnox`, and refuse to write a value that fails a shape check. Longer term: keep the GitHub token out of `nix.conf` (per-command `NIX_CONFIG`, or an `!include` of a 0600 file written by the same step) | `nch-a67.7` |
| 3 | `git-credential-fnox` exists (fnox-flake #28) but no home enables it | unified HM, Clan homes | Enable `programs.fnox.gitCredentialHelper` on each machine once fnox decrypts there (after `nch-a67.2` rolls out); it replaces the `gh auth git-credential` fallback, so verify with the probe in the guide first | `nch-a67.3` (remaining acceptance) |
| 4 | Keys provisioned to Clan workstations but not declared in fnox-flake's defaults: `deepseek-api-key`, `openai-api-key`. `DEEPSEEK_API_KEY` exists on emerald only as a hand-added entry | Clan `workstation-user-secrets.nix`; fnox-flake `defaultSecretDefinitions` | Declared by the workstation fnox aspect for seeding and wrappers; roundtable seats then use `fnox exec` instead of reading key files | `nch-a67.8` |
| 5 | Docs show `TOKEN=$(sudo cat …)` for the Technitium API token and then pass it in argv | nix-router-optimized `docs/router-technitium-automation.md`, `docs/troubleshooting.md`; unified `docs/router-nixos-anywhere-lessons.md` | These are host-side service secrets (agenix, root-only), so fnox does not apply, but the snippets should send the token on stdin (`curl -H @-`) and never echo it | `nch-a67.9` |
| 6 | Drift between a seed source and fnox is invisible | all fnox hosts | fnox-flake PR #31 makes seed sources authoritative, refreshes changed values during activation, and adds `fnox-check`, which reports drift by secret name without exposing values or hashes | `nch-a67.2` |
| 7 | Committed secrets are caught only by GitGuardian on PRs | all repos | `fnox scan` in pre-commit and CI | `nch-a67.5` |
| 8 | On Clan workstations with `WORKSTATION_CREDENTIALS_DIRECTORY` set, `claude-fnox` and `gemini-fnox` skip fnox: they use an already-exported `ANTHROPIC_API_KEY`/`GEMINI_API_KEY`, else `cat` the systemd credential file | nix-clan-homelab `modules/_hm/workstation-developer/fnox.nix` (`withCredential`) | Seed those credentials into fnox (as unified seeds agenix user secrets) and drop the direct read, or record the systemd credential as the accepted interface for those two tools. Part of porting the fnox integration to Clan homes | `nch-a67.6` |

On Clan workstations `FNOX_CONFIG` points at `fnox/clan-defaults.toml` to keep
that store separate from an existing writable global config. Fnox does not
automatically honor that environment variable for ordinary CLI invocations;
select the store explicitly, for example:

```sh
fnox -c "$FNOX_CONFIG" exec -- <command>
```

The `gh-fnox` and `bw-fnox` launchers also pass that config explicitly.

## Checked and fine

- **Agent and MCP configs on emerald:** no MCP server in `~/.claude.json` or
  `~/.claude/settings.json` takes a key through `env` or `headers`;
  `~/.config/opencode/opencode.jsonc` contains no inline keys.
- **Other remotes:** the `ssh://git@github.com/...` remotes carry only the
  `git` user.
- **`~/.config/nix/nix.conf`:** holds a token-shaped 40-character GitHub
  token, not the `age` placeholder (on emerald the activation skipped fnox,
  because `keys.txt` is absent, and used the token file).
- **System services:** router, Attic and Technitium secrets come from clan
  vars or agenix files, read by the services themselves.

## fnox features not used yet

| Feature | Verdict |
| --- | --- |
| `fnox exec` profiles (`-P`) | Useful once there are task-specific secret sets (for example a `deploy` profile with only the Proxmox token). Not needed while wrappers cover each tool. |
| `fnox mcp` (secret-gated agent access) | Most promising: agents ask for a secret and fnox mediates, instead of an agent shell holding it. Worth a spike after `nch-a67.2`. |
| `fnox lease` (ephemeral credentials) | Needs a provider that mints short-lived credentials (cloud IAM, Vault). None in this homelab; skip. |
| `fnox sync` (pull from a remote provider) | Only if Bitwarden becomes the source of truth instead of agenix user secrets; `BW_SESSION` is already declared. Not proposed. |
| `fnox scan` | Tracked in `nch-a67.5`. |
| `fnox activate` | **Reject for agent shells**: it puts every secret into the shell environment, the ambient pattern the guide forbids. |
| `fnox check` / `fnox doctor` | Part of the activation health check (item 6), next to the hash comparison: they show that values resolve, not that they match the seed. |
