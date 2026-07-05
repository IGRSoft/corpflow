#!/usr/bin/env python3
"""benchmark/tests/with-plugin/test_stage_table_ssot.py — REQ-5/AC-6 (ad4).

`benchmark/live/dispatch.py` STAGE_TABLE is the machine-checked SSOT for
per-stage (model, effort) tiers (ad4 — dispatch.py is opus-correct for DR; the
drift was in prose docs, not code). This test pins STAGE_TABLE against
`skills/shared/stage-codes.md`'s Model column (parsed, not hand-copied) so a
future manual edit that re-introduces a stale tier (e.g. sonnet-for-DR) fails a
test rather than silently rotting a doc paragraph.

Kept deliberately non-brittle (RK-A7): only the (model-tier, stage) pairing is
asserted, not markdown table structure beyond the two columns needed.

IMPORTANT (AC-8 tripwire safety): this test lives under `tests/with-plugin/`,
which shares a process with `test_generators.py::test_no_live_import` — that
tripwire fails if ANY module whose `__file__` is under `benchmark/live/` ever
appears in `sys.modules`, regardless of module name. A real `import dispatch`
(even via importlib-by-path) would trip it. So STAGE_TABLE is read via `ast`
static parsing of the source text — dispatch.py is NEVER executed or imported,
only its AST is inspected for the STAGE_TABLE dict literal's keys/values.
"""

from __future__ import annotations

import ast
import os
import re
import unittest

_HERE = os.path.dirname(os.path.abspath(__file__))
_PLUGIN_ROOT = os.path.normpath(os.path.join(_HERE, "..", "..", ".."))
DISPATCH_PY = os.path.normpath(os.path.join(_HERE, "..", "..", "live", "dispatch.py"))
STAGE_CODES_MD = os.path.join(_PLUGIN_ROOT, "skills", "shared", "stage-codes.md")


def _parse_stage_table_from_source() -> dict[str, tuple[str, str, str]]:
    """Statically parse STAGE_TABLE's dict literal out of dispatch.py's AST —
    never imports/executes the module (AC-8 tripwire safety, see module doc).
    Returns {stage_code: (agent, model_id, effort)}.
    """
    with open(DISPATCH_PY, "r", encoding="utf-8") as f:
        tree = ast.parse(f.read(), filename=DISPATCH_PY)

    table: dict[str, tuple[str, str, str]] = {}
    for node in ast.walk(tree):
        if isinstance(node, ast.AnnAssign) and getattr(node.target, "id", None) == "STAGE_TABLE":
            value = node.value
        elif isinstance(node, ast.Assign) and any(
            getattr(t, "id", None) == "STAGE_TABLE" for t in node.targets
        ):
            value = node.value
        else:
            continue
        if not isinstance(value, ast.Dict):
            continue
        for k, v in zip(value.keys, value.values):
            if not (isinstance(k, ast.Constant) and isinstance(v, ast.Tuple)):
                continue
            elts = [e.value for e in v.elts if isinstance(e, ast.Constant)]
            if len(elts) == 3:
                table[k.value] = tuple(elts)  # (agent, model_id, effort)
        break
    return table

# Model-id -> tier-alias map (dispatch.py stores concrete IDs; stage-codes.md
# stores the alias). Mirrors skills/shared/model-selection.md's alias table.
_MODEL_ID_TO_ALIAS = {
    "claude-opus-4-8": "opus",
    "claude-sonnet-4-6": "sonnet",
    "claude-haiku-4-5": "haiku",
}

# Effort tiers are NOT in stage-codes.md's table (that file tracks model only);
# pin them against the canonical orchestration contract this benchmark itself
# imports its architecture from (CLAUDE.md § Feature Development 9-stage table
# + skills/shared/model-selection.md "Complex" tier for DR). Kept as a small
# literal map, not re-parsed from prose, per RK-A7 (avoid brittle doc parsing
# for the harder-to-locate effort field).
_EXPECTED_EFFORT: dict[str, str] = {
    "PL": "high",
    "AR": "xhigh",
    "TL": "medium",
    "DV": "xhigh",
    "DR": "xhigh",
    "SR": "xhigh",
    "QA": "high",
    "DC": "low",
    "FN": "medium",
    "ST": "medium",
}


def _parse_stage_codes_model_column() -> dict[str, str]:
    """Parse `| <CODE> | <Stage> | <agent> | <model> |` rows from stage-codes.md
    § Primary Stages table. Returns {stage_code: model_alias}. Defensive: skips
    the header/separator rows and any row that doesn't match 4 pipe-delimited
    cells with a 2-letter-plus stage code in the first column.
    """
    with open(STAGE_CODES_MD, "r", encoding="utf-8") as f:
        text = f.read()
    mapping: dict[str, str] = {}
    row_re = re.compile(
        r"^\|\s*([A-Z]{2,3})\s*\|\s*[^|]+\|\s*[^|]+\|\s*(opus|sonnet|haiku)\s*\|\s*$",
        re.MULTILINE,
    )
    for code, model in row_re.findall(text):
        mapping[code] = model
    return mapping


class StageTableSSOT(unittest.TestCase):
    def test_stage_codes_md_model_column_matches_dispatch_stage_table(self):
        """Every STAGE_TABLE entry's model tier matches stage-codes.md's row
        for that stage code (the doc-drift class AC-6/ad4 exists to kill)."""
        doc_models = _parse_stage_codes_model_column()
        self.assertTrue(doc_models, "failed to parse any rows from stage-codes.md")
        stage_table = _parse_stage_table_from_source()
        self.assertTrue(stage_table, "failed to statically parse STAGE_TABLE from dispatch.py")
        mismatches = []
        for code, (_, model_id, _effort) in stage_table.items():
            if code not in doc_models:
                continue  # e.g. IR isn't in the live benchmark's pipeline
            expected_alias = doc_models[code]
            actual_alias = _MODEL_ID_TO_ALIAS.get(model_id, model_id)
            if actual_alias != expected_alias:
                mismatches.append(
                    f"{code}: dispatch.py={actual_alias} ({model_id}) vs "
                    f"stage-codes.md={expected_alias}"
                )
        self.assertEqual(
            mismatches, [],
            "STAGE_TABLE model tier drifted from stage-codes.md:\n"
            + "\n".join(mismatches),
        )

    def test_dr_row_is_opus_xhigh(self):
        """AC-6 headline assertion: DR must be opus/xhigh (ad4 — the drift
        README F5 warned about, now killed at the doc layer too)."""
        stage_table = _parse_stage_table_from_source()
        agent, model_id, effort = stage_table["DR"]
        self.assertEqual(agent, "igrsoft:technical-lead")
        self.assertEqual(model_id, "claude-opus-4-8")
        self.assertEqual(effort, "xhigh")

    def test_effort_tiers_match_expected_map(self):
        stage_table = _parse_stage_table_from_source()
        mismatches = []
        for code, (_, _model_id, effort) in stage_table.items():
            expected = _EXPECTED_EFFORT.get(code)
            if expected is None:
                continue
            if effort != expected:
                mismatches.append(f"{code}: dispatch.py effort={effort} vs expected={expected}")
        self.assertEqual(mismatches, [], "\n".join(mismatches))


if __name__ == "__main__":
    unittest.main()
