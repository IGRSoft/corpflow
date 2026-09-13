"""STAGE_TABLE SSOT parity (port of StageTableSSOTTests): stage-codes.md model and
effort columns match STAGE_TABLE; DR row is opus/high; efforts are valid; the table
covers exactly the 10-stage PIPELINE_STAGES (SR included); and the prose restatement in
headless-dispatch.md agrees with canon.
"""

import os
import re
import unittest

from benchmarklive.budget import PIPELINE_STAGES
from benchmarklive.dispatch import STAGE_TABLE

_HARNESS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_PLUGIN_ROOT = os.path.dirname(os.path.dirname(_HARNESS))
_STAGE_CODES = os.path.join(_PLUGIN_ROOT, "skills", "shared", "stage-codes.md")
_HEADLESS_DISPATCH = os.path.join(
    _PLUGIN_ROOT, "skills", "agent-coordination", "references", "headless-dispatch.md"
)

_ROW = re.compile(r"^\|\s*([A-Z]{2})\s*\|[^|]*\|[^|]*\|\s*(opus|sonnet|haiku)\s*\|", re.MULTILINE)

# Effort is the 5th column, whose vocabulary overlaps ordinary prose, so unlike _ROW this
# pattern cannot lean on a model-family alternation to anchor it — the cell classes exclude
# newlines to keep a short row from absorbing the next one.
_EFFORT_ROW = re.compile(
    r"^\|\s*([A-Z]{2})\s*\|[^|\n]*\|[^|\n]*\|\s*\w+\s*\|\s*(low|medium|high|xhigh)\s*\|",
    re.MULTILINE,
)

# The dispatch reference bolds the stage code and backticks the effort, and carries it one
# column earlier than stage-codes.md — a restatement table, not a second copy of canon.
_DISPATCH_ROW = re.compile(
    r"^\|\s*\*\*([A-Z]{2})\*\*\s*\|[^|\n]*\|[^|\n]*\|\s*`(\w+)`\s*\|",
    re.MULTILINE,
)


def _family(model_id: str) -> str:
    # "claude-opus-5" -> "opus"
    return model_id.split("-")[1]


class StageTableSSOT(unittest.TestCase):
    def test_table_covers_exactly_pipeline_stages(self):
        self.assertEqual(set(STAGE_TABLE), set(PIPELINE_STAGES))
        self.assertIn("SR", STAGE_TABLE)  # SR is in the live pipeline (D3)
        self.assertEqual(len(STAGE_TABLE), 10)

    def test_dr_row_is_technical_lead_opus_high(self):
        agent, model, effort = STAGE_TABLE["DR"]
        self.assertIn("technical-lead", agent)
        self.assertEqual(_family(model), "opus")
        self.assertEqual(effort, "high")

    def test_reconciled_efforts_and_models(self):
        self.assertEqual(STAGE_TABLE["AR"][2], "high")
        self.assertEqual(STAGE_TABLE["DV"][2], "high")
        self.assertEqual(STAGE_TABLE["DR"][2], "high")
        self.assertEqual(STAGE_TABLE["QA"][2], "medium")
        self.assertEqual(STAGE_TABLE["ST"][2], "low")
        self.assertEqual(_family(STAGE_TABLE["FN"][1]), "sonnet")

    def test_efforts_are_valid(self):
        for _, _, effort in STAGE_TABLE.values():
            self.assertIn(effort, {"low", "medium", "high", "xhigh"})

    def test_model_families_match_stage_codes_md(self):
        with open(_STAGE_CODES, encoding="utf-8") as f:
            declared = dict(_ROW.findall(f.read()))
        # Every stage present in BOTH sources must agree on model family.
        overlap = set(declared) & set(STAGE_TABLE)
        self.assertTrue(overlap, "no overlapping stage codes parsed from stage-codes.md")
        for code in overlap:
            self.assertEqual(_family(STAGE_TABLE[code][1]), declared[code],
                             f"{code} model family mismatch vs stage-codes.md")

    def test_efforts_match_stage_codes_md(self):
        with open(_STAGE_CODES, encoding="utf-8") as f:
            declared = dict(_EFFORT_ROW.findall(f.read()))
        overlap = set(declared) & set(STAGE_TABLE)
        self.assertTrue(overlap, "no overlapping stage codes parsed from stage-codes.md")
        for code in overlap:
            self.assertEqual(STAGE_TABLE[code][2], declared[code],
                             f"{code} effort mismatch vs stage-codes.md")

    def test_headless_dispatch_table_matches_stage_codes(self):
        # headless-dispatch.md restates the per-stage contract as prose for external CLI
        # dispatchers. Nothing imports it, so only an assertion that reads the file keeps it
        # honest; both sides are parsed from disk so a canon change fails here rather than
        # leaving the restatement quietly wrong.
        with open(_STAGE_CODES, encoding="utf-8") as f:
            canon = dict(_EFFORT_ROW.findall(f.read()))
        with open(_HEADLESS_DISPATCH, encoding="utf-8") as f:
            restated = dict(_DISPATCH_ROW.findall(f.read()))
        self.assertTrue(restated, "no stage rows parsed from headless-dispatch.md")
        # It documents a subset (and uniquely carries RE), so compare the overlap and let the
        # asymmetry stand rather than forcing the two tables to cover the same stages.
        overlap = set(canon) & set(restated)
        self.assertTrue(overlap, "no overlapping stage codes between canon and dispatch table")
        for code in sorted(overlap):
            self.assertEqual(restated[code], canon[code],
                             f"{code} effort in headless-dispatch.md disagrees with stage-codes.md")


if __name__ == "__main__":
    unittest.main()
