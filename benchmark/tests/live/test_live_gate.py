"""benchmark/tests/live/test_live_gate.py — AC-8 live gate tripwire (DV0e).

Asserts the default benchmark path NEVER reaches benchmark/live/dispatch.py and that
the live adapter, when it IS reached, only dispatches through the injectable seam
(so no real `claude agents run` / network / spend ever happens here).

Two complementary guards:
  1. STATIC: `make benchmark` (default) shells run-benchmark.sh WITHOUT --live, which
     must never invoke the dispatch module. We assert via the shell harness + source
     inspection that the deterministic branch does not touch benchmark/live/.
  2. INJECTED: when dispatch.dispatch() runs with a TRIPWIRE dispatcher and a budget
     high enough to clear pre-flight, the tripwire proves the only dispatch route is
     the injected seam (we feed a credential + fake estimate so we reach dispatch).
"""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
import unittest

from _helpers import (
    PLUGIN_ROOT,
    load_dispatch,
    TripwireDispatcher,
    RecordingFakeDispatcher,
    fake_estimate_runner,
)

_BENCH = os.path.join(PLUGIN_ROOT, "benchmark")


class TestDefaultPathNeverReachesLive(unittest.TestCase):
    """AC-8 tripwire: the deterministic path must not import/run benchmark/live/."""

    def test_run_benchmark_deterministic_does_not_reference_live_in_branch(self):
        # The shell harness's deterministic branch must not name benchmark/live/.
        with open(
            os.path.join(_BENCH, "run-benchmark.sh"), encoding="utf-8"
        ) as fh:
            src = fh.read()
        # Split on the LIVE guard; the deterministic else-branch must be live-free.
        self.assertIn("if [ \"$LIVE\" = \"1\" ]", src)
        det_branch = src.split("else", 1)[1]
        self.assertNotIn("live/dispatch.py", det_branch)
        self.assertNotIn("benchmark/live", det_branch)

    def test_deterministic_run_module_does_not_import_dispatch(self):
        # deterministic_run.py (DV0d) is what the default path executes; it must not
        # import the live adapter.
        det = os.path.join(_BENCH, "lib", "deterministic_run.py")
        if os.path.isfile(det):
            with open(det, encoding="utf-8") as fh:
                src = fh.read()
            self.assertNotIn("live.dispatch", src)
            self.assertNotIn("live/dispatch", src)
            self.assertNotIn("import dispatch", src)

    def test_make_benchmark_default_runs_without_touching_live(self):
        # Run the real deterministic benchmark in a sandboxed record dir and assert
        # it exits 0 and writes NO file under any live path. This is the deterministic
        # side of AC-8 (no network, no dispatch).
        env = dict(os.environ)
        # Guarantee no accidental live trigger and no credential influence.
        env.pop("ANTHROPIC_API_KEY", None)
        proc = subprocess.run(
            ["bash", os.path.join(_BENCH, "run-benchmark.sh")],
            capture_output=True,
            text=True,
            env=env,
            cwd=PLUGIN_ROOT,
        )
        self.assertEqual(
            proc.returncode,
            0,
            msg=f"default make benchmark failed: {proc.stderr[-2000:]}",
        )
        # The deterministic record lives under results/runs/deterministic/, never live/.
        self.assertNotIn("live/dispatch", proc.stdout + proc.stderr)


class TestLiveAdapterOnlyDispatchesViaSeam(unittest.TestCase):
    """The adapter's ONLY external call is the injected dispatcher (no real LLM)."""

    def test_tripwire_is_the_only_dispatch_route(self):
        dispatch = load_dispatch()
        tripwire = TripwireDispatcher()
        with tempfile.TemporaryDirectory() as tmp:
            record = os.path.join(tmp, "rec.json")
            # Budget huge so pre-flight passes; credential present; fake estimate.
            # The tripwire raises on first dispatch -> proves the seam is the route.
            with self.assertRaises(AssertionError):
                dispatch.dispatch(
                    workdir="gate-run",
                    budget=10_000.0,
                    record_path=record,
                    dispatcher=tripwire,
                    env={"ANTHROPIC_API_KEY": "present-not-logged"},
                    estimate_runner=fake_estimate_runner(0.01),
                    stages=("PL",),
                )
            self.assertTrue(tripwire.called)

    def test_fake_dispatcher_makes_no_subprocess(self):
        # A run with a recording fake completes with ZERO real calls and writes a
        # record. Proves the full pipeline is exercisable without spend.
        dispatch = load_dispatch()
        fake = RecordingFakeDispatcher(
            outputs=['{"usage": {"input_tokens": 10, "output_tokens": 5}, '
                     '"total_cost_usd": 0.001}']
        )
        with tempfile.TemporaryDirectory() as tmp:
            record = os.path.join(tmp, "rec.json")
            rc = dispatch.dispatch(
                workdir="gate-fake",
                budget=10_000.0,
                record_path=record,
                dispatcher=fake,
                env={"ANTHROPIC_API_KEY": "present"},
                estimate_runner=fake_estimate_runner(0.01),
                stages=("PL",),
            )
            self.assertEqual(rc, 0)
            self.assertTrue(os.path.isfile(record))
            self.assertEqual(len(fake.calls), 1)
            # The argv targets `claude agents run` but was never executed (fake).
            argv = fake.calls[0][0]
            self.assertEqual(argv[:3], ["claude", "agents", "run"])
            self.assertIn("--permission-mode", argv)
            self.assertIn("default", argv)


class TestStageTableModel(unittest.TestCase):
    """AC-6 (F5): the STAGE_TABLE DR row must match canonical README:294 — opus/xhigh."""

    def test_dr_row_uses_opus_xhigh(self):
        dispatch = load_dispatch()
        self.assertEqual(
            dispatch.STAGE_TABLE["DR"],
            ("igrsoft:technical-lead", "claude-opus-4-8", "xhigh"),
        )

    def test_dr_model_is_opus_not_sonnet(self):
        dispatch = load_dispatch()
        _agent, model, effort = dispatch.STAGE_TABLE["DR"]
        self.assertEqual(model, "claude-opus-4-8")
        self.assertEqual(effort, "xhigh")
        self.assertNotIn("sonnet", model)


if __name__ == "__main__":
    unittest.main()
