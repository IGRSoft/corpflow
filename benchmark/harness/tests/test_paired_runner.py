"""U4 paired ±agent runner: both arms execute the SAME ordered stage sequence over
byte-identical prompt inputs (WITH agent-bound, WITHOUT bare); a full pipeline run
yields 10 WITH + 10 WITHOUT persisted captures.
"""

import os
import shutil
import tempfile
import unittest

from benchmarklive import budget as budget_mod
from benchmarklive.dispatch import dispatch

import sys as _sys
_sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _helpers import SequencedFakeDispatcher, fake_estimate_runner, make_live_sandbox, single_object_usage, stub_git_sha

_ENV = {"ANTHROPIC_API_KEY": "k"}


class PairedRunner(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="pair-")
        self.sb = make_live_sandbox(self.tmp)

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _seed_swift_both_arms(self):
        for arm in ("with", "without"):
            d = os.path.join(self.sb.workdir_path, arm, "Sources")
            os.makedirs(d, exist_ok=True)
            with open(os.path.join(d, "App.swift"), "w", encoding="utf-8") as f:
                f.write("let x = 1\n")

    def test_both_arms_consume_identical_prompt_inputs(self):
        fake = SequencedFakeDispatcher([single_object_usage()])
        dispatch(
            workdir=self.sb.run_id, budget=100.0, record_path=self.sb.record_path,
            benchmark_dir=self.sb.benchmark_dir, dispatcher=fake, env=_ENV,
            estimate_runner=fake_estimate_runner(0.001), stages=["PL", "AR"],
            git_sha_runner=stub_git_sha, without_arm="real")
        # calls: WITHOUT-PL, WITHOUT-AR, WITH-PL, WITH-AR
        self.assertEqual(len(fake.calls), 4)
        without_pl, without_ar = fake.calls[0][1], fake.calls[1][1]
        with_pl, with_ar = fake.calls[2][1], fake.calls[3][1]
        self.assertEqual(without_pl, with_pl)  # identical bytes per stage
        self.assertEqual(without_ar, with_ar)
        self.assertNotIn("--agent", fake.calls[0][0])  # WITHOUT bare
        self.assertIn("--agent", fake.calls[2][0])      # WITH bound

    def test_full_pipeline_yields_ten_plus_ten_captures(self):
        self._seed_swift_both_arms()
        fake = SequencedFakeDispatcher([single_object_usage()])
        rc = dispatch(
            workdir=self.sb.run_id, budget=1000.0, record_path=self.sb.record_path,
            benchmark_dir=self.sb.benchmark_dir, dispatcher=fake, env=_ENV,
            estimate_runner=fake_estimate_runner(0.001),
            stages=budget_mod.PIPELINE_STAGES, git_sha_runner=stub_git_sha, without_arm="real")
        self.assertEqual(rc, 0)
        captures = os.path.join(self.sb.workdir_path, "captures")
        files = sorted(os.listdir(captures))
        self.assertEqual(len(files), 20)
        with_files = [f for f in files if f.startswith("with-")]
        without_files = [f for f in files if f.startswith("without-")]
        self.assertEqual(len(with_files), 10)
        self.assertEqual(len(without_files), 10)


if __name__ == "__main__":
    unittest.main()
