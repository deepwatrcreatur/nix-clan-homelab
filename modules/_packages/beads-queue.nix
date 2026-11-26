# beads-q: runs beads-rust against the repo's shared beads-queue branch.
# UPSTREAM: the script is unified's pkgs/beads-queue.sh, used as is, so the
# two repos run one wrapper. Package it here because Clan-managed homes do not
# get unified's overlay.
{
  beads-rust,
  coreutils,
  git,
  lib,
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
  # UPSTREAM: unified #265 makes the script remove beads-rust 0.7's database
  # sidecars too; drop this replacement once the unified input includes it.
  text =
    lib.replaceStrings
      [ ''rm -f "$BEADS_DIR"/beads.db "$BEADS_DIR"/beads.db-wal "$BEADS_DIR"/beads.db-shm'' ]
      [ ''rm -f "$BEADS_DIR"/beads.db "$BEADS_DIR"/beads.db-* "$BEADS_DIR"/beads.db.*'' ]
      (builtins.readFile script);
}
