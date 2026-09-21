"""Paired-arm semantics (U3/U4): the WITHOUT arm now runs the SAME ordered stage
sequence bare (no --agent), the WITH arm runs it agent-bound; ``skip`` keeps the
WITHOUT placeholder byte-stable. Covers policy resolution, the exact skip placeholder
shape, real-mode record aggregation + deltas, preflight (stages*2 when real),
post-baseline breach persistence, and degraded-capture partial marking. All dispatch
is fake — zero real `claude -p` calls.
"""

import os
import shutil
import tempfile
import unittest

from benchmarklive import baseline
from benchmarklive import budget as budget_mod
from benchmarklive.dispatch import DispatchFailure, dispatch

import sys as _sys
_sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))  # _helpers under any runner
from _helpers import (
    SequencedFakeDispatcher,
    ThrowAtStageDispatcher,
    fake_estimate_runner,
    load_json,
    make_live_sandbox,
    single_object_usage,
    stub_git_sha,
)

_ENV = {"ANTHROPIC_API_KEY": "k"}


class ResolveArmModeMatrix(unittest.TestCase):
    def test_explicit_real_wins_on_subset(self):
        self.assertEqual(baseline.resolve_arm_mode("real", ["PL"]), "real")

    def test_explicit_skip_wins_on_full_run(self):
        self.assertEqual(baseline.resolve_arm_mode("skip", None), "skip")

    def test_stages_subset_default_is_skip(self):
        self.assertEqual(baseline.resolve_arm_mode(None, ["PL", "AR"]), baseline.ARM_SKIP)

    def test_full_run_default_is_real(self):
        self.assertEqual(baseline.resolve_arm_mode(None, None), baseline.ARM_REAL)


class StagesSubsetNormalisation(unittest.TestCase):
    """The full pipeline spelled out is a FULL run, however it was spelled."""

    FULL = budget_mod.PIPELINE_STAGES

    def test_full_pipeline_normalises_to_none(self):
        self.assertIsNone(baseline.stages_subset(list(self.FULL), self.FULL))

    def test_order_and_duplicates_do_not_make_it_a_subset(self):
        shuffled = list(reversed(self.FULL)) + ["PL", "PL"]
        self.assertIsNone(baseline.stages_subset(shuffled, self.FULL))

    def test_genuine_subset_is_returned_verbatim(self):
        self.assertEqual(baseline.stages_subset(["PL", "AR"], self.FULL), ["PL", "AR"])

    def test_absent_stages_stay_absent(self):
        self.assertIsNone(baseline.stages_subset(None, self.FULL))

    def test_full_pipeline_via_stages_still_pairs_both_arms(self):
        sel = baseline.resolve_arm_selection(
            None, None, baseline.stages_subset(list(self.FULL), self.FULL))
        self.assertEqual(sel.dispatch, ("without", "with"))


class PairedDispatch(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="woa-dispatch-")
        self.sb = make_live_sandbox(self.tmp)

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _dispatch(self, dispatcher, budget_usd=100.0, stages=None, without_arm="real", est_cost=0.001):
        return dispatch(
            workdir=self.sb.run_id, budget=budget_usd, record_path=self.sb.record_path,
            benchmark_dir=self.sb.benchmark_dir, dispatcher=dispatcher, env=_ENV,
            estimate_runner=fake_estimate_runner(est_cost), stages=stages or ["PL"],
            git_sha_runner=stub_git_sha, without_arm=without_arm)

    def test_without_arm_runs_first_and_bare(self):
        fake = SequencedFakeDispatcher([single_object_usage(), single_object_usage()])
        rc = self._dispatch(fake)
        self.assertEqual(rc, 0)
        self.assertEqual(len(fake.calls), 2)  # WITHOUT PL then WITH PL
        without_argv, _ = fake.calls[0]
        with_argv, _ = fake.calls[1]
        self.assertNotIn("--agent", without_argv)
        self.assertIn("--agent", with_argv)

    def test_record_shape_real_tokens_and_deltas(self):
        fake = SequencedFakeDispatcher([
            single_object_usage(input_tokens=200, output_tokens=100, cost=0.05),  # WITHOUT
            single_object_usage(input_tokens=300, output_tokens=150, cost=0.08),  # WITH
        ])
        rc = self._dispatch(fake)
        self.assertEqual(rc, 0)
        rec = load_json(self.sb.record_path)
        self.assertNotIn("live_partial", rec)

        without_p = rec["paths"]["without"]
        self.assertEqual(without_p["tokens"]["in"], 200)
        self.assertEqual(without_p["tokens"]["total"], 300)
        self.assertEqual(without_p["cost_usd"], 0.05)
        self.assertEqual(without_p["stage_count"], 1)

        with_p = rec["paths"]["with"]
        self.assertEqual(with_p["tokens"]["total"], 450)
        self.assertEqual(with_p["cost_usd"], 0.08)

        comp = rec["comparison"]
        self.assertEqual(comp["tokens_total"], {"with": 450, "without": 300, "delta": 150})
        self.assertAlmostEqual(comp["cost_usd"]["delta"], 0.03, places=9)

        arms = {(s["stage"], s.get("arm")) for s in rec["stages"]}
        self.assertEqual(arms, {("PL", "with"), ("PL", "without")})

    def test_default_skip_emits_exact_placeholder(self):
        fake = SequencedFakeDispatcher([single_object_usage()])
        rc = dispatch(
            workdir=self.sb.run_id, budget=100.0, record_path=self.sb.record_path,
            benchmark_dir=self.sb.benchmark_dir, dispatcher=fake, env=_ENV,
            estimate_runner=fake_estimate_runner(0.001), stages=["PL"],
            git_sha_runner=stub_git_sha)  # without_arm defaults to "skip"
        self.assertEqual(rc, 0)
        self.assertEqual(len(fake.calls), 1)  # only the WITH arm runs
        rec = load_json(self.sb.record_path)
        self.assertEqual(rec["paths"]["without"], {
            "tokens": {"in": None, "out": None, "total": None,
                       "cache_read": None, "cache_creation": None},
            "cost_usd": None,
            "wall_clock_s": 0.0,
            "loc_produced": 0,
            "test_count": 0,
            # Unmeasured, not measured-zero: the arm never ran, so 0.0 would claim
            # a coverage run happened.
            "coverage_pct": None,
            "estimate_complexity_score": 0,
            "stage_count": 1,
            "pass_fail": "pass",
            "app_path": None,
        })
        # Skip mode leaves stage rows untagged (byte-stable): no "arm" key.
        self.assertTrue(all("arm" not in s for s in rec["stages"]))

    def test_policy_fallback_reads_the_dispatched_stages_not_none(self):
        # without_arm=None is the only way into the subset→skip policy from inside
        # dispatch(); the fallback must consult its own `stages`, not a hardcoded None.
        fake = SequencedFakeDispatcher([single_object_usage()])
        rc = self._dispatch(fake, stages=["PL"], without_arm=None)
        self.assertEqual(rc, 0)
        self.assertEqual(len(fake.calls), 1)  # subset ⇒ WITH alone

    def test_policy_fallback_pairs_when_the_stage_list_is_the_whole_pipeline(self):
        for arm in ("with", "without"):
            d = os.path.join(self.sb.workdir_path, arm, "Sources")
            os.makedirs(d, exist_ok=True)
            with open(os.path.join(d, "App.swift"), "w", encoding="utf-8") as f:
                f.write("let x = 1\n")  # clears the DV gate so every stage dispatches
        fake = SequencedFakeDispatcher([single_object_usage()])
        rc = self._dispatch(fake, stages=list(budget_mod.PIPELINE_STAGES), without_arm=None)
        self.assertEqual(rc, 0)
        self.assertEqual(len(fake.calls), 2 * len(budget_mod.PIPELINE_STAGES))

    def test_paired_coverage_is_absent_not_zero(self):
        # Live coverage is never measured: the paired path emits None (absent) for BOTH arms
        # so a renderer can tell it apart from a real 0.0. Skip mode keeps the 0.0 placeholder.
        fake = SequencedFakeDispatcher([single_object_usage(), single_object_usage()])
        rc = self._dispatch(fake)
        self.assertEqual(rc, 0)
        rec = load_json(self.sb.record_path)
        self.assertIsNone(rec["paths"]["with"]["coverage_pct"])
        self.assertIsNone(rec["paths"]["without"]["coverage_pct"])
        self.assertIsNone(rec["comparison"]["coverage_pct"]["with"])
        self.assertIsNone(rec["comparison"]["coverage_pct"]["delta"])

    def test_preflight_counts_both_arms_when_real(self):
        # est=0.5, stages=["PL"]: real preflight count = 2 => 1.0 > 0.6 declines.
        rc_real = self._dispatch(SequencedFakeDispatcher([single_object_usage()]),
                                 budget_usd=0.6, without_arm="real", est_cost=0.5)
        self.assertEqual(rc_real, 2)
        self.assertFalse(os.path.exists(self.sb.record_path))

        rc_skip = self._dispatch(SequencedFakeDispatcher([single_object_usage()]),
                                 budget_usd=0.6, without_arm="skip", est_cost=0.5)
        self.assertEqual(rc_skip, 0)  # skip count is 1 => 0.5 <= 0.6

    def test_breach_after_without_keeps_it_on_disk_rc4(self):
        # Per-arm budget 1.0. WITHOUT runs both stages cheaply; WITH's first stage
        # costs 0.9, so its own reserve gates its second.
        fake = SequencedFakeDispatcher([
            single_object_usage(cost=0.3), single_object_usage(cost=0.3),
            single_object_usage(cost=0.9),
        ])
        rc = self._dispatch(fake, budget_usd=2.0, stages=["PL", "AR"],
                            without_arm="real", est_cost=0.4)
        self.assertEqual(rc, 4)
        self.assertEqual(len(fake.calls), 3)  # WITHOUT x2, WITH x1 then gated
        rec = load_json(self.sb.record_path)
        self.assertTrue(rec["live_partial"])
        self.assertEqual(rec["paths"]["without"]["stage_count"], 2)
        self.assertEqual(rec["paths"]["without"]["cost_usd"], 0.6)
        self.assertEqual(rec["paths"]["with"]["pass_fail"], "fail")
        self.assertEqual(rec["paths"]["with"]["stage_count"], 1)

    def test_throw_mid_without_arm_keeps_completed_stages(self):
        # A breach returns an ArmResult, but a throw does not; without incremental
        # persistence the WITHOUT arm's finished stages leave no record at all.
        with self.assertRaises(DispatchFailure):
            self._dispatch(ThrowAtStageDispatcher(throw_at=3), stages=["PL", "AR", "TL"],
                           without_arm="real")
        rec = load_json(self.sb.record_path)
        self.assertTrue(rec["live_partial"])
        self.assertEqual(rec["paths"]["without"]["stage_count"], 2)
        self.assertEqual([s["stage"] for s in rec["stages"]], ["PL", "AR"])

    def test_arm_budgets_are_independent(self):
        # A shared purse would let WITHOUT's 0.9 gate WITH out entirely; halves of
        # a 2.0 budget leave each arm its own 1.0 and both arms complete.
        fake = SequencedFakeDispatcher([
            single_object_usage(cost=0.9), single_object_usage(cost=0.9),
        ])
        rc = self._dispatch(fake, budget_usd=2.0, without_arm="real", est_cost=0.4)
        self.assertEqual(rc, 0)
        self.assertEqual(len(fake.calls), 2)
        rec = load_json(self.sb.record_path)
        self.assertEqual(rec["paths"]["with"]["stage_count"], 1)
        self.assertEqual(rec["paths"]["without"]["stage_count"], 1)

    def test_degraded_without_capture_marks_partial_rc4(self):
        fake = SequencedFakeDispatcher(["not json at all", single_object_usage()])
        rc = self._dispatch(fake, without_arm="real")
        self.assertEqual(rc, 4)
        rec = load_json(self.sb.record_path)
        self.assertTrue(rec["live_partial"])
        self.assertIsNone(rec["paths"]["without"]["tokens"]["total"])  # never fabricated


class SeamTextWiring(unittest.TestCase):
    def test_without_arm_flag_wired_in_bench_live_and_run_benchmark(self):
        harness = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        bench_live = os.path.join(harness, "bin", "bench-live")
        run_benchmark = os.path.join(os.path.dirname(harness), "run-benchmark.sh")
        with open(bench_live, encoding="utf-8") as f:
            self.assertIn("--without-arm", f.read())
        with open(run_benchmark, encoding="utf-8") as f:
            self.assertIn("--without-arm", f.read())


if __name__ == "__main__":
    unittest.main()
