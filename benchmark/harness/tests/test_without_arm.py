"""WITHOUT-arm parity (D1-D7): a single-shot baseline dispatched FIRST, before any
WITH stage, so a later budget breach still leaves a real comparison point on disk.
Covers policy resolution (resolve_arm_mode), frozen argv/prompt (no --agent, no
[1]-[4] preamble), record shape (real tokens/deltas, stage_count 1, no WITHOUT row
in stages[]), the default "skip" placeholder byte shape, preflight/running-tally
budget interaction, DispatchFailure tolerance, and incremental persistence ordering.
All dispatch is fake — zero real `claude -p` calls.
"""

import os
import shutil
import tempfile
import unittest

from benchmarklive import baseline
from benchmarklive import budget as budget_mod
from benchmarklive.dispatch import CAPTURE_JSON, CAPTURE_STREAM_JSON, DispatchFailure, dispatch, run_baseline

import sys as _sys
_sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))  # _helpers under any runner
from _helpers import (
    SequencedFakeDispatcher,
    TripwireDispatcher,
    fake_estimate_runner,
    load_json,
    make_live_sandbox,
    single_object_usage,
    stub_git_sha,
)

_ENV = {"ANTHROPIC_API_KEY": "k"}


class ArmFailsThenSucceeds:
    """First .run() raises DispatchFailure (the arm); every later call succeeds."""

    def __init__(self, stdout=None):
        self.calls = []
        self._stdout = stdout if stdout is not None else single_object_usage()

    def run(self, argv, prompt_text):
        self.calls.append((list(argv), prompt_text))
        if len(self.calls) == 1:
            raise DispatchFailure("arm boom")
        return self._stdout


class ResolveArmModeMatrix(unittest.TestCase):
    def test_explicit_real_wins_on_subset(self):
        self.assertEqual(baseline.resolve_arm_mode("real", ["PL"]), "real")

    def test_explicit_skip_wins_on_full_run(self):
        self.assertEqual(baseline.resolve_arm_mode("skip", None), "skip")

    def test_stages_subset_default_is_skip(self):
        self.assertEqual(baseline.resolve_arm_mode(None, ["PL", "AR"]), baseline.ARM_SKIP)

    def test_full_run_default_is_real(self):
        self.assertEqual(baseline.resolve_arm_mode(None, None), baseline.ARM_REAL)


class BuildWithoutArgvCaptureModes(unittest.TestCase):
    def test_json_capture_has_no_verbose(self):
        argv = baseline.build_without_argv(CAPTURE_JSON)
        self.assertNotIn("--verbose", argv)
        self.assertNotIn("--agent", argv)
        self.assertIn(baseline.WITHOUT_MODEL, argv)
        self.assertIn(baseline.WITHOUT_EFFORT, argv)

    def test_stream_json_capture_adds_verbose(self):
        argv = baseline.build_without_argv(CAPTURE_STREAM_JSON)
        self.assertIn("--verbose", argv)
        self.assertNotIn("--agent", argv)


class RunBaselineGateSkip(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="woa-gate-")
        self.sb = make_live_sandbox(self.tmp)

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_gate_skip_via_preloaded_tally_never_calls_dispatcher(self):
        tally = budget_mod.RunningTally(1.0)
        tally.add(1.0)  # already fully spent
        result = run_baseline(
            self.sb.prompts_dir, TripwireDispatcher(), tally, baseline.ARM_REAL,
            audit_path=os.path.join(self.sb.workdir_path, ".context", "logs", "audit.jsonl"),
            estimate_calc_path="/x", estimate_runner=fake_estimate_runner(0.1))
        self.assertTrue(result.partial)
        self.assertFalse(result.dispatched)

    def test_prompt_sent_verbatim_no_preamble_markers(self):
        recorder = SequencedFakeDispatcher([single_object_usage()])
        run_baseline(
            self.sb.prompts_dir, recorder, budget_mod.RunningTally(100.0), baseline.ARM_REAL,
            audit_path=os.path.join(self.sb.workdir_path, ".context", "logs", "audit.jsonl"),
            estimate_calc_path="/x", estimate_runner=fake_estimate_runner(0.01))
        self.assertEqual(len(recorder.calls), 1)
        argv, prompt_text = recorder.calls[0]
        self.assertNotIn("--agent", argv)
        expected = baseline.load_without_prompt(self.sb.prompts_dir)
        self.assertEqual(prompt_text, expected)
        for marker in ("<<<contract-reminder>>>", "<<<worktask-header>>>",
                       "<<<state-json>>>", "<<<stage-contract>>>"):
            self.assertNotIn(marker, prompt_text)


class DispatchWithArm(unittest.TestCase):
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

    def test_arm_dispatches_first_and_argv_has_no_agent(self):
        fake = SequencedFakeDispatcher([single_object_usage(), single_object_usage()])
        rc = self._dispatch(fake)
        self.assertEqual(rc, 0)
        self.assertEqual(len(fake.calls), 2)
        arm_argv, _ = fake.calls[0]
        pl_argv, _ = fake.calls[1]
        self.assertNotIn("--agent", arm_argv)
        self.assertIn("--agent", pl_argv)

    def test_record_shape_real_tokens_stage_count_and_deltas(self):
        fake = SequencedFakeDispatcher([
            single_object_usage(input_tokens=200, output_tokens=100, cost=0.05),
            single_object_usage(input_tokens=300, output_tokens=150, cost=0.08),
        ])
        rc = self._dispatch(fake)
        self.assertEqual(rc, 0)
        rec = load_json(self.sb.record_path)
        self.assertNotIn("live_partial", rec)  # omit-when-false on a clean real run

        without_p = rec["paths"]["without"]
        self.assertEqual(without_p["tokens"]["in"], 200)
        self.assertEqual(without_p["tokens"]["out"], 100)
        self.assertEqual(without_p["tokens"]["total"], 300)
        self.assertEqual(without_p["cost_usd"], 0.05)
        self.assertEqual(without_p["stage_count"], 1)

        with_p = rec["paths"]["with"]
        self.assertEqual(with_p["tokens"]["total"], 450)
        self.assertEqual(with_p["cost_usd"], 0.08)

        comp = rec["comparison"]
        self.assertEqual(comp["tokens_total"], {"with": 450, "without": 300, "delta": 150})
        self.assertAlmostEqual(comp["cost_usd"]["delta"], 0.03, places=9)

        self.assertEqual(len(rec["stages"]), 1)  # only the WITH stage attribution
        self.assertEqual(rec["stages"][0]["stage"], "PL")
        self.assertNotIn("WITHOUT", [s["stage"] for s in rec["stages"]])

    def test_default_skip_emits_exact_placeholder(self):
        fake = SequencedFakeDispatcher([single_object_usage()])
        rc = dispatch(
            workdir=self.sb.run_id, budget=100.0, record_path=self.sb.record_path,
            benchmark_dir=self.sb.benchmark_dir, dispatcher=fake, env=_ENV,
            estimate_runner=fake_estimate_runner(0.001), stages=["PL"],
            git_sha_runner=stub_git_sha)  # without_arm defaults to "skip"
        self.assertEqual(rc, 0)
        self.assertEqual(len(fake.calls), 1)  # baseline never dispatched
        rec = load_json(self.sb.record_path)
        without_p = rec["paths"]["without"]
        self.assertEqual(without_p, {
            "tokens": {"in": None, "out": None, "total": None,
                      "cache_read": None, "cache_creation": None},
            "cost_usd": None,
            "wall_clock_s": 0.0,
            "loc_produced": 0,
            "test_count": 0,
            "coverage_pct": 0.0,
            "estimate_complexity_score": 0,
            "stage_count": 1,
            "pass_fail": "pass",
            "app_path": None,
        })

    def test_preflight_budget_counts_stages_plus_one_when_real(self):
        # est_cost=0.5, stages=["PL"]: real preflight count = 2 (PL + arm) => 1.0.
        budget_that_covers_only_stages = 0.6
        rc_real = self._dispatch(SequencedFakeDispatcher([single_object_usage()]),
                                 budget_usd=budget_that_covers_only_stages,
                                 without_arm="real", est_cost=0.5)
        self.assertEqual(rc_real, 2)  # declined pre-flight: projection 1.0 > 0.6
        self.assertFalse(os.path.exists(self.sb.record_path))

        rc_skip = self._dispatch(SequencedFakeDispatcher([single_object_usage()]),
                                 budget_usd=budget_that_covers_only_stages,
                                 without_arm="skip", est_cost=0.5)
        self.assertEqual(rc_skip, 0)  # skip: preflight count is just the 1 stage => 0.5 <= 0.6

    def test_breach_after_baseline_keeps_baseline_on_disk_rc4(self):
        # Low preflight estimate (passes gate) but a high REAL arm cost breaches the
        # running tally before the WITH stage can dispatch.
        fake = SequencedFakeDispatcher([single_object_usage(cost=0.9)])
        rc = self._dispatch(fake, budget_usd=1.0, without_arm="real", est_cost=0.4)
        self.assertEqual(rc, 4)
        self.assertEqual(len(fake.calls), 1)  # only the arm dispatched, PL never reached
        rec = load_json(self.sb.record_path)
        self.assertTrue(rec["live_partial"])
        self.assertEqual(rec["paths"]["without"]["cost_usd"], 0.9)  # real baseline kept
        self.assertEqual(rec["paths"]["with"]["pass_fail"], "fail")
        self.assertEqual(rec["paths"]["with"]["stage_count"], 0)
        self.assertEqual(rec.get("stages", []), [])

    def test_arm_dispatch_failure_tolerated_pipeline_still_runs(self):
        fake = ArmFailsThenSucceeds(single_object_usage())
        rc = self._dispatch(fake, without_arm="real")
        self.assertEqual(rc, 4)  # arm failure marks the record partial
        self.assertEqual(len(fake.calls), 2)  # PL still dispatched despite the arm failing
        rec = load_json(self.sb.record_path)
        self.assertEqual(len(rec["stages"]), 1)
        self.assertEqual(rec["stages"][0]["stage"], "PL")
        self.assertIsNone(rec["paths"]["without"]["tokens"]["total"])  # arm never produced usage
        self.assertEqual(rec["paths"]["without"]["pass_fail"], "fail")  # no app materialized

    def test_baseline_persisted_before_stage_one(self):
        # Call 1 = the arm (succeeds); call 2 = PL, the first WITH stage (throws).
        fake = ThrowAtStage(throw_at=2, stdout=single_object_usage(input_tokens=10, output_tokens=5))
        with self.assertRaises(DispatchFailure):
            self._dispatch(fake, stages=["PL", "AR"], without_arm="real")
        rec = load_json(self.sb.record_path)
        self.assertIsNotNone(rec["paths"]["without"]["tokens"]["total"])  # real arm usage on disk
        self.assertEqual(rec.get("stages", []), [])  # PL never completed => never persisted

    def test_degraded_arm_capture_marks_partial_rc4(self):
        fake = SequencedFakeDispatcher(["not json at all", single_object_usage()])
        rc = self._dispatch(fake, without_arm="real")
        self.assertEqual(rc, 4)
        rec = load_json(self.sb.record_path)
        self.assertTrue(rec["live_partial"])
        self.assertIsNone(rec["paths"]["without"]["tokens"]["total"])  # Layer-3: never fabricated


class ThrowAtStage:
    """Local variant of _helpers.ThrowAtStageDispatcher with a distinguishable success
    stdout, so the baseline's real usage is verifiable on the persisted record."""

    def __init__(self, throw_at, stdout):
        self.throw_at = throw_at
        self.count = 0
        self._stdout = stdout

    def run(self, argv, prompt_text):
        self.count += 1
        if self.count == self.throw_at:
            raise DispatchFailure(f"boom at call {self.count}")
        return self._stdout


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
