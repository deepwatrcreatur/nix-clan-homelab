"""Fail on .beads/issues.jsonl records that a fresh clone cannot import.

Issue IDs (`<parent>.N`) and comment IDs come from each clone's own SQLite
counter, so parallel branches can mint the same ID; git merges both lines
cleanly and the next `beads-rust` rebuild dies on a UNIQUE constraint.
"""

import json
import sys
from collections import defaultdict


def problems(lines):
    issues = {}
    comments = defaultdict(list)
    deps = []
    errors = []
    for number, line in enumerate(lines, 1):
        if not line.strip():
            continue
        try:
            issue = json.loads(line)
        except json.JSONDecodeError as error:
            errors.append(f"line {number}: invalid JSON ({error.msg})")
            continue
        issue_id = issue.get("id")
        if issue_id in issues:
            errors.append(
                f"line {number}: issue {issue_id} duplicates line {issues[issue_id]}"
            )
        else:
            issues[issue_id] = number
        for comment in issue.get("comments") or []:
            comments[comment.get("id")].append(issue_id)
            if comment.get("issue_id") != issue_id:
                errors.append(
                    f"line {number}: comment {comment.get('id')} names issue "
                    f"{comment.get('issue_id')} but sits under {issue_id}"
                )
        for dep in issue.get("dependencies") or []:
            deps.append((number, issue_id, dep.get("depends_on_id")))
    for comment_id, owners in sorted(comments.items(), key=lambda kv: str(kv[0])):
        if len(owners) > 1:
            errors.append(
                f"comment id {comment_id} is used {len(owners)} times "
                f"({', '.join(owners)}); renumber the newer one above the max"
            )
    for number, issue_id, target in deps:
        if target not in issues:
            errors.append(f"line {number}: {issue_id} depends on missing {target}")
    return errors


def self_test():
    ok = [
        '{"id":"a","comments":[{"id":1,"issue_id":"a"}]}',
        '{"id":"b","dependencies":[{"depends_on_id":"a"}]}',
    ]
    assert problems(ok) == [], problems(ok)
    dup_comment = ['{"id":"a","comments":[{"id":1,"issue_id":"a"}]}',
                   '{"id":"b","comments":[{"id":1,"issue_id":"b"}]}']
    assert any("comment id 1" in e for e in problems(dup_comment))
    dup_issue = ['{"id":"a"}', '{"id":"a"}']
    assert any("duplicates" in e for e in problems(dup_issue))
    dangling = ['{"id":"b","dependencies":[{"depends_on_id":"z"}]}']
    assert any("missing z" in e for e in problems(dangling))
    assert any("invalid JSON" in e for e in problems(["{"]))


if __name__ == "__main__":
    self_test()
    with open(sys.argv[1], encoding="utf-8") as handle:
        found = problems(handle.read().splitlines())
    for error in found:
        print(error, file=sys.stderr)
    sys.exit(1 if found else 0)
