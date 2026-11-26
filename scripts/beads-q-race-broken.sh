#!/usr/bin/env bash
# Negative control for beads-q-race-test.sh: claims on a stale copy and force-pushes, the
# way an agent bypassing beads-q (or a wrapper without revalidation) would.
set -uo pipefail
[ "$1" = -C ] && { dir=$2; shift 2; }
Q=$BEADS_Q_DIR; BR=${BROKEN_BR:?}
git -C "$dir" fetch -q origin +refs/heads/beads-queue:refs/remotes/origin/beads-queue
[ -d "$Q" ] || git -C "$dir" worktree add -q --detach "$Q" origin/beads-queue
git -C "$Q" reset -q --hard origin/beads-queue
rm -f "$Q"/.beads/beads.db*
sleep 0.3   # everyone reads the same tip
BEADS_DIR=$Q/.beads "$BR" "$@" || exit $?
BEADS_DIR=$Q/.beads "$BR" sync --flush-only >/dev/null
git -C "$Q" commit -qam "beads: $*"
git -C "$Q" push -q --force origin HEAD:refs/heads/beads-queue 2>/dev/null || git -C "$Q" push -q --force origin HEAD:refs/heads/beads-queue
