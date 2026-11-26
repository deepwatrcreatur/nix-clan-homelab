# beads-q: runs beads-rust against the repo's shared beads-queue branch.
# UPSTREAM: the script is unified's pkgs/beads-queue.sh, used as is, so the
# two repos run one wrapper. Package it here because Clan-managed homes do not
# get unified's overlay.
{
  beads-rust,
  coreutils,
  git,
  script,
  util-linux,
  writeShellApplication,
}:
writeShellApplication {
  name = "beads-q";
  runtimeInputs = [
    beads-rust
    coreutils
    git
    util-linux
  ];
  text = builtins.readFile script;
}
