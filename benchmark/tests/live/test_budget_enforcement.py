"""benchmark/tests/live/test_budget_enforcement.py — AC-8 budget gates (DV0e).

Two gates, both proven WITHOUT any real LLM call:

  (a) PRE-FLIGHT: a projection exceeding --budget declines before ANY dispatch. The
      tripwire dispatcher proves nothing was dispatched.
  (b) RUNNING-TALLY: a stub per-stage cost sequence that breaches mid-run aborts
      BEFORE the breaching dispatch and writes a partial record (pass_fail="fail",
      live_partial=True).

All dispatchers/estimators are injected fakes — no network, no spend.
"""

from __future__ import annotations

import json
import os
import tempfile
import unittest

from _helpers import (
    load_dispatch,
    load_budget,
    TripwireDispatcher,
    RecordingFakeDispatcher,
    fake_estimate_runner,
)


class TestPreflightGate(unittest.TestCase):
    """Gate (a): projection > budget -> decline, dispatch nothing."""

    def test_preflight_declines_and_dispatches_nothing(self):
        dispatch = load_dispatch()
        tripwire = TripwireDispatcher()
        with tempfile.TemporaryDirectory() as tmp:
            record = os.path.join(tmp, "rec.json")
            # 10 stages * $1.00/stage = $10 projection vs $1 budget -> decline.
            rc = dispatch.dispatch(
                workdir="budget-preflight",
                budget=1.00,
                record_path=record,
                dispatcher=tripwire,
                env={"ANTHROPIC_API_KEY": "present"},
                estimate_runner=fake_estimate_runner(1.00),
            )
            self.assertNotEqual(rc, 0)            # non-zero exit
            self.assertFalse(tripwire.called)     # dispatched nothing
            self.assertFalse(os.path.isfile(record))  # no record written on decline

    def test_budget_module_raises_on_projection_over_budget(self):
        budget = load_budget()
        with self.assertRaises(budget.BudgetExceeded):
            budget.assert_preflight_within_budget(
                budget=0.50,
                stage_count=10,
                estimate_calc_path="/unused",
                runner=fake_estimate_runner(1.00),
            )

    def test_budget_module_allows_projection_within_budget(self):
        budget = load_budget()
        projection = budget.assert_preflight_within_budget(
            budget=100.0,
            stage_count=10,
            estimate_calc_path="/unused",
            runner=fake_estimate_runner(1.00),
        )
        self.assertAlmostEqual(projection, 10.0, places=6)


class TestRunningTallyGate(unittest.TestCase):
    """Gate (b): abort before the breaching stage; write a partial record."""

    def test_running_tally_aborts_before_breaching_stage(self):
        dispatch = load_dispatch()
        # Pre-flight uses the per-stage ESTIMATE ($0.20): 3 * 0.20 = 0.60 <= 1.00
        # budget, so pre-flight passes and we reach the running-tally gate. The REAL
        # measured cost per stage (Layer-1 stdout) is HIGHER at $0.45. Running tally
        # (can_afford uses the $0.20 estimate):
        #   stage 1: spent 0  -> dispatch -> real spent 0.45
        #   stage 2: 0.45+0.20=0.65 <= 1.00 -> dispatch -> real spent 0.90
        #   stage 3: 0.90+0.20=1.10 >  1.00 -> ABORT before dispatching stage 3.
        stage_stdout = json.dumps(
            {"usage": {"input_tokens": 100, "output_tokens": 50},
             "total_cost_usd": 0.45}
        )
        fake = RecordingFakeDispatcher(outputs=[stage_stdout, stage_stdout, stage_stdout])
        with tempfile.TemporaryDirectory() as tmp:
            record = os.path.join(tmp, "rec.json")
            rc = dispatch.dispatch(
                workdir="budget-tally",
                budget=1.00,
                record_path=record,
                dispatcher=fake,
                env={"ANTHROPIC_API_KEY": "present"},
                estimate_runner=fake_estimate_runner(0.20),
                stages=("PL", "AR", "TL"),
            )
            # Only 2 of 3 stages dispatched (aborted before the breaching 3rd).
            self.assertEqual(len(fake.calls), 2)
            self.assertNotEqual(rc, 0)  # partial run -> non-zero
            # Partial record written.
            self.assertTrue(os.path.isfile(record))
            with open(record, encoding="utf-8") as fh:
                data = json.loads(fh.read())
            self.assertTrue(data.get("live_partial"))
            self.assertEqual(data["mode"], "live")
            self.assertEqual(data["paths"]["with"]["pass_fail"], "fail")
            self.assertEqual(data["paths"]["with"]["stage_count"], 2)

    def test_running_tally_class_can_afford_logic(self):
        budget = load_budget()
        tally = budget.RunningTally(1.00)
        self.assertTrue(tally.can_afford(0.40))
        tally.add(0.40)
        self.assertTrue(tally.can_afford(0.40))   # 0.80 <= 1.00
        tally.add(0.40)
        self.assertFalse(tally.can_afford(0.40))  # 1.20 > 1.00

    def test_running_tally_never_fabricates_on_none_cost(self):
        budget = load_budget()
        tally = budget.RunningTally(1.00)
        tally.add(None)            # unmeasured stage contributes nothing
        self.assertEqual(tally.spent_usd, 0.0)


if __name__ == "__main__":
    unittest.main()
