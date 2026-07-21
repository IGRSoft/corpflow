"""Budget enforcement parity (R2; port of BudgetEnforcementTests): pre-flight decline
rc=2 dispatching nothing, module throws over budget, running-tally abort before the
breaching stage (rc=4, partial written first, live_partial, pass_fail=fail,
stage_count=2), can_afford, nil-cost adds nothing, Layer-3 degradation. All fakes.
"""

import json
import os
import shutil
import tempfile
import unittest

from benchmarklive import budget
from benchmarklive.dispatch import dispatch

import sys as _sys
_sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))  # _helpers under any runner
from _helpers import (
    RecordingFakeDispatcher,
    TripwireDispatcher,
    fake_estimate_runner,
    load_json,
    make_live_sandbox,
    single_object_usage,
    stub_git_sha,
)

_ENV = {"ANTHROPIC_API_KEY": "test-key"}
_STAGES = ["PL", "AR", "TL"]


class BudgetModule(unittest.TestCase):
    def test_assert_preflight_throws_over_budget(self):
        with self.assertRaises(budget.BudgetExceeded):
            budget.assert_preflight_within_budget(0.5, 3, "/x", runner=fake_estimate_runner(1.0))

    def test_assert_preflight_allows_within_budget(self):
        proj = budget.assert_preflight_within_budget(10.0, 3, "/x", runner=fake_estimate_runner(1.0))
        self.assertEqual(proj, 3.0)

    def test_can_afford_logic(self):
        t = budget.RunningTally(3.0)
        t.add(2.0)
        self.assertTrue(t.can_afford(1.0))
        self.assertFalse(t.can_afford(1.5))

    def test_nil_cost_adds_nothing(self):
        t = budget.RunningTally(3.0)
        t.add(None)
        self.assertEqual(t.spent_usd, 0.0)


class DispatchBudgetGates(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="bud-")
        self.sb = make_live_sandbox(self.tmp)

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _dispatch(self, dispatcher, budget_usd, est_cost):
        return dispatch(
            workdir=self.sb.run_id, budget=budget_usd, record_path=self.sb.record_path,
            benchmark_dir=self.sb.benchmark_dir, dispatcher=dispatcher, env=_ENV,
            estimate_runner=fake_estimate_runner(est_cost), stages=list(_STAGES),
            git_sha_runner=stub_git_sha)

    def test_preflight_decline_rc2_dispatches_nothing(self):
        trip = TripwireDispatcher()
        rc = self._dispatch(trip, budget_usd=0.5, est_cost=1.0)  # projection 3.0 > 0.5
        self.assertEqual(rc, 2)
        self.assertFalse(os.path.exists(self.sb.record_path))  # dispatched nothing, no record

    def test_running_tally_abort_writes_partial_rc4(self):
        fake = RecordingFakeDispatcher(single_object_usage(cost=1.4))
        rc = self._dispatch(fake, budget_usd=3.0, est_cost=1.0)  # real 1.4/stage breaches at 3rd
        self.assertEqual(rc, 4)
        self.assertEqual(len(fake.calls), 2)  # 2 dispatched, aborted before 3rd
        rec = load_json(self.sb.record_path)
        self.assertTrue(rec["live_partial"])
        self.assertEqual(rec["paths"]["with"]["pass_fail"], "fail")
        self.assertEqual(rec["paths"]["with"]["stage_count"], 2)

    def test_layer3_degradation_partial_rc4_null_tokens(self):
        fake = RecordingFakeDispatcher(stdout="not json at all")  # no usage → Layer 3
        rc = self._dispatch(fake, budget_usd=100.0, est_cost=0.001)
        self.assertEqual(rc, 4)  # degradation marks partial
        rec = load_json(self.sb.record_path)
        self.assertTrue(rec["live_partial"])
        self.assertIsNone(rec["paths"]["with"]["tokens"]["total"])


if __name__ == "__main__":
    unittest.main()
