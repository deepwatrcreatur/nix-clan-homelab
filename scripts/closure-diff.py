"""Compare two Nix closures by package name and version.

Usage: closure-diff OLD NEW

OLD and NEW are files with one store path per line. Only the lists are
needed, so the running host's paths do not have to exist locally.
"""

import re
import sys
from collections import defaultdict

STORE_PATH = re.compile(r"^/nix/store/[0-9a-z]{32}-(?P<name>.+)$")
# UPSTREAM: same rule as builtins.parseDrvName: the version starts at the first
# dash that is followed by something other than a letter.
VERSION = re.compile(r"^(?P<name>.+?)-(?P<version>[^a-zA-Z].*)$")


def read(path):
    with open(path, encoding="utf-8") as handle:
        return {line.strip() for line in handle if line.strip()}


def packages(paths):
    """Map package name -> {version: {store path}}."""
    found = defaultdict(lambda: defaultdict(set))
    for path in paths:
        match = STORE_PATH.match(path)
        if not match:
            raise ValueError(f"not a store path: {path}")
        split = VERSION.match(match["name"])
        name, version = (split["name"], split["version"]) if split else (match["name"], "")
        found[name][version].add(path)
    return found


def show(versions):
    return ", ".join(sorted(version or "(none)" for version in versions))


def report(old_paths, new_paths):
    if old_paths == new_paths:
        return ["No changes: the closures are identical."]
    old, new = packages(old_paths), packages(new_paths)
    changed, rebuilt = [], []
    for name in sorted(old.keys() & new.keys()):
        if old[name].keys() != new[name].keys():
            changed.append(f"  {name}: {show(old[name])} -> {show(new[name])}")
        elif old[name] != new[name]:
            rebuilt.append(name)
    lines = []
    for title, entries in (
        ("Changed versions", changed),
        ("Added", [f"  {n}: {show(new[n])}" for n in sorted(new.keys() - old.keys())]),
        ("Removed", [f"  {n}: {show(old[n])}" for n in sorted(old.keys() - new.keys())]),
        # WHY: one group, because a path list cannot tell a configuration change
        # from a rebuild caused by a dependency.
        ("Rebuilt or reconfigured", [f"  {n}" for n in rebuilt]),
    ):
        if entries:
            lines += [f"{title} ({len(entries)}):", *entries]
    lines.append(f"Store paths: {len(old_paths)} -> {len(new_paths)}")
    return lines


def main(argv):
    if len(argv) != 3:
        print("Usage: closure-diff OLD NEW", file=sys.stderr)
        return 2
    old_paths, new_paths = read(argv[1]), read(argv[2])
    # WHY: an empty list means the query failed, not that the host is empty.
    if not old_paths or not new_paths:
        print("closure-diff: empty closure list", file=sys.stderr)
        return 1
    print("\n".join(report(old_paths, new_paths)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
