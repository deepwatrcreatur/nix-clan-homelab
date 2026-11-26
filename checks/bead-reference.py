import runpy
import sys
import unittest

ref = runpy.run_path(sys.argv.pop(1))
issues = ref["load"]([
    '{"id":"nch-a","status":"in_progress"}',
    '{"id":"nch-b","status":"open"}',
    '{"id":"nch-c","status":"in_progress"}',
])
check = lambda body: ref["problems"](body, issues)


class BeadReferenceTests(unittest.TestCase):
    def test_claimed_bead_passes(self):
        self.assertEqual(check("Fixes things.\n\nBead: nch-a\n"), [])

    def test_several_ids_and_backticks(self):
        self.assertEqual(check("Bead: `nch-a`, nch-c"), [])

    def test_case_and_indent(self):
        self.assertEqual(check("  bead: nch-a"), [])

    def test_missing_line_fails(self):
        self.assertIn("no `Bead: <id>` line", check("Just a description.")[0])
        self.assertEqual(len(check(None)), 1)

    def test_unknown_bead_fails(self):
        self.assertIn("not on the beads-queue", check("Bead: nch-zzz")[0])

    def test_unclaimed_bead_fails(self):
        self.assertIn("claim it", check("Bead: nch-b")[0])

    def test_none_needs_reason(self):
        self.assertEqual(check("Bead: none (dependency bump)"), [])
        self.assertEqual(check("Bead: none - typo fix"), [])
        self.assertIn("needs a reason", check("Bead: none")[0])
        self.assertIn("needs a reason", check("Bead: none ()")[0])

    def test_mention_in_prose_is_not_a_line(self):
        self.assertEqual(len(check("This relates to the Bead: nch-a idea")), 1)


unittest.main()
