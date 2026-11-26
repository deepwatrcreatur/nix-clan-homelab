"""Show which migrated hosts lag this checkout or need a reboot.

Usage: fleet-status [HOST...]

Read-only. For each host it compares the running system with the one this
checkout evaluates to (no build), and reads the booted kernel and initrd, the
time of the last switch and the failed units over one SSH connection.
FLEET_STATUS_HOSTS (set by the Nix wrapper) is a JSON object
{host: {"target": "user@addr", "alias": "host key alias"}}.

Exit status: 0 when every host is current, booted into its current kernel,
and has no failed units; 1 otherwise; 2 on bad usage.
"""

import json
import os
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor

# WHY: one connection per host, printing key=value lines, so a slow or
# half-broken host cannot leave the output half-parsed.
REMOTE = r"""
PATH=/run/current-system/sw/bin
echo "current=$(readlink -f /run/current-system)"
echo "booted_kernel=$(readlink -f /run/booted-system/kernel)"
echo "current_kernel=$(readlink -f /run/current-system/kernel)"
echo "booted_initrd=$(readlink -f /run/booted-system/initrd)"
echo "current_initrd=$(readlink -f /run/current-system/initrd)"
echo "switched=$(stat -c %Y /nix/var/nix/profiles/system)"
echo "failed=$(systemctl list-units --failed --plain --no-legend --no-pager | cut -d' ' -f1 | paste -sd, -)"
"""
SSH_TIMEOUT = 20


def read_host(name, host):
    """Return the host's key=value facts, or {"error": reason}."""
    command = [
        "ssh",
        "-o", "BatchMode=yes",
        "-o", "ConnectTimeout=5",
        "-o", f"HostKeyAlias={host['alias']}",
        host["target"],
        REMOTE,
    ]
    try:
        done = subprocess.run(command, capture_output=True, text=True, timeout=SSH_TIMEOUT)
    except subprocess.TimeoutExpired:
        return {"error": f"no answer in {SSH_TIMEOUT}s"}
    if done.returncode != 0:
        last = (done.stderr.strip().splitlines() or [f"ssh exited {done.returncode}"])[-1]
        return {"error": last}
    facts = dict(line.split("=", 1) for line in done.stdout.splitlines() if "=" in line)
    if not facts.get("current", "").startswith("/nix/store/"):
        return {"error": "could not read /run/current-system"}
    return facts


def expected_toplevels(names):
    """Evaluate (not build) each host's system in this checkout."""
    hosts = " ".join(json.dumps(n) for n in names)
    apply = (
        "cs: builtins.listToAttrs (map (n: { name = n; "
        "value = cs.${n}.config.system.build.toplevel.outPath; }) [ " + hosts + " ])"
    )
    done = subprocess.run(
        ["nix", "eval", "--json", ".#nixosConfigurations", "--apply", apply],
        capture_output=True, text=True,
    )
    if done.returncode != 0:
        sys.stderr.write(done.stderr)
        raise SystemExit("fleet-status: evaluating this checkout failed")
    return json.loads(done.stdout)


def ago(seconds):
    for unit, size in (("d", 86400), ("h", 3600), ("m", 60)):
        if seconds >= size:
            return f"{seconds // size}{unit} ago"
    return "just now"


def assess(facts, expected, now):
    """Return (row cells, needs attention) for one host."""
    if "error" in facts:
        return ["unreachable", "-", "-", facts["error"]], True
    state = "current" if facts["current"] == expected else "behind"
    reboot = (
        facts.get("booted_kernel") != facts.get("current_kernel")
        or facts.get("booted_initrd") != facts.get("current_initrd")
    )
    try:
        switched = ago(max(0, now - int(facts.get("switched", ""))))
    except ValueError:
        switched = "?"
    failed = facts.get("failed", "")
    cells = [state, "needed" if reboot else "no", switched, failed or "none"]
    return cells, state != "current" or reboot or bool(failed)


def table(rows):
    header = ["HOST", "SYSTEM", "REBOOT", "LAST SWITCH", "FAILED UNITS"]
    widths = [max(len(r[i]) for r in [header, *rows]) for i in range(len(header) - 1)]
    return [
        "  ".join(c.ljust(w) for c, w in zip(r, widths)) + "  " + r[-1]
        for r in [header, *rows]
    ]


def main(argv):
    hosts = json.loads(os.environ["FLEET_STATUS_HOSTS"])
    names = argv[1:] or sorted(hosts)
    if any(n.startswith("-") for n in names):
        print(__doc__.split("\n\n")[1], file=sys.stderr)
        return 2
    unknown = [n for n in names if n not in hosts]
    if unknown:
        print(f"Not a migrated Clan machine: {', '.join(unknown)}", file=sys.stderr)
        return 2
    with ThreadPoolExecutor(max_workers=len(names)) as pool:
        reads = {n: pool.submit(read_host, n, hosts[n]) for n in names}
        expected = expected_toplevels(names)
        facts = {n: f.result() for n, f in reads.items()}
    now = int(time.time())
    rows, attention = [], False
    for name in names:
        cells, flag = assess(facts[name], expected[name], now)
        rows.append([name, *cells])
        attention |= flag
    print("\n".join(table(rows)))
    print("SYSTEM compares with this checkout; behind means `fleet-deploy <host>` would change it.")
    return 1 if attention else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
