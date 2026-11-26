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

    def test_rebuilt_kernel_same_version_needs_reboot(self):
        booted, new = path("linux-zen-7.3.4"), path("linux-zen-7.3.4", "b")
        self.assertIn("Rebuilt or reconfigured (1):", diff["report"]({booted}, {new}))
        self.assertEqual(len(diff["reboot_notice"](booted, new)), 1)

    def test_firmware_only_change_needs_no_reboot(self):
        kernel = path("linux-6.18.16")
        old = {kernel, path("linux-firmware-20261101")}
        new = {kernel, path("linux-firmware-20261115", "b")}
        self.assertIn("  linux-firmware: 20261101 -> 20261115", diff["report"](old, new))
        self.assertEqual(diff["reboot_notice"](kernel, kernel), [])

    def test_main_appends_reboot_notice(self):
        import contextlib, io, os, tempfile
        with tempfile.TemporaryDirectory() as tmp:
            files = []
            for name, paths in (("old", [path("hello-1")]), ("new", [path("hello-2")])):
                files.append(os.path.join(tmp, name))
                with open(files[-1], "w", encoding="utf-8") as handle:
                    handle.write("\n".join(paths) + "\n")
            for kernels, expected in (
                ((path("linux-zen-7.3.4"), path("linux-zen-7.3.4", "b")), True),
                ((path("linux-6.18.16"), path("linux-6.18.16")), False),
            ):
                out = io.StringIO()
                with contextlib.redirect_stdout(out):
                    self.assertEqual(diff["main"](["closure-diff", *files, *kernels]), 0)
                self.assertEqual("reboot is needed" in out.getvalue(), expected)
            self.assertEqual(diff["main"](["closure-diff", files[0]]), 2)

    def test_rejects_other_output(self):
        with self.assertRaises(ValueError):
            diff["packages"]({"Warning: something"})


unittest.main()
