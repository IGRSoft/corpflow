"""A5 DV file-landing gate: dv_produced_swift is True only for *.swift outside
{.build,.swiftpm,.context}; when the DV stage lands no Swift the arm is marked
partial and its remaining stages are skipped (already-flushed stages survive).
"""

import os
import shutil
import tempfile
import unittest

from benchmarklive import budget as budget_mod
from benchmarklive.dispatch import ArmSpec, dv_produced_swift, run_arm

import sys as _sys
_sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _helpers import SequencedFakeDispatcher, fake_estimate_runner, single_object_usage


class DvProducedSwift(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="dvg-")

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_swift_in_source_counts(self):
        os.makedirs(os.path.join(self.tmp, "Sources"))
        with open(os.path.join(self.tmp, "Sources", "App.swift"), "w") as f:
            f.write("let x = 1\n")
        self.assertTrue(dv_produced_swift(self.tmp))

    def test_swift_only_in_ignored_dirs_does_not_count(self):
        for d in (".build", ".context", ".swiftpm"):
            os.makedirs(os.path.join(self.tmp, d))
            with open(os.path.join(self.tmp, d, "Gen.swift"), "w") as f:
                f.write("x\n")
        self.assertFalse(dv_produced_swift(self.tmp))


class RunArmDvGate(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="dvg-arm-")
        self.cwd = os.path.join(self.tmp, "with")
        os.makedirs(os.path.join(self.cwd, ".context", "logs"))

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _arm(self):
        return ArmSpec(name="with", bind_agent=True, cwd=self.cwd,
                       audit_path=os.path.join(self.cwd, ".context", "logs", "audit.jsonl"))

    def _prompts(self, stages):
        return {s: f"task {s}" for s in stages}

    def test_no_swift_after_dv_stops_arm_partial(self):
        stages = ["PL", "DV", "DR"]
        flushed = []
        res = run_arm(
            self._arm(), self._prompts(stages), SequencedFakeDispatcher([single_object_usage()]),
            budget_mod.RunningTally(100.0), "/x", stages,
            estimate_runner=fake_estimate_runner(0.001),
            persist_partial=lambda r: flushed.append(r.dispatched))
        self.assertTrue(res.dv_gated)
        self.assertTrue(res.partial)
        self.assertEqual([s for s, _ in res.usages], ["PL", "DV"])  # DR never dispatched
        self.assertEqual(flushed, [1, 2])  # PL and DV flushed before the gate stopped it

    def test_swift_present_after_dv_continues(self):
        os.makedirs(os.path.join(self.cwd, "Sources"))
        with open(os.path.join(self.cwd, "Sources", "App.swift"), "w") as f:
            f.write("let x = 1\n")
        stages = ["PL", "DV", "DR"]
        res = run_arm(
            self._arm(), self._prompts(stages), SequencedFakeDispatcher([single_object_usage()]),
            budget_mod.RunningTally(100.0), "/x", stages,
            estimate_runner=fake_estimate_runner(0.001))
        self.assertFalse(res.dv_gated)
        self.assertEqual([s for s, _ in res.usages], ["PL", "DV", "DR"])


if __name__ == "__main__":
    unittest.main()
