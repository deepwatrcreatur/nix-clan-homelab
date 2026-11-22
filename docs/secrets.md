# Secrets (clan vars)

Secrets are clan vars (sops backend). Each one is encrypted to the `admins`
group and to the machines whose config declares its generator, and to no one
else. Routers stay least-privilege by not including the aspects that declare
the vars they don't need.

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
| cache/builder | `nix-cache-auth`, `remote-builder-client` | `nix-cache-auth/{attic-token,netrc}`, `nix-remote-builder/key` | imported; verified on clan-spike; Lattitude recipient added for candidate |
| Synology CIFS | `synology-shares` | `synology-shares/credentials` | imported from unified; Lattitude recipient added for candidate; Emerald remains admin-only |
| user/operator | `console-password` (per clan host) | `console-password/{root,deepwatrcreatur}` (yescrypt hashes); github-token, API keys still todo | Lattitude recipient added for candidate; other hosts still need vars generation |
| homeserver services | | | todo |
| router services | | | todo |

An agenix file is deleted from unified only once every host that used it
reads the secret from vars.

### Workstation user credentials

The operator's home uses Clan vars. The opt-in
`workstation-user-secrets` aspect declares a shared generator with files
owned by `deepwatrcreatur` and mode `0400`. It also exposes the GitHub token
at the path expected by `gh-fnox`. Enable the aspect only on a workstation
selected for the migration or its coordinated verification.

Imported values are stored under `vars/shared/workstation-user-secrets`.
Lattitude now declares this aspect, and its machine key is a recipient for
these encrypted vars. No live machine has read them. Emerald remains
admin-only. Live verification on each host still needs the maintainer's
coordination and covers credential delivery and preservation of existing
application state.

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
- The `nix-cache-auth` aspect enables the NixCI substituter and signing key
  alongside that netrc. Router-class hosts use the public cache and
  anonymous Attic reads. Separately scoped NixCI downloads for those hosts
  are tracked in `nch-sny.38`.
- The `nix-cache-auth` flake check verifies the NixCI endpoint, key and netrc
  on the exported NixOS configurations and checks the public-cache fallback.
- attic's `cache-local` answers unauthenticated reads on the LAN, so pulls
  need no credential. The token only gates pushes (the post-build push hook
  has not been ported yet). Never put it in netrc: the attic substituters are
  plain HTTP, and Nix would send it in clear.
- emerald has no clan host certificate yet, so builder trust pins its host
  key (`keys/emerald-host-ed25519.pub`).
