"""Prompt-assembly parity (port of PromptAssemblyTests): markers in [1][2][3][4][5]
order; [1]+[2] byte-identical across stages; stage-contract differs per stage and is
stable within; header carries only the two required literals; dispatch wiring feeds
the assembled prompt (all markers); [5] differs per stage.
"""

import os
import shutil
import tempfile
import unittest

from benchmarklive import preamble
from benchmarklive.dispatch import dispatch

import sys as _sys
_sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))  # _helpers under any runner
from _helpers import RecordingFakeDispatcher, fake_estimate_runner, make_live_sandbox, stub_git_sha

_MARKS = [preamble.MARK_CONTRACT, preamble.MARK_HEADER, preamble.MARK_STATE,
          preamble.MARK_CONTRACT_STAGE, preamble.MARK_TASK]


def _asm(stage, task="task body"):
    return preamble.assemble_stage_prompt(stage, "wt", ".context/planning-0.md",
                                          '{"k":1}\n', task)


class PromptAssembly(unittest.TestCase):
    def test_markers_in_order(self):
        p = _asm("PL")
        idx = [p.index(m) for m in _MARKS]
        self.assertEqual(idx, sorted(idx))

    def test_prefix_1_2_byte_identical_across_stages(self):
        pl = _asm("PL")
        dv = _asm("DV")
        prefix_pl = pl[:pl.index(preamble.MARK_STATE)]
        prefix_dv = dv[:dv.index(preamble.MARK_STATE)]
        self.assertEqual(prefix_pl, prefix_dv)  # [1]+[2] cross-stage stable

    def test_stage_contract_differs_per_stage(self):
        pl = _asm("PL")
        dv = _asm("DV")
        self.assertIn(preamble.STAGE_CONTRACT["PL"], pl)
        self.assertNotIn(preamble.STAGE_CONTRACT["PL"], dv)

    def test_stage_contract_stable_within_stage(self):
        self.assertEqual(_asm("PL"), _asm("PL"))

    def test_header_only_required_literals(self):
        h = preamble.header("wt", "plan.md")
        self.assertEqual(h, "worktask_id: wt\nplan_file: plan.md")
        self.assertNotIn("timestamp", h.lower())
        self.assertNotIn("agent", h.lower())

    def test_task_body_differs_per_stage(self):
        self.assertNotEqual(_asm("PL", "task PL"), _asm("PL", "task DV"))

    def test_dispatch_feeds_assembled_prompt_with_all_markers(self):
        tmp = tempfile.mkdtemp(prefix="asm-")
        try:
            sb = make_live_sandbox(tmp)
            fake = RecordingFakeDispatcher()
            dispatch(workdir=sb.run_id, budget=100.0, record_path=sb.record_path,
                     benchmark_dir=sb.benchmark_dir, dispatcher=fake,
                     env={"ANTHROPIC_API_KEY": "k"}, estimate_runner=fake_estimate_runner(0.001),
                     stages=["PL"], git_sha_runner=stub_git_sha)
            self.assertEqual(len(fake.calls), 1)
            _, prompt_text = fake.calls[0]
            for m in _MARKS:
                self.assertIn(m, prompt_text)
        finally:
            shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    unittest.main()
