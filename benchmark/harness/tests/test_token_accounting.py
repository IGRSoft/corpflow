"""U5 per-call token accounting: every prompt execution in BOTH arms persists
input+output tokens as per-stage-prompt rows in the record AND in the raw captures;
skip-mode callers stay byte-stable (no arm tag, no schema growth).
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


class TokenAccounting(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="tok-")
        self.sb = make_live_sandbox(self.tmp)

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_per_call_tokens_in_record_both_arms(self):
        fake = SequencedFakeDispatcher([single_object_usage(input_tokens=11, output_tokens=7)])
        dispatch(
            workdir=self.sb.run_id, budget=100.0, record_path=self.sb.record_path,
            benchmark_dir=self.sb.benchmark_dir, dispatcher=fake, env=_ENV,
            estimate_runner=fake_estimate_runner(0.001), stages=["PL", "AR"],
            git_sha_runner=stub_git_sha, without_arm="real")
        rec = load_json(self.sb.record_path)
        rows = {(s["stage"], s["arm"]): s for s in rec["stages"]}
        self.assertEqual(set(rows), {("PL", "with"), ("AR", "with"), ("PL", "without"), ("AR", "without")})
        for row in rows.values():
            self.assertEqual(row["fresh_in"], 11)
            self.assertEqual(row["out"], 7)

    def test_tokens_persisted_in_captures(self):
        fake = SequencedFakeDispatcher([single_object_usage(input_tokens=42, output_tokens=9)])
        dispatch(
            workdir=self.sb.run_id, budget=100.0, record_path=self.sb.record_path,
            benchmark_dir=self.sb.benchmark_dir, dispatcher=fake, env=_ENV,
            estimate_runner=fake_estimate_runner(0.001), stages=["PL"],
            git_sha_runner=stub_git_sha, without_arm="real")
        captures = os.path.join(self.sb.workdir_path, "captures")
        with open(os.path.join(captures, "with-PL.jsonl"), encoding="utf-8") as f:
            body = f.read()
        self.assertIn('"input_tokens": 42', body)
        self.assertIn('"output_tokens": 9', body)

    def test_skip_mode_rows_have_no_arm_tag(self):
        fake = SequencedFakeDispatcher([single_object_usage(input_tokens=5, output_tokens=3)])
        dispatch(
            workdir=self.sb.run_id, budget=100.0, record_path=self.sb.record_path,
            benchmark_dir=self.sb.benchmark_dir, dispatcher=fake, env=_ENV,
            estimate_runner=fake_estimate_runner(0.001), stages=["PL"],
            git_sha_runner=stub_git_sha)  # skip
        rec = load_json(self.sb.record_path)
        self.assertEqual(len(rec["stages"]), 1)
        self.assertNotIn("arm", rec["stages"][0])
        self.assertEqual(rec["stages"][0]["fresh_in"], 5)
        self.assertEqual(rec["stages"][0]["out"], 3)


if __name__ == "__main__":
    unittest.main()
