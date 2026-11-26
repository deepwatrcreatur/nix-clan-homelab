"""Post-deploy health check for fleet-deploy (nch-a9a.2).

Usage:
  deploy-health before ALIAS TARGET > SNAPSHOT
  deploy-health after ALIAS TARGET SNAPSHOT

`before` records the system profile generation and the failed units.
`after` opens a new SSH connection (so a deploy that broke SSH is caught),
waits for systemd to leave "starting", and fails if a unit failed that was
not failed before. On failure it prints the command that returns the host
to the generation recorded by `before`; it never runs it.

Exit status: 0 healthy; 1 unhealthy or unreachable; 2 bad usage.
"""

import json
import os
import re
import shlex
import subprocess
import sys
import time

REMOTE = r"""
PATH=/run/current-system/sw/bin
echo "profile=$(readlink /nix/var/nix/profiles/system)"
echo "state=$(systemctl is-system-running)"
# GOTCHA: test systemctl's own status; inside a pipeline a failed query
# would look like "no failed units".
if units=$(systemctl list-units --failed --plain --no-legend --no-pager); then
  echo "failed=$(printf '%s\n' "$units" | cut -d' ' -f1 | paste -sd, -)"
else
  echo "failed_query=error"
fi
"""
GENERATION = re.compile(r"^system-(\d+)-link$")
# WHY: activation restarts units; systemd reports "starting" until jobs drain.
SETTLE_SECONDS = int(os.environ.get("DEPLOY_HEALTH_SETTLE", "60"))
POLL_SECONDS = float(os.environ.get("DEPLOY_HEALTH_POLL", "3"))
SSH_TIMEOUT = 20


def read(alias, target):
    """Return the host's facts, or raise RuntimeError with the reason."""
    command = [
        "ssh",
        "-o", "BatchMode=yes",
        "-o", "ConnectTimeout=5",
        "-o", f"HostKeyAlias={alias}",
        target,
        REMOTE,
    ]
    try:
        done = subprocess.run(command, capture_output=True, text=True, timeout=SSH_TIMEOUT)
    except subprocess.TimeoutExpired:
        raise RuntimeError(f"no answer in {SSH_TIMEOUT}s")
    if done.returncode != 0:
        raise RuntimeError((done.stderr.strip().splitlines() or [f"ssh exited {done.returncode}"])[-1])
    facts = dict(line.split("=", 1) for line in done.stdout.splitlines() if "=" in line)
    if "failed_query" in facts or "failed" not in facts:
        raise RuntimeError("systemctl could not list failed units")
    match = GENERATION.match(facts.get("profile", ""))
    return {
        "generation": int(match[1]) if match else None,
        "state": facts.get("state", ""),
        "failed": sorted(u for u in facts["failed"].split(",") if u),
    }


def rollback_command(target, alias, generation):
    remote = (
        f"sudo nix-env -p /nix/var/nix/profiles/system --switch-generation {generation}"
        " && sudo /nix/var/nix/profiles/system/bin/switch-to-configuration switch"
    )
    return f"ssh -o HostKeyAlias={shlex.quote(alias)} {shlex.quote(target)} {shlex.quote(remote)}"


def verdict(before, after):
    """Return (healthy, report lines) comparing two snapshots."""
    new = sorted(set(after["failed"]) - set(before["failed"]))
    old = sorted(set(after["failed"]) & set(before["failed"]))
    lines = []
    if after["generation"] == before["generation"]:
        lines.append(f"System profile still at generation {before['generation']}: nothing was switched.")
    if new:
        lines.append(f"Failed since the deploy: {', '.join(new)}")
    if old:
        lines.append(f"Already failed before the deploy: {', '.join(old)}")
    healthy = not new and after["state"] in ("running", "degraded")
    if after["state"] not in ("running", "degraded"):
        lines.append(f"systemd state: {after['state']} (expected running)")
    return healthy, lines


def main(argv):
    if len(argv) == 4 and argv[1] == "before":
        try:
            print(json.dumps(read(argv[2], argv[3])))
        except RuntimeError as error:
            print(f"deploy-health: cannot read {argv[2]} before deploying: {error}", file=sys.stderr)
            return 1
        return 0
    if len(argv) != 5 or argv[1] != "after":
        print(__doc__.split("\n\n")[1], file=sys.stderr)
        return 2
    alias, target = argv[2], argv[3]
    with open(argv[4], encoding="utf-8") as handle:
        before = json.load(handle)
    deadline = time.monotonic() + SETTLE_SECONDS
    while True:
        try:
            after = read(alias, target)
        except RuntimeError as error:
            after = {"error": str(error)}
        settling = after.get("state") in ("starting", "initializing")
        if not settling or time.monotonic() >= deadline:
            break
        time.sleep(POLL_SECONDS)
    if "error" in after:
        healthy, lines = False, [f"Cannot reach the host after the deploy: {after['error']}"]
    else:
        healthy, lines = verdict(before, after)
    print(f"Health check: {'OK' if healthy else 'FAILED'}")
    for line in lines:
        print(f"  {line}")
    switched = after.get("generation", "unknown") != before.get("generation")
    if not healthy and switched and before.get("generation") is not None:
        print(f"To return to generation {before['generation']} (not run automatically):")
        print(f"  {rollback_command(target, alias, before['generation'])}")
    return 0 if healthy else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
