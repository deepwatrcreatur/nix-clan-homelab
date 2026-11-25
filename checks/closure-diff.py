import runpy
import sys
import unittest

script = sys.argv.pop(1)
diff = runpy.run_path(script)


def path(name, digest="a"):
    return f"/nix/store/{digest * 32}-{name}"


class ClosureDiffTests(unittest.TestCase):
    def test_identical(self):
        self.assertIn("No changes", diff["report"]({path("hello-1.0")}, {path("hello-1.0")})[0])

    def test_names_and_versions(self):
        found = diff["packages"]({path("gcc-13.2.0-lib"), path("unit-sshd.service"), path("source")})
        self.assertEqual(set(found), {"gcc", "unit-sshd.service", "source"})
        self.assertEqual(set(found["gcc"]), {"13.2.0-lib"})

    def test_sections(self):
        old = {path("a-1"), path("gone-2"), path("etc")}
        new = {path("a-2"), path("new-3"), path("etc", "b")}
        self.assertEqual(
            diff["report"](old, new),
            [
                "Changed versions (1):", "  a: 1 -> 2",
                "Added (1):", "  new: 3",
                "Removed (1):", "  gone: 2",
                "Rebuilt or reconfigured (1):", "  etc",
                "Store paths: 3 -> 3",
            ],
        )

    def test_kernel_rebuild_is_reported(self):
        old = {path("linux-6.18.44"), path("linux-firmware-20260810")}
        self.assertTrue(any("reboot" in l for l in diff["report"](old, {path("linux-6.18.44", "b"), path("linux-firmware-20260810")})))
        self.assertFalse(any("reboot" in l for l in diff["report"](old, {path("linux-6.18.44"), path("linux-firmware-20261019")})))

    def test_rejects_other_output(self):
        with self.assertRaises(ValueError):
            diff["packages"]({"Warning: something"})


unittest.main()
