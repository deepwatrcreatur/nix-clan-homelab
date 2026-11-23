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


if __name__ == "__main__":
    unittest.main()
