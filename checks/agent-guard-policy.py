import contextlib
import io
import json
import runpy
import sys
import unittest
from unittest.mock import patch


guard_path = sys.argv.pop(1)
sys.argv = [sys.argv[0]]
guard = runpy.run_path(guard_path)


class AgentGuardPolicyTests(unittest.TestCase):
    def test_multiline_separators_reach_the_destructive_command(self):
        commands = (
            "printf ok;\nrm -rf /home/agent-guard-test",
            "printf ok;\n\nrm -rf /home/agent-guard-test",
            "printf ok &&\nrm -rf /home/agent-guard-test",
        )
        for command in commands:
            with self.subTest(command=command):
                self.assertEqual(guard["evaluate"](command)[0], guard["ASK"])

    def test_hook_requests_confirmation_for_second_command(self):
        command = "printf ok;\nrm -rf /home/agent-guard-test"
        payload = json.dumps({"tool_input": {"command": command}})
        output = io.StringIO()
        with patch("sys.stdin", io.StringIO(payload)), contextlib.redirect_stdout(output):
            self.assertEqual(guard["main"](["agent-guard"]), 0)
        result = json.loads(output.getvalue())
        self.assertEqual(result["hookSpecificOutput"]["permissionDecision"], guard["ASK"])

    def test_quoted_separator_is_not_split(self):
        self.assertEqual(guard["evaluate"]("printf 'safe;\\ntext'")[0], guard["ALLOW"])

    def test_whole_store_scans_are_refused(self):
        for command in (
            "find /nix/store -name '*.so'",
            "find -L /nix/store/ -type f",
            "sudo find /nix -name hello",
            "rg foo /nix/store",
            "fd hello /nix/store",
            "grep -r foo /nix/store",
            "grep foo -rn /nix/store/",
            "ls -R /nix/store",
            "bash -c 'find /nix/store -name x'",
        ):
            with self.subTest(command=command):
                self.assertEqual(guard["evaluate"](command)[0], guard["SCAN"])

    def test_narrow_store_reads_are_allowed(self):
        for command in (
            "find /nix/store/abc-hello -name '*.so'",
            "find /nix/store -maxdepth 1 -name '*-hello-*'",
            "find . -path /nix/store -prune",
            "rg foo /nix/store/abc-source",
            "grep foo /nix/store/abc-source/file",
            "ls /nix/store",
            "ls -ltr /nix/store",
            "ls -d /nix/store/*-hello",
            "rg nix/store .",
        ):
            with self.subTest(command=command):
                self.assertEqual(guard["evaluate"](command)[0], guard["ALLOW"])

    def test_scan_is_denied_with_an_alternative(self):
        payload = json.dumps({"tool_input": {"command": "find /nix/store -name x"}})
        output = io.StringIO()
        with patch("sys.stdin", io.StringIO(payload)), contextlib.redirect_stdout(output):
            guard["main"](["agent-guard"])
        result = json.loads(output.getvalue())["hookSpecificOutput"]
        self.assertEqual(result["permissionDecision"], "deny")
        self.assertIn("nix flake archive", result["permissionDecisionReason"])

    def test_destructive_find_keeps_its_prompt(self):
        self.assertEqual(guard["evaluate"]("find /nix/store/abc -delete")[0], guard["ASK"])
        self.assertEqual(guard["evaluate"]("find /nix/store; rm -rf /")[0], guard["DENY"])


if __name__ == "__main__":
    unittest.main()
