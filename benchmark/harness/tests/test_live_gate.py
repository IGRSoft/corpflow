"""Live-gate parity (port of LiveGateTests): the fake dispatcher is the only route
(no real subprocess); dispatch-failure carries the child's stderr, never the prompt;
capture-mode variants (--verbose only on stream-json); STAGE_TABLE DR rows; and, once
run-benchmark.sh is rewired, its deterministic branch stays live-free.
"""

import os
import unittest

from benchmarklive.dispatch import (
    STAGE_TABLE,
    CAPTURE_JSON,
    CAPTURE_STREAM_JSON,
    DispatchFailure,
    SubprocessDispatcher,
    build_stage_argv,
)

_HARNESS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_RUN_BENCHMARK = os.path.join(os.path.dirname(_HARNESS), "run-benchmark.sh")


class LiveGate(unittest.TestCase):
    def test_capture_mode_variants(self):
        self.assertNotIn("--verbose", build_stage_argv("PL", CAPTURE_JSON))
        self.assertIn("--verbose", build_stage_argv("PL", CAPTURE_STREAM_JSON))
        self.assertEqual(build_stage_argv("PL")[:2], ["claude", "-p"])

    def test_dispatch_failure_carries_stderr_not_prompt(self):
        disp = SubprocessDispatcher(workdir=None)
        with self.assertRaises(DispatchFailure) as ctx:
            disp.run(["sh", "-c", "echo ERRTEXT >&2; exit 1"], "SECRET_PROMPT_BODY")
        msg = str(ctx.exception)
        self.assertIn("ERRTEXT", msg)
        self.assertNotIn("SECRET_PROMPT_BODY", msg)

    def test_stage_table_dr_row(self):
        agent, model, effort = STAGE_TABLE["DR"]
        self.assertEqual((_family(model), effort), ("opus", "xhigh"))

    def test_run_benchmark_deterministic_branch_is_live_free(self):
        if not os.path.exists(_RUN_BENCHMARK):
            self.skipTest("run-benchmark.sh not present")
        text = open(_RUN_BENCHMARK, encoding="utf-8").read()
        if "bench-deterministic" not in text:
            self.skipTest("run-benchmark.sh not yet rewired to the Python entrypoints (Phase 6)")
        # After rewire: the deterministic entrypoint line must not reference bench-live.
        for line in text.splitlines():
            if "bench-deterministic" in line:
                self.assertNotIn("bench-live", line)


def _family(model_id: str) -> str:
    return model_id.split("-")[1]


if __name__ == "__main__":
    unittest.main()
