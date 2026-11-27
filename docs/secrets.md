# Secrets (clan vars)

Secrets are clan vars (sops backend). Each one is encrypted to the `admins`
group and to the machines whose config declares its generator, and to no one
else. Routers stay least-privilege by not including the aspects that declare
the vars they don't need.

Secrets used by commands that agents or the operator run (API keys, the
GitHub token) go through fnox instead; see
[fnox-survey.md](fnox-survey.md) for what still bypasses it.

## Moving a secret over from unified

The value comes from unified's agenix file, piped straight into the var, so it
never touches the disk unencrypted:

```sh
age -d -i ~/.ssh/id_ed25519 ../unified/secrets-agenix/<name>.age \
  | nix develop -c clan-admin vars set <any machine declaring it> <generator>/<file>
```

For a shared generator (`share = true`), set it once through any machine.
Every other machine that declares the generator gets it at its next
`clan vars fix`/deploy. `clan vars set` commits on its own, so review the
commit before pushing.

## Domains (bead nch-sny.11)

| Domain | Aspects | Vars | Status |
| --- | --- | --- | --- |
| cache/builder | `nix-cache-auth`, `nix-ci-cache-auth`, `remote-builder-client` | `nix-cache-auth/{attic-token,netrc}`, `nix-ci-cache-auth/netrc`, `nix-remote-builder/key` | Existing values are imported; Phoenix is a recipient for declared vars. Router-class hosts do not use NixCI; builder keys remain off routers. |
| Synology CIFS | `synology-shares` | `synology-shares/credentials` | Imported from unified; Lattitude and Phoenix are recipients. Emerald remains admin-only. |
| user/operator | `console-password` (per clan host), `workstation-user-secrets`, `root-ssh-identity` | `console-password/{root,deepwatrcreatur}` (yescrypt hashes); 13 workstation credentials under `vars/shared/workstation-user-secrets`; stable root client key under `vars/shared/root-ssh-identity` | Values are encrypted Clan vars; Lattitude and Phoenix are recipients for their declared vars. No live host has read the workstation credentials. Root SSH identity is preserved for Phoenix, with no Clan vars delivered yet. Workstation credential delivery and state preservation remain in `nch-sny.37.7`. |
| homeserver services | | | todo |
| router services | `router-role`, `router-secrets`, `console-password` | router service vars plus per-machine health-check URLs | Clan vars and source aspects are in place for the VRRP pair. No Clan vars have been deployed to the live routers; retain Unified's agenix files until each router host migration is complete. |

An agenix file is deleted from unified only once every host that used it
reads the secret from vars.

### Workstation user credentials

The operator's home uses Clan vars. The opt-in
`workstation-user-secrets` aspect declares a shared generator with files
owned by `deepwatrcreatur` and mode `0400`. It also exposes the GitHub token
at the path expected by `gh-fnox`. Enable the aspect only on a workstation
selected for the migration or its coordinated verification.

Imported values are stored under `vars/shared/workstation-user-secrets`.
Lattitude and Phoenix declare this aspect, and both machine keys are
recipients for these encrypted vars. No live machine has read them. Emerald
remains admin-only. Live verification on each host still needs the
maintainer's coordination and covers credential delivery and preservation of
existing application state.

The GPG private key remains in the operator's cloud backup for optional
recovery. Technitium router automation creates its own API token from the
separate bootstrap password. Bitwarden establishes a fresh unlock session.
These three legacy files are outside the required import.

On activation, the workstation aspect seeds missing Atuin, Bitwarden,
Gemini OAuth and rclone state as owner-only files. Existing application
state takes precedence, including changes made after the first activation.
The Claude and Gemini wrappers read Clan files for their API keys when the
aspect is enabled. The remaining API keys are available as user-owned
files under `WORKSTATION_CREDENTIALS_DIRECTORY`. The generated fnox
defaults use a separate file so an existing writable config stays in place.

### cache/builder notes

- `netrc` contains only the cache.nix-ci.com entry (HTTPS).
- The `nix-cache-auth` aspect enables NixCI and Attic client credentials for
  hosts that explicitly include it. Router-class hosts must not include
  `nix-cache-auth` or `nix-ci-cache-auth`: the operator chose no NixCI
  credential for routers. They retain the local Attic and public substituters;
  the `nix-ci-cache-auth` check enforces this policy on router-role NixOS
  configurations.
- The `nix-cache-auth` flake check verifies the NixCI endpoint, key and netrc
  on the exported NixOS configurations and checks the public-cache fallback.
- attic's `cache-local` answers unauthenticated reads on the LAN, so pulls
  need no credential. The token only gates pushes (the post-build push hook
  has not been ported yet). Never put it in netrc: the attic substituters are
  plain HTTP, and Nix would send it in clear.
- emerald has no clan host certificate yet, so builder trust pins its host
  key (`keys/emerald-host-ed25519.pub`).
