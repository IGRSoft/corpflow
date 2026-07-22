"""Incremental persistence parity (OI-2; port of IncrementalPersistenceTests):
throw at stage N → stages 1..N-1 on disk with live_partial=true; clean run flips
live_partial off with all stages; the first stage is persisted before the second
dispatch. git_sha stubbed (avoids subprocess).
"""

import json
import os
import shutil
import tempfile
import unittest

from benchmarklive.dispatch import DispatchFailure, dispatch

import sys as _sys
_sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))  # _helpers under any runner
from _helpers import (
    RecordingFakeDispatcher,
    ThrowAtStageDispatcher,
    fake_estimate_runner,
    load_json,
    make_live_sandbox,
    single_object_usage,
    stub_git_sha,
)

_ENV = {"ANTHROPIC_API_KEY": "k"}
_STAGES = ["PL", "AR", "TL"]


class IncrementalPersistence(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="inc-")
        self.sb = make_live_sandbox(self.tmp)

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _dispatch(self, dispatcher):
        return dispatch(
            workdir=self.sb.run_id, budget=100.0, record_path=self.sb.record_path,
            benchmark_dir=self.sb.benchmark_dir, dispatcher=dispatcher, env=_ENV,
            estimate_runner=fake_estimate_runner(0.001), stages=list(_STAGES),
            git_sha_runner=stub_git_sha)

    def test_throw_at_stage_three_persists_first_two(self):
        with self.assertRaises(DispatchFailure):
            self._dispatch(ThrowAtStageDispatcher(throw_at=3))
        rec = load_json(self.sb.record_path)
        self.assertTrue(rec["live_partial"])
        self.assertEqual(rec["paths"]["with"]["stage_count"], 2)
        self.assertEqual(len(rec["stages"]), 2)
        self.assertEqual([s["stage"] for s in rec["stages"]], ["PL", "AR"])

    def test_first_stage_persisted_before_second_dispatch(self):
        with self.assertRaises(DispatchFailure):
            self._dispatch(ThrowAtStageDispatcher(throw_at=2))
        rec = load_json(self.sb.record_path)  # exists → stage 1 flushed before stage 2
        self.assertEqual(rec["paths"]["with"]["stage_count"], 1)
        self.assertEqual(len(rec["stages"]), 1)

    def test_clean_run_flips_partial_off(self):
        rc = self._dispatch(RecordingFakeDispatcher(single_object_usage()))
        self.assertEqual(rc, 0)
        rec = load_json(self.sb.record_path)
        self.assertNotIn("live_partial", rec)  # omit-when-false
        self.assertEqual(len(rec["stages"]), 3)
        self.assertEqual(rec["paths"]["with"]["pass_fail"], "pass")


if __name__ == "__main__":
    unittest.main()
