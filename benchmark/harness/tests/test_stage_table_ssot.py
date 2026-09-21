"""STAGE_TABLE SSOT parity (port of StageTableSSOTTests): stage-codes.md model and
effort columns match STAGE_TABLE; DR row is opus/high; efforts are valid; the table
covers exactly the 10-stage PIPELINE_STAGES (SR included); and headless-dispatch.md's
per-stage flag table points at stage-codes.md for model/effort instead of restating them.
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

# The dispatch reference bolds the stage code and backticks $AGENT and $MODE — three
# columns, no model or effort cell.
_DISPATCH_ROW = re.compile(
    r"^\|\s*\*\*([A-Z]{2})\*\*\s*\|\s*`([^`]+)`\s*\|\s*`([^`]+)`\s*\|",
    re.MULTILINE,
)

_MODEL_TERMS = {"opus", "sonnet", "haiku", "claude-opus-5", "claude-sonnet-5"}
_EFFORT_TERMS = {"low", "medium", "high", "xhigh", "max"}


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

    def test_headless_dispatch_table_points_to_stage_codes(self):
        # headless-dispatch.md's flag table carries $AGENT and $MODE per stage but no
        # model/effort cell — those are looked up from stage-codes.md at call time (§ Model &
        # effort defaults). Nothing imports the reference, so this reads it from disk: every
        # parsed row's stage code must be canon, neither cell may restate a model or effort
        # term, and the defaults section must still point at stage-codes.md.
        with open(_STAGE_CODES, encoding="utf-8") as f:
            stage_codes_text = f.read()
            canon_codes = set(dict(_ROW.findall(stage_codes_text)))
        with open(_HEADLESS_DISPATCH, encoding="utf-8") as f:
            headless_text = f.read()
        rows = _DISPATCH_ROW.findall(headless_text)
        self.assertTrue(rows, "no stage rows parsed from headless-dispatch.md")
        for code, agent, mode in rows:
            self.assertIn(code, canon_codes, f"{code} is not a stage-codes.md stage")
            for cell in (agent, mode):
                self.assertNotIn(cell.strip().lower(), _MODEL_TERMS,
                                  f"{code} row restates a model: {cell!r}")
                self.assertNotIn(cell.strip().lower(), _EFFORT_TERMS,
                                  f"{code} row restates an effort tier: {cell!r}")
        self.assertIn("stage-codes.md", headless_text.split("Model & effort defaults", 1)[-1][:400])


if __name__ == "__main__":
    unittest.main()
