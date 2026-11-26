{ inputs, ... }:
{
  perSystem =
    { config, pkgs, ... }:
    {
      packages.beads-q = pkgs.callPackage ./_packages/beads-queue.nix {
        beads-rust = pkgs.callPackage ./_packages/beads-rust.nix { };
        script = inputs.unified + "/pkgs/beads-queue.sh";
      };

      # INVARIANT: the beads queue lives on the beads-queue branch, written only
      # by beads-q. A .beads/ directory on main means a feature PR carried
      # bead state again, which is what docs/discussions/01-beads-rust-task-tracker.md
      # moved away from. The duplicate-id check runs on that branch instead.
      checks.no-beads-on-main =
        assert !builtins.pathExists ../.beads;
        pkgs.runCommand "no-beads-on-main" { } "touch $out";

      # WHY: the Bead: line rule runs in GitHub Actions (it needs the PR
      # description); its parsing is tested here.
      checks.bead-reference = pkgs.runCommand "bead-reference" { nativeBuildInputs = [ pkgs.python3 ]; } ''
        python3 ${../checks/bead-reference.py} ${../scripts/bead-reference.py}
        touch $out
      '';

      # A short run of the claim race (scripts/beads-q-race-test.sh; the full
      # matrix and results are in docs/discussions/01-beads-rust-task-tracker.md):
      # four clones claim one bead per round with a forced push retry, and a
      # wrapper that skips revalidation must fail the same harness.
      checks.beads-q-race =
        let
          beadsRust = pkgs.callPackage ./_packages/beads-rust.nix { };
        in
        pkgs.runCommand "beads-q-race"
          {
            nativeBuildInputs = [
              pkgs.git
              pkgs.python3
            ];
          }
          ''
            bash ${../scripts/beads-q-race-test.sh} ${config.packages.beads-q}/bin/beads-q 4 10 $TMPDIR/race ${beadsRust}/bin/beads-rust
            cp ${../scripts/beads-q-race-broken.sh} broken-q && chmod +x broken-q && patchShebangs broken-q
            if BROKEN_BR=${beadsRust}/bin/beads-rust bash ${../scripts/beads-q-race-test.sh} \
                $PWD/broken-q 4 3 $TMPDIR/control ${beadsRust}/bin/beads-rust > control.log 2>&1; then
              cat control.log
              echo "negative control passed: the harness cannot detect double claims" >&2
              exit 1
            fi
            # INVARIANT: it must fail because of double claims, not a broken setup.
            grep -qE 'wins=[2-9]' control.log || { cat control.log; exit 1; }
            touch $out
          '';

      # From a source checkout with no .beads/, beads-q reads the queue branch
      # and pushes a write to it (the Clan homes' only way to reach the queue).
      checks.beads-q-smoke =
        pkgs.runCommand "beads-q-smoke"
          {
            nativeBuildInputs = [
              config.packages.beads-q
              pkgs.git
            ];
          }
          ''
            export HOME=$TMPDIR/home GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
            mkdir -p "$HOME"
            git init -q --bare remote.git
            git clone -q remote.git seed && cd seed
            git checkout -q --orphan beads-queue
            mkdir .beads
            printf 'issue_prefix: tst\n' > .beads/config.yaml
            printf '%s\n' '{"id":"tst-abc","title":"seed","status":"open","priority":2,"issue_type":"task","created_at":"2026-11-26T00:00:00Z","updated_at":"2026-11-26T00:00:00Z"}' > .beads/issues.jsonl
            git add .beads && git commit -q -m seed && git push -q origin beads-queue
            cd .. && git clone -q remote.git src && cd src
            git commit -q --allow-empty -m code
            test ! -e .beads
            beads-q ready --json | grep -q tst-abc
            beads-q create "from smoke" -t task -p 3 --actor smoke >/dev/null
            git -C ../remote.git show beads-queue:.beads/issues.jsonl | grep -q '"from smoke"'
            touch $out
          '';
    };
}
