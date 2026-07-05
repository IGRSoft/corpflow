#!/usr/bin/env python3
"""benchmark/tests/live/test_prompt_assembly.py — REQ-1 / AC-1 preamble fidelity.

Proves the live WITH-path stage prompt is ASSEMBLED with the production
cache-prefix layout ([1] contract-reminder + [2] worktask-header + [3] state-json
+ [4] stage-contract + [5] task) in binding order, and that the cross-stage
cacheable prefix [1]+[2] is byte-identical across two consecutive stages of one
worktask_id. All assertions run against the PURE assembler and the injected
RecordingFakeDispatcher — zero LLM calls, zero spend (AC-8 preserved: nothing
here imports benchmark/live/ on the deterministic path).
"""

from __future__ import annotations

import os
import sys
import tempfile
import unittest

_HELPERS = os.path.dirname(os.path.abspath(__file__))
if _HELPERS not in sys.path:
    sys.path.insert(0, _HELPERS)

from _helpers import (  # noqa: E402
    load_dispatch,
    RecordingFakeDispatcher,
    fake_estimate_runner,
)

# Load the pure assembler by path (hyphen-free dir, but load via the same seam
# the dispatch module uses so sibling imports resolve).
import importlib.util  # noqa: E402

_LIVE = os.path.normpath(os.path.join(_HELPERS, "..", "..", "live"))
if _LIVE not in sys.path:
    sys.path.insert(0, _LIVE)
_spec = importlib.util.spec_from_file_location(
    "preamble_under_test", os.path.join(_LIVE, "preamble.py")
)
preamble = importlib.util.module_from_spec(_spec)
sys.modules["preamble_under_test"] = preamble
_spec.loader.exec_module(preamble)


def _section(prompt: str, marker: str) -> str:
    """Extract a section body between <<<marker>>> and the next <<<...>>> tag.

    Mirrors cache-lint.sh extract_section so the test asserts the SAME slicing
    the production lint uses over a captured prompt-log.
    """
    lines = prompt.splitlines()
    out: list[str] = []
    capturing = False
    for ln in lines:
        if ln == marker:
            capturing = True
            continue
        if capturing and ln.startswith("<<<") and ln.endswith(">>>"):
            break
        if capturing:
            out.append(ln)
    return "\n".join(out)


class PureAssembler(unittest.TestCase):
    def test_markers_present_in_binding_order(self):
        prompt = preamble.assemble_stage_prompt(
            "PL",
            worktask_id="wf-x",
            plan_file=".context/planning-0.md",
            state_json_text='{"stages":{}}',
            task_text="do PL",
        )
        order = [
            preamble.MARK_CONTRACT,
            preamble.MARK_HEADER,
            preamble.MARK_STATE,
            preamble.MARK_CONTRACT_STAGE,
            preamble.MARK_TASK,
        ]
        positions = [prompt.index(m) for m in order]
        self.assertEqual(
            positions, sorted(positions),
            "markers must appear in [1][2][3][4][5] binding order",
        )

    def test_prefix_1_2_byte_identical_across_stages(self):
        common = dict(
            worktask_id="wf-x",
            plan_file=".context/planning-0.md",
            state_json_text='{"stages":{"PL":{"status":"completed"}}}',
        )
        p_pl = preamble.assemble_stage_prompt("PL", task_text="pl body", **common)
        p_ar = preamble.assemble_stage_prompt("AR", task_text="ar body", **common)
        # [1] contract-reminder byte-identical.
        self.assertEqual(
            _section(p_pl, preamble.MARK_CONTRACT),
            _section(p_ar, preamble.MARK_CONTRACT),
        )
        # [2] worktask-header byte-identical (same worktask_id + plan_file).
        self.assertEqual(
            _section(p_pl, preamble.MARK_HEADER),
            _section(p_ar, preamble.MARK_HEADER),
        )

    def test_stage_contract_differs_per_stage_but_stable_within_stage(self):
        common = dict(
            worktask_id="wf-x", plan_file="p", state_json_text="{}", task_text="t",
        )
        pl = preamble.assemble_stage_prompt("PL", **common)
        ar = preamble.assemble_stage_prompt("AR", **common)
        self.assertNotEqual(
            _section(pl, preamble.MARK_CONTRACT_STAGE),
            _section(ar, preamble.MARK_CONTRACT_STAGE),
        )
        pl2 = preamble.assemble_stage_prompt("PL", **common)
        self.assertEqual(
            _section(pl, preamble.MARK_CONTRACT_STAGE),
            _section(pl2, preamble.MARK_CONTRACT_STAGE),
        )

    def test_header_contains_only_required_literals(self):
        h = preamble.header("wf-x", ".context/planning-0.md")
        self.assertIn("worktask_id: wf-x", h)
        self.assertIn("plan_file: .context/planning-0.md", h)
        # No forbidden tokens: no agent name, no timestamp digits pattern.
        self.assertNotIn("software-architector", h)
        self.assertNotIn("T00:", h)


class DispatchWiring(unittest.TestCase):
    """The dispatcher receives the ASSEMBLED prompt (not a bare flat file)."""

    def _run_two_stages(self):
        dispatch = load_dispatch()
        fake = RecordingFakeDispatcher(outputs=["{}", "{}"])
        with tempfile.TemporaryDirectory() as tmp:
            prompts = os.path.join(tmp, "prompts")
            os.makedirs(prompts)
            for stg in ("pl", "ar"):
                with open(os.path.join(prompts, f"{stg}.txt"), "w") as f:
                    f.write(f"{stg} task body\n")
            usages, partial, dispatched = dispatch.run_pipeline(
                workdir_path=os.path.join(tmp, "wd"),
                budget=100.0,
                prompts_dir=prompts,
                audit_path=os.path.join(tmp, "audit.jsonl"),
                dispatcher=fake,
                estimate_runner=fake_estimate_runner(0.01),
                stages=("PL", "AR"),
                worktask_id="wf-live",
                plan_file=".context/planning-0.md",
            )
        return fake, dispatched

    def test_dispatcher_gets_assembled_prompt_with_all_markers(self):
        fake, dispatched = self._run_two_stages()
        self.assertEqual(dispatched, 2)
        first_prompt = fake.calls[0][1]  # (argv, prompt_text)
        for marker in ("<<<contract-reminder>>>", "<<<worktask-header>>>",
                       "<<<state-json>>>", "<<<stage-contract>>>", "<<<task>>>"):
            self.assertIn(marker, first_prompt)
        # [5] carries the dynamic task body.
        self.assertIn("pl task body", first_prompt)

    def test_prefix_1_2_byte_identical_across_dispatched_stages(self):
        fake, _ = self._run_two_stages()
        p_pl, p_ar = fake.calls[0][1], fake.calls[1][1]
        self.assertEqual(
            _section(p_pl, "<<<contract-reminder>>>"),
            _section(p_ar, "<<<contract-reminder>>>"),
        )
        self.assertEqual(
            _section(p_pl, "<<<worktask-header>>>"),
            _section(p_ar, "<<<worktask-header>>>"),
        )
        # [5] task bodies differ per stage.
        self.assertNotEqual(
            _section(p_pl, "<<<task>>>"), _section(p_ar, "<<<task>>>")
        )


if __name__ == "__main__":
    unittest.main()
