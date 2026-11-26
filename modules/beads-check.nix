{
  perSystem =
    { pkgs, ... }:
    {
      # WHY: kept after beads_rust v0.7.0 fixed import (#486, #512): it is the
      # only guard against writes that bypass beads-q. docs/discussions/01-beads-rust-task-tracker.md
      # WHY: parallel branches mint the same bead or comment ID from their own
      # SQLite counters; git merges both, and fresh clones then fail to import.
      checks.beads-integrity = pkgs.runCommand "beads-integrity" {
        nativeBuildInputs = [ pkgs.python3 ];
      } ''
        python3 ${../checks/beads-integrity.py} ${../.beads/issues.jsonl}
        touch $out
      '';
    };
}
