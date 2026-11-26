#!/usr/bin/env bash
# beads-q claim race test (nch-a9a.9, discussion 01).
# usage: beads-q-race-test.sh <beads-q binary> <K clients> <rounds> <workdir> <beads-rust binary>
# K clones of one bare remote (separate clones = separate beads-q locks, so
# they behave like separate machines) claim the same bead at a barrier.
# A pre-receive hook rejects the first push of every round, so the retry
# path runs every time. Checks per round: exactly one exit 0, every other
# client exits 4 with CLAIM_CONFLICT (0.1.45 says "already assigned"), exactly one claim commit for that bead.
# Final checks: linear history, and a fresh import shows each bead assigned
# to that round's winner.
set -uo pipefail
BQ=$1; K=$2; ROUNDS=$3; W=$4; BR=$5
rm -rf "$W"; mkdir -p "$W"; cd "$W"
export HOME=$W/home GIT_AUTHOR_NAME=race GIT_AUTHOR_EMAIL=race@test GIT_COMMITTER_NAME=race GIT_COMMITTER_EMAIL=race@test
mkdir -p "$HOME"

git init -q --bare remote.git
cat > remote.git/hooks/pre-receive <<EOF
#!/bin/sh
if [ -e "$W/reject-once" ]; then rm -f "$W/reject-once"; echo "race: rejecting first push" >&2; exit 1; fi
EOF
chmod +x remote.git/hooks/pre-receive

git clone -q remote.git seed 2>/dev/null; cd seed
git checkout -q --orphan beads-queue
mkdir .beads
printf 'issue_prefix: tst\n' > .beads/config.yaml
for r in $(seq -w 1 "$ROUNDS"); do
  printf '{"id":"tst-r%s","title":"round %s","status":"open","priority":2,"issue_type":"task","created_at":"2026-11-26T00:00:00Z","updated_at":"2026-11-26T00:00:00Z"}\n' "$r" "$r"
done > .beads/issues.jsonl
git add .beads && git commit -q -m seed && git push -q origin beads-queue
cd "$W"

for c in $(seq 1 "$K"); do
  git clone -q remote.git "c$c" 2>/dev/null
  git -C "c$c" commit -q --allow-empty -m code
done

fail=0; retries_seen=0
declare -A winner
start=$(date +%s)
for r in $(seq -w 1 "$ROUNDS"); do
  bead=tst-r$r
  rm -f "$W/go"; touch "$W/reject-once"
  for c in $(seq 1 "$K"); do
    (
      while [ ! -e "$W/go" ]; do sleep 0.005; done
      BEADS_Q_DIR=$W/q$c "$BQ" -C "$W/c$c" update "$bead" --claim --actor "c$c" >"$W/out.$c" 2>&1
      echo $? >"$W/rc.$c"
    ) &
  done
  sleep 0.2; touch "$W/go"; wait
  wins=0; conflicts=0; other=""
  for c in $(seq 1 "$K"); do
    rc=$(cat "$W/rc.$c")
    if [ "$rc" = 0 ]; then wins=$((wins+1)); winner[$bead]=c$c
    elif [ "$rc" = 4 ] && grep -qE "CLAIM_CONFLICT|already assigned" "$W/out.$c"; then conflicts=$((conflicts+1))
    else other="$other c$c:rc=$rc:$(tr '\n' ' ' <"$W/out.$c" | cut -c1-160)"; fi
    grep -q "retrying on the new tip" "$W/out.$c" && retries_seen=$((retries_seen+1))
  done
  commits=$(git -C remote.git log --format=%s beads-queue | grep -c -- "update $bead --claim")
  if [ "$wins" != 1 ] || [ "$conflicts" != $((K-1)) ] || [ "$commits" != 1 ] || [ -n "$other" ]; then
    fail=$((fail+1)); echo "ROUND $r FAIL wins=$wins conflicts=$conflicts commits=$commits$other"
  fi
  [ -e "$W/reject-once" ] && { fail=$((fail+1)); echo "ROUND $r FAIL: no push reached the hook"; }
done
elapsed=$(( $(date +%s) - start ))

merges=$(git -C remote.git log --merges --oneline beads-queue | wc -l)
[ "$merges" = 0 ] || { fail=$((fail+1)); echo "FAIL: $merges merge commits"; }

# Fresh import of the final queue: each bead assigned to its round's winner.
mkdir -p fresh/.beads && git -C remote.git show beads-queue:.beads/issues.jsonl > fresh/.beads/issues.jsonl
cp seed/.beads/config.yaml fresh/.beads/
git -C fresh init -q
bad=0
while read -r line; do
  id=$(printf '%s' "$line" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d["id"], d.get("assignee",""), d["status"])')
  set -- $id
  [ "${2:-}" = "${winner[$1]:-}" ] && [ "${3:-}" = in_progress ] || { bad=$((bad+1)); echo "FAIL final: $id expected ${winner[$1]:-none}"; }
done < fresh/.beads/issues.jsonl
[ "$bad" = 0 ] || fail=$((fail+1))
# The final JSONL must also rebuild into a database that agrees.
if ( cd fresh && export BEADS_DIR=$PWD/.beads && "$BR" sync --import-only >/dev/null 2>&1 ); then
  got=$(cd fresh && BEADS_DIR=$PWD/.beads "$BR" show tst-r$(printf '%0*d' ${#ROUNDS} 1) --json 2>/dev/null | python3 -c 'import json,sys;d=json.load(sys.stdin);d=d[0] if isinstance(d,list) else d;print(d.get("assignee",""))')
  [ "$got" = "${winner[tst-r$(printf '%0*d' ${#ROUNDS} 1)]}" ] || { fail=$((fail+1)); echo "FAIL: rebuilt DB assignee $got"; }
else fail=$((fail+1)); echo "FAIL: final JSONL does not import"; fi

total_commits=$(git -C remote.git rev-list --count beads-queue)
echo "RESULT K=$K rounds=$ROUNDS failures=$fail clients_that_retried=$retries_seen commits=$total_commits merges=$merges elapsed=${elapsed}s"
[ "$fail" = 0 ]
