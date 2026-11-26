{
  perSystem =
    { pkgs, ... }:
    {
      # INVARIANT: the beads queue lives on the beads-queue branch, written only
      # by beads-q. A .beads/ directory on main means a feature PR carried
      # bead state again, which is what docs/discussions/01-beads-rust-task-tracker.md
      # moved away from. The duplicate-id check runs on that branch instead.
      checks.no-beads-on-main =
        assert !builtins.pathExists ../.beads;
        pkgs.runCommand "no-beads-on-main" { } "touch $out";
    };
}
