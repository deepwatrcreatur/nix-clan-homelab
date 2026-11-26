"""Tests for scripts/deploy-health.py and its use in fleet-deploy.

Usage: deploy-health.py SCRIPT FLEET_DEPLOY
"""

import json
import os
import subprocess
import sys
import tempfile
import unittest

script = sys.argv.pop(1)
fleet_deploy = sys.argv.pop(1)
health = {}


def slurp(path):
    with open(path, encoding="utf-8") as handle:
        return handle.read()


exec(compile(slurp(script), script, "exec"), health)


def snap(generation=41, state="running", failed=()):
    return {"generation": generation, "state": state, "failed": sorted(failed)}


def answer(profile="system-41-link", state="running", failed=""):
    return f"profile={profile}\nstate={state}\nfailed={failed}\n"


class VerdictTests(unittest.TestCase):
    def test_healthy(self):
        self.assertEqual(health["verdict"](snap(), snap(42)), (True, []))

    def test_new_failure(self):
        ok, lines = health["verdict"](snap(), snap(42, "degraded", ["nginx.service"]))
        self.assertFalse(ok)
        self.assertIn("Failed since the deploy: nginx.service", lines)

    def test_old_failure_is_reported_not_fatal(self):
        before = snap(failed=["tailscaled-autoconnect.service"])
        ok, lines = health["verdict"](before, snap(42, "degraded", ["tailscaled-autoconnect.service"]))
        self.assertTrue(ok)
        self.assertIn("Already failed before the deploy: tailscaled-autoconnect.service", lines)

    def test_bad_state(self):
        for state in ("starting", "maintenance", "stopping", "offline"):
            self.assertFalse(health["verdict"](snap(), snap(42, state))[0], state)

    def test_no_switch_noted(self):
        ok, lines = health["verdict"](snap(), snap())
        self.assertTrue(ok)
        self.assertIn("nothing was switched", lines[0])

    def test_rollback_command(self):
        command = health["rollback_command"]("deepwatrcreatur@10.0.0.5", "spike.example", 41)
        self.assertEqual(
            command,
            "ssh -o HostKeyAlias=spike.example deepwatrcreatur@10.0.0.5 "
            "'sudo nix-env -p /nix/var/nix/profiles/system --switch-generation 41"
            " && sudo /nix/var/nix/profiles/system/bin/switch-to-configuration switch'",
        )

    def test_remote_is_read_only(self):
        for word in ("switch-to-configuration", "nix-env", "systemctl start", "systemctl restart", "rm "):
            self.assertNotIn(word, health["REMOTE"])


class StubbedRuns(unittest.TestCase):
    """ssh and clan-admin replaced by stubs. ssh answers are queued in
    files ssh.1, ssh.2, ... (ssh.N.fail: refuse the connection)."""

    def setUp(self):
        self.dir = tempfile.mkdtemp()
        bin_dir = os.path.join(self.dir, "bin")
        os.mkdir(bin_dir)
        stubs = {
            "ssh": f"""#!/bin/sh
d={self.dir}
n=$(cat $d/ssh.count 2>/dev/null || echo 0); n=$((n + 1)); echo $n > $d/ssh.count
printf '%s\\n' "$*" >> $d/ssh.log
if [ -e $d/ssh.$n.fail ]; then echo 'ssh: connect to host x port 22: Connection refused' >&2; exit 255; fi
[ -e $d/ssh.$n ] || n=last
cat $d/ssh.$n
""",
            "clan-admin": f"""#!/bin/sh
printf '%s\\n' "$*" >> {self.dir}/deploy.log
exit $(cat {self.dir}/deploy.rc 2>/dev/null || echo 0)
""",
        }
        for name, text in stubs.items():
            path = os.path.join(bin_dir, name)
            with open(path, "w") as handle:
                handle.write(text)
            os.chmod(path, 0o755)
        self.env = {
            **os.environ,
            "PATH": bin_dir + os.pathsep + os.environ["PATH"],
            "DEPLOY_HEALTH_SETTLE": "2",
            "DEPLOY_HEALTH_POLL": "0.1",
        }

    def queue(self, *answers):
        for n, text in enumerate(answers, 1):
            name = f"ssh.{n}.fail" if text is None else f"ssh.{n}"
            with open(os.path.join(self.dir, name), "w") as handle:
                handle.write(text or "")
        with open(os.path.join(self.dir, "ssh.last"), "w") as handle:
            handle.write(answers[-1] or "")

    def deploy(self, *args):
        return subprocess.run([fleet_deploy, *args], env=self.env, capture_output=True, text=True)

    def deployed(self):
        path = os.path.join(self.dir, "deploy.log")
        return slurp(path) if os.path.exists(path) else ""

    def test_healthy_deploy(self):
        self.queue(answer(), answer("system-42-link"))
        done = self.deploy("clan-spike")
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertEqual(self.deployed(), "machines update clan-spike\n")
        self.assertIn("Health check: OK", done.stdout)

    def test_new_failed_unit_fails_and_prints_rollback(self):
        self.queue(answer(), answer("system-42-link", "degraded", "nginx.service"))
        done = self.deploy("clan-spike")
        self.assertEqual(done.returncode, 1)
        self.assertIn("Failed since the deploy: nginx.service", done.stdout)
        self.assertIn("--switch-generation 41", done.stdout)
        # INVARIANT: the rollback is printed, not run: only the two reads went over ssh.
        self.assertEqual(slurp(os.path.join(self.dir, "ssh.count")).strip(), "2")

    def test_waits_for_starting_to_settle(self):
        self.queue(answer(), answer("system-42-link", "starting"), answer("system-42-link"))
        done = self.deploy("clan-spike")
        self.assertEqual(done.returncode, 0, done.stdout)

    def test_still_starting_after_settle_time_fails(self):
        self.queue(answer(), answer("system-42-link", "starting"))
        done = self.deploy("clan-spike")
        self.assertEqual(done.returncode, 1)
        self.assertIn("systemd state: starting", done.stdout)

    def test_unreachable_after_deploy(self):
        self.queue(answer(), None)
        done = self.deploy("clan-spike")
        self.assertEqual(done.returncode, 1)
        self.assertIn("Cannot reach the host after the deploy", done.stdout)
        self.assertIn("--switch-generation 41", done.stdout)

    def test_unreachable_before_does_not_deploy(self):
        self.queue(None)
        done = self.deploy("clan-spike")
        self.assertEqual(done.returncode, 1)
        self.assertEqual(self.deployed(), "")
        self.assertIn("--no-check", done.stderr)

    def test_failed_deploy_keeps_its_status_and_still_checks(self):
        with open(os.path.join(self.dir, "deploy.rc"), "w") as handle:
            handle.write("3")
        self.queue(answer(), answer())
        done = self.deploy("clan-spike")
        self.assertEqual(done.returncode, 3)
        self.assertIn("nothing was switched", done.stdout)

    def test_no_check_skips_ssh(self):
        done = self.deploy("--no-check", "clan-spike")
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(self.deployed(), "machines update clan-spike\n")
        self.assertFalse(os.path.exists(os.path.join(self.dir, "ssh.log")))

    def test_flag_after_host_and_usage(self):
        self.assertEqual(self.deploy("clan-spike", "--no-check").returncode, 0)
        for args in ([], ["--bogus", "clan-spike"], ["a", "b"], ["--dry-run", "--diff", "clan-spike"]):
            self.assertEqual(self.deploy(*args).returncode, 2, args)

    def test_dry_run_unchanged(self):
        done = self.deploy("--dry-run", "clan-spike")
        self.assertEqual(done.returncode, 0)
        self.assertEqual(done.stdout, "clan-admin machines update clan-spike\n")
        self.assertEqual(self.deployed(), "")


unittest.main(argv=["deploy-health"], verbosity=1)
