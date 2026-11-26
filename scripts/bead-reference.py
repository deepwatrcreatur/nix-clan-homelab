"""Check a pull request description's `Bead:` lines against the beads queue.

Usage: bead-reference.py ISSUES_JSONL   (PR description on stdin)

Every PR to main names its bead (docs/discussions/01-beads-rust-task-tracker.md):
  Bead: nch-a9a.8            one or more ids, comma or space separated;
                             each must exist on beads-queue and be claimed
  Bead: none (<reason>)      for work without a bead; the reason is required
"""

import json
import re
import sys

LINE = re.compile(r"^\s*bead:\s*(?P<value>.*?)\s*$", re.IGNORECASE | re.MULTILINE)
NONE = re.compile(r"^none\b\s*(?P<reason>.*)$", re.IGNORECASE)


def load(lines):
    return {
        issue["id"]: issue
        for issue in (json.loads(line) for line in lines if line.strip())
    }


def problems(body, issues):
    values = [m["value"] for m in LINE.finditer(body or "")]
    if not values:
        return [
            "The PR description has no `Bead: <id>` line. Name the claimed bead, "
            "or write `Bead: none (<reason>)`."
        ]
    errors = []
    for value in values:
        none = NONE.match(value)
        if none:
            reason = none["reason"].strip(" ()-:")
            if not reason:
                errors.append("`Bead: none` needs a reason, e.g. `Bead: none (dependency bump)`.")
            continue
        ids = [i for i in re.split(r"[\s,]+", value.strip("`")) if i]
        if not ids:
            errors.append("Empty `Bead:` line.")
        for bead_id in (i.strip("`") for i in ids):
            issue = issues.get(bead_id)
            if issue is None:
                errors.append(f"Bead `{bead_id}` is not on the beads-queue branch.")
            elif issue.get("status") != "in_progress":
                errors.append(
                    f"Bead `{bead_id}` is `{issue.get('status')}`, not in progress: "
                    f"claim it with `beads-q update {bead_id} --claim --actor <you>`."
                )
    return errors


if __name__ == "__main__":
    with open(sys.argv[1], encoding="utf-8") as handle:
        found = problems(sys.stdin.read(), load(handle))
    for error in found:
        print(f"::error title=Bead reference::{error}")
    if not found:
        print("Bead reference OK.")
    sys.exit(1 if found else 0)
