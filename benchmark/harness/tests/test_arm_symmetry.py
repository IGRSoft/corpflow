"""U3 symmetric arm folders: each arm's LOC/file measurement is scoped strictly to
its own with/ or without/ folder — with-arm Bar.swift and without-arm Foo.swift are
attributed to the correct arm only, never cross-counted.
"""

import os
import shutil
import tempfile
import unittest

from benchmarklive.dispatch import dispatch

import sys as _sys
_sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _helpers import SequencedFakeDispatcher, fake_estimate_runner, load_json, make_live_sandbox, single_object_usage, stub_git_sha

_ENV = {"ANTHROPIC_API_KEY": "k"}


def _seed_arm(arm_dir: str, swift_name: str, n_lines: int) -> None:
    os.makedirs(arm_dir, exist_ok=True)
    with open(os.path.join(arm_dir, "Package.swift"), "w", encoding="utf-8") as f:
        f.write("garbage-manifest\n")  # resolves fast to a failing `swift test`
    with open(os.path.join(arm_dir, swift_name), "w", encoding="utf-8") as f:
        f.write("\n".join(f"let v{i} = {i}" for i in range(n_lines)) + "\n")


class ArmSymmetry(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="sym-")
        self.sb = make_live_sandbox(self.tmp)

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_each_arm_measured_in_its_own_folder(self):
        _seed_arm(os.path.join(self.sb.workdir_path, "with"), "Bar.swift", n_lines=3)
        _seed_arm(os.path.join(self.sb.workdir_path, "without"), "Foo.swift", n_lines=7)
        fake = SequencedFakeDispatcher([single_object_usage(cost=0.01)])
        dispatch(
            workdir=self.sb.run_id, budget=100.0, record_path=self.sb.record_path,
            benchmark_dir=self.sb.benchmark_dir, dispatcher=fake, env=_ENV,
            estimate_runner=fake_estimate_runner(0.001), stages=["PL"],
            git_sha_runner=stub_git_sha, without_arm="real")
        rec = load_json(self.sb.record_path)
        # with = Package.swift(1) + Bar.swift(3) = 4; without = Package(1) + Foo(7) = 8.
        self.assertEqual(rec["paths"]["with"]["loc_produced"], 4)
        self.assertEqual(rec["paths"]["without"]["loc_produced"], 8)
        # app_path points at each arm's own folder.
        self.assertTrue(rec["paths"]["with"]["app_path"].endswith(os.path.join(self.sb.run_id, "with")))
        self.assertTrue(rec["paths"]["without"]["app_path"].endswith(os.path.join(self.sb.run_id, "without")))


if __name__ == "__main__":
    unittest.main()
