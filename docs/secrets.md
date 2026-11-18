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
| cache/builder | `nix-cache-auth`, `remote-builder-client` | `nix-cache-auth/{attic-token,netrc}`, `nix-remote-builder/key` | imported; verified on clan-spike |
| user/operator | | user passwords, github-token, API keys | todo |
| homeserver services | | | todo |
| router services | | | todo |

An agenix file is deleted from unified only once every host that used it
reads the secret from vars.

### cache/builder notes

- `netrc` contains the nix-ci entry plus one attic entry per substituter
  host. Nix sends the netrc password as the credential.
- attic's `cache-local` answers unauthenticated reads on the LAN, so the
  token only gates pushes (the post-build push hook has not been ported yet).
- emerald has no clan host certificate yet, so builder trust pins its host
  key (`keys/emerald-host-ed25519.pub`).
