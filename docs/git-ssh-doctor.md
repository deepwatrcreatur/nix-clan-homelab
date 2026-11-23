# Git SSH doctor

Run `git-ssh-doctor` in a checkout to check Git signing, the SSH agent,
GitHub authentication, and local verification of `HEAD`. Pass another
revision to inspect it, or use `git-ssh-doctor --offline` to skip the
GitHub connection. The connection probe requires an existing trusted
GitHub host key.

## Which key GitHub must have

Emerald and Phoenix use the same workstation key for GitHub SSH transport
and Git commit signing. The shared Home Manager identity pins
`github.com` to `~/.ssh/id_ed25519` with `IdentitiesOnly yes` and sets Git's
`user.signingkey` to its public counterpart at `~/.ssh/id_ed25519.pub`.

Register [the workstation public key](../keys/deepwatrcreatur-phoenix.pub)
on GitHub as both an **authentication key** and a **signing key**. Its
fingerprint is `SHA256:6DrmIDTuA8ev7n/D+VOdD/jtknzJMlm9yOYQBJ/QNOg`.
The doctor compares the local signing key against that fingerprint.

Missing authentication registration causes SSH pushes to fail with
`Permission denied (publickey)`. Missing signing registration can leave
commits locally verifiable while GitHub shows them as **Unverified**.
