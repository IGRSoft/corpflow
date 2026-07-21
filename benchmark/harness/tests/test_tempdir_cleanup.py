"""Temp-dir cleanup parity (port of TempDirCleanupTests, OI-1/R3):
with_ephemeral_workdir removes its dir on success AND on exception; run_app_tests
sweeps <app_dir>/.build on the fail path without deleting the caller's app dir;
cleanup never touches external dirs.
"""

import os
import shutil
import tempfile
import unittest

from benchmarkkit import genlib
from benchmarkkit.generators import with_ephemeral_workdir


class TempDirCleanup(unittest.TestCase):
    def test_ephemeral_removed_on_success(self):
        captured = {}
        with with_ephemeral_workdir() as wd:
            captured["wd"] = wd
            self.assertTrue(os.path.isdir(wd))
        self.assertFalse(os.path.exists(captured["wd"]))

    def test_ephemeral_removed_on_exception(self):
        captured = {}

        class Boom(Exception):
            pass

        with self.assertRaises(Boom):
            with with_ephemeral_workdir() as wd:
                captured["wd"] = wd
                raise Boom()
        self.assertFalse(os.path.exists(captured["wd"]))

    def test_run_app_tests_sweeps_build_on_fail_without_deleting_appdir(self):
        parent = tempfile.mkdtemp(prefix="ttc-")
        try:
            app_dir = os.path.join(parent, "app")
            os.makedirs(os.path.join(app_dir, ".build"))
            # A source-only dir with no Package.swift makes `swift test` fail fast.
            with open(os.path.join(app_dir, "note.swift"), "w") as f:
                f.write("// no package\n")
            external = os.path.join(parent, "external.txt")
            with open(external, "w") as f:
                f.write("keep me")

            _, pass_fail = genlib.run_app_tests(app_dir)
            self.assertEqual(pass_fail, "fail")
            self.assertFalse(os.path.exists(os.path.join(app_dir, ".build")))  # swept
            self.assertTrue(os.path.isdir(app_dir))          # caller's app survives
            self.assertTrue(os.path.exists(external))        # external untouched (R3)
        finally:
            shutil.rmtree(parent, ignore_errors=True)


if __name__ == "__main__":
    unittest.main()
