import json
import os
import runpy
import subprocess
import sys
import tempfile
import unittest

script = sys.argv.pop(1)
status = runpy.run_path(script)


def path(name, digest="a"):
    return f"/nix/store/{digest * 32}-{name}"


SYSTEM = path("nixos-system-a")
NOW = 1_000_000


def facts(**changes):
    base = {
        "current": SYSTEM,
        "booted_kernel": path("linux-7.3/bzImage"),
        "current_kernel": path("linux-7.3/bzImage"),
        "booted_initrd": path("initrd"),
        "current_initrd": path("initrd"),
        "switched": str(NOW - 7200),
        "failed": "",
    }
    return {**base, **changes}


class AssessTests(unittest.TestCase):
    def test_healthy(self):
        self.assertEqual(
            status["assess"](facts(), SYSTEM, NOW),
            (["current", "no", "2h ago", "none"], False),
        )

    def test_behind(self):
        cells, flag = status["assess"](facts(), path("nixos-system-a", "b"), NOW)
        self.assertEqual(cells[0], "behind")
        self.assertTrue(flag)

    def test_reboot_on_kernel_or_initrd(self):
        for change in ({"current_kernel": path("linux-7.4/bzImage")}, {"current_initrd": path("initrd", "b")}):
            cells, flag = status["assess"](facts(**change), SYSTEM, NOW)
            self.assertEqual(cells[1], "needed")
            self.assertTrue(flag)

    def test_failed_units(self):
        cells, flag = status["assess"](facts(failed="a.service,b.timer"), SYSTEM, NOW)
        self.assertEqual(cells[3], "a.service,b.timer")
        self.assertTrue(flag)

    def test_unreachable(self):
        cells, flag = status["assess"]({"error": "Connection refused"}, SYSTEM, NOW)
        self.assertEqual(cells, ["unreachable", "-", "-", "Connection refused"])
        self.assertTrue(flag)

    def test_failed_unit_query_is_not_healthy(self):
        broken = facts(failed_query="error")
        del broken["failed"]
        cells, flag = status["assess"](broken, SYSTEM, NOW)
        self.assertEqual(cells[3], "unknown (systemctl failed)")
        self.assertTrue(flag)

    def test_unread_boot_fact_is_not_healthy(self):
        cells, flag = status["assess"](facts(booted_initrd=""), SYSTEM, NOW)
        self.assertEqual(cells[1], "unknown")
        self.assertTrue(flag)

    def test_remote_failed_query(self):
        """Runs REMOTE in sh with systemctl failing like 'Failed to connect to bus'."""
        stub = tempfile.mkdtemp()
        with open(os.path.join(stub, "systemctl"), "w") as handle:
            handle.write("#!/bin/sh\necho 'Failed to connect to bus' >&2\nexit 1\n")
        os.chmod(os.path.join(stub, "systemctl"), 0o755)
        remote = status["REMOTE"].replace("PATH=/run/current-system/sw/bin", f"PATH={stub}:$PATH")
        out = subprocess.run(["sh", "-c", remote], capture_output=True, text=True).stdout
        self.assertIn("failed_query=error", out)
        self.assertNotIn("failed=", out.replace("failed_query", ""))

    def test_remote_no_failed_units(self):
        stub = tempfile.mkdtemp()
        with open(os.path.join(stub, "systemctl"), "w") as handle:
            handle.write("#!/bin/sh\nexit 0\n")
        os.chmod(os.path.join(stub, "systemctl"), 0o755)
        remote = status["REMOTE"].replace("PATH=/run/current-system/sw/bin", f"PATH={stub}:$PATH")
        out = subprocess.run(["sh", "-c", remote], capture_output=True, text=True).stdout
        self.assertIn("failed=\n", out)

    def test_bad_switch_time(self):
        self.assertEqual(status["assess"](facts(switched=""), SYSTEM, NOW)[0][2], "?")


class EndToEndTests(unittest.TestCase):
    """Runs the script with ssh and nix replaced by stubs on PATH."""

    def setUp(self):
        self.dir = tempfile.mkdtemp()
        bin_dir = os.path.join(self.dir, "bin")
        os.mkdir(bin_dir)
        self.log = os.path.join(self.dir, "ssh.log")
        # good: current; stale: behind and needs a reboot; down: refused.
        stub_ssh = f"""#!/bin/sh
printf '%s\\n' "$*" >> {self.log}
case "$*" in
  *root@good*) printf 'current={SYSTEM}\\nbooted_kernel=k\\ncurrent_kernel=k\\nbooted_initrd=i\\ncurrent_initrd=i\\nswitched=0\\nfailed=\\n' ;;
  *root@stale*) printf 'current={path("old")}\\nbooted_kernel=k\\ncurrent_kernel=k2\\nbooted_initrd=i\\ncurrent_initrd=i\\nswitched=0\\nfailed=x.service\\n' ;;
  *) echo 'ssh: connect to host down port 22: Connection refused' >&2; exit 255 ;;
esac
"""
        stub_nix = f"""#!/bin/sh
echo '{json.dumps({"good": SYSTEM, "stale": SYSTEM, "down": SYSTEM})}'
"""
        for name, text in (("ssh", stub_ssh), ("nix", stub_nix)):
            file = os.path.join(bin_dir, name)
            with open(file, "w") as handle:
                handle.write(text)
            os.chmod(file, 0o755)
        hosts = {
            n: {"target": f"root@{n}", "alias": f"{n}.example"} for n in ("good", "stale", "down")
        }
        self.env = {
            **os.environ,
            "PATH": bin_dir + os.pathsep + os.environ["PATH"],
            "FLEET_STATUS_HOSTS": json.dumps(hosts),
        }

    def run_status(self, *args):
        return subprocess.run(
            [sys.executable, script, *args], env=self.env, capture_output=True, text=True
        )

    def test_all_hosts(self):
        done = self.run_status()
        self.assertEqual(done.returncode, 1, done.stderr)
        rows = {line.split()[0]: line.split() for line in done.stdout.splitlines()[1:4]}
        self.assertEqual(rows["good"][1:3], ["current", "no"])
        self.assertEqual(rows["good"][-1], "none")
        self.assertEqual(rows["stale"][1:3], ["behind", "needed"])
        self.assertEqual(rows["stale"][-1], "x.service")
        self.assertEqual(rows["down"][1], "unreachable")
        self.assertIn("Connection refused", done.stdout)
        with open(self.log) as handle:
            calls = handle.read()
        self.assertIn("HostKeyAlias=good.example", calls)
        self.assertIn("BatchMode=yes", calls)

    def test_healthy_host_exits_zero(self):
        done = self.run_status("good")
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)

    def test_unknown_host(self):
        done = self.run_status("nope")
        self.assertEqual(done.returncode, 2)
        self.assertIn("Not a migrated Clan machine: nope", done.stderr)

    def test_flag_is_usage(self):
        self.assertEqual(self.run_status("--help").returncode, 2)

    def test_read_only_remote_command(self):
        # INVARIANT: the remote command only reads.
        for word in ("switch-to-configuration", "nix-env", "rm ", "systemctl start", "systemctl restart"):
            self.assertNotIn(word, status["REMOTE"])


unittest.main(argv=["fleet-status"], verbosity=1)
