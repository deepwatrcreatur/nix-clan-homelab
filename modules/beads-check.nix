{
  perSystem =
    { pkgs, ... }:
    {
      # UPSTREAM: fixed in beads_rust v0.7.0 (#486, #512); delete after nch-a9a.7.
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
