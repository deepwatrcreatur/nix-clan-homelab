# Do not use fnox scan as a secret-scanning gate yet

Status: accepted (2026-11-26)

## Context

Bead `nch-a67.5` evaluated adding `fnox scan` to local pre-commit and CI
checks. The pinned `fnox-flake` input is revision
`0186fa138a7032118bcb3d2f2c62da35f8903733`; its packaged fnox is version
1.19.0.

Running that package's `fnox scan` against this repository prints
`No implementation yet.` and exits successfully. Its help lists heuristic
scanning options but no way to scan actual configured values. It therefore
does not inspect the files and cannot enforce the repository's
"never commit secrets" rule. Adding it to pre-commit or CI would create a
misleading green check.

## Decision

Do not enable `fnox scan` as a pre-commit hook or CI check. Keep the existing
GitGuardian GitHub check as the automated secret-detection gate. This does
not change the rule against committing secrets or the practice of reviewing
staged changes before commit.

Reconsider when the pinned fnox implementation actually scans repository
contents and produces meaningful results. Before adoption, evaluate it on
the Nix repositories named in `nch-a67.5`, record known false positives
(including public keys and test fixtures), and add a narrow allowlist only
where the scanner supports one without hiding real credentials. Then wire it
into at least this repository's CI and local workflow and verify that a
controlled test secret is detected without printing its value.

## Evidence

The packaged version and scan behavior were checked on 2026-11-26 with the
`fnox-flake` input pinned above. A quiet scan also exits successfully with no
output, confirming that the current command is not a usable gate.
