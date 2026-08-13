"""Capture parser parity (port of CoverageParserTests): single-object usage /
no-coverage; stream-json → manifest + result usage; stream without result keeps
coverage with usage nil; garbage → None; capture_stage_usage Layer-2 fallback keeps
the manifest; Layer-3 all-nil; manifest rides into record stages[0] after cost_usd.
"""

import json
import os
import shutil
import tempfile
import unittest

from benchmarklive import capture, dispatch
from benchmarklive.dispatch import StageUsage, build_live_record

import sys as _sys
_sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))  # _helpers under any runner
from _helpers import single_object_usage, stream_json


class CaptureParser(unittest.TestCase):
    def test_single_object_usage_no_coverage(self):
        p = capture.parse(single_object_usage(input_tokens=10, output_tokens=5, cost=0.02))
        self.assertTrue(p.has_usage)
        self.assertEqual(p.input_tokens, 10)
        self.assertEqual(p.cost_usd, 0.02)
        self.assertIsNone(p.coverage)

    def test_stream_json_manifest_and_usage(self):
        s = stream_json(tool_uses=[
            ("Task", {"subagent_type": "corpflow:developer"}),
            ("Skill", {"skill": "corpflow:test-plan"}),
            ("SlashCommand", {"command": "/worktask"}),
        ], result_usage=True, cost=0.05)
        p = capture.parse(s)
        self.assertEqual(p.coverage.agents, ["corpflow:developer"])
        self.assertEqual(p.coverage.skills, ["corpflow:test-plan"])
        self.assertEqual(p.coverage.commands, ["/worktask"])
        self.assertEqual(p.coverage.tool_calls, 3)
        self.assertEqual(p.cost_usd, 0.05)

    def test_stream_without_result_keeps_coverage_usage_nil(self):
        s = stream_json(tool_uses=[("Task", {"subagent_type": "a"})], result_usage=False)
        p = capture.parse(s)
        self.assertIsNotNone(p.coverage)
        self.assertFalse(p.has_usage)

    def test_garbage_returns_none(self):
        self.assertIsNone(capture.parse("total garbage not json"))
        self.assertIsNone(capture.parse_single_object("{}"))

    def test_capture_stage_usage_layer2_fallback_keeps_manifest(self):
        tmp = tempfile.mkdtemp(prefix="cap-")
        try:
            audit = os.path.join(tmp, "audit.jsonl")
            with open(audit, "w") as f:
                f.write(json.dumps({
                    "action": "external_dispatch",
                    "metadata": {"stage": "PL", "usage": {"input_tokens": 99, "output_tokens": 11}},
                }) + "\n")
            # stdout has a manifest but NO usage (result_usage=False) → Layer 2 supplies usage.
            stdout = stream_json(tool_uses=[("Task", {"subagent_type": "x"})], result_usage=False)
            u = dispatch.capture_stage_usage(stdout, audit, "PL")
            self.assertEqual(u.capture_layer, 2)
            self.assertEqual(u.input_tokens, 99)
            self.assertIsNotNone(u.coverage)  # manifest rides along
        finally:
            shutil.rmtree(tmp, ignore_errors=True)

    def test_layer3_all_nil(self):
        u = dispatch.capture_stage_usage("not json", "/nonexistent/audit.jsonl", "PL")
        self.assertIsNone(u.capture_layer)
        self.assertIsNone(u.input_tokens)

    def test_manifest_rides_into_record_stage(self):
        from benchmarkkit.metrics import StageCoverage
        cov = StageCoverage(agents=["a"], skills=[], commands=[], tool_calls=1)
        usages = [("PL", StageUsage(input_tokens=10, output_tokens=5, cost_usd=0.1, capture_layer=1, coverage=cov))]
        rec = build_live_record("r", "t", "sha", 5.0, usages, 1, live_partial=False).to_dict()
        stage0 = rec["stages"][0]
        self.assertIn("coverage", stage0)
        keys = list(stage0.keys())
        self.assertGreater(keys.index("coverage"), keys.index("cost_usd"))  # after cost_usd


class AgentAliasAndNestedSpawns(unittest.TestCase):
    """A4: the `Agent` tool aliases `Task`; nested background spawns are counted from
    the per-arm audit (canonical rows only, deduped) and emitted only when >0."""

    def test_agent_tool_name_aliases_task(self):
        s = stream_json(tool_uses=[("Agent", {"subagent_type": "system-developer:python-developer"})])
        p = capture.parse(s)
        self.assertEqual(p.coverage.agents, ["system-developer:python-developer"])

    def _audit(self, tmp, rows):
        audit = os.path.join(tmp, "audit.jsonl")
        with open(audit, "w", encoding="utf-8") as f:
            for r in rows:
                f.write(json.dumps(r) + "\n")
        return audit

    def test_nested_background_counted_canonical_only_deduped(self):
        tmp = tempfile.mkdtemp(prefix="nest-")
        try:
            audit = self._audit(tmp, [
                {"action": "subagent_stopped", "metadata": {"stage": "DV", "dedupe_key": "a"}},
                {"action": "subagent_stopped", "metadata": {"stage": "DV", "dedupe_key": "a"}},  # dup
                {"action": "subagent_stopped", "metadata": {"stage": "DV", "dedupe_key": "b"}},
                {"action": "subagent_stopped", "metadata": {"stage": "DV", "advisory": True}},    # mirror
                {"action": "subagent_stopped", "metadata": {"stage": "PL", "dedupe_key": "c"}},   # other stage
            ])
            stdout = stream_json(tool_uses=[("Task", {"subagent_type": "x"})], result_usage=True)
            u = dispatch.capture_stage_usage(stdout, audit, "DV")
            self.assertEqual(u.coverage.nested_background, 2)  # a + b, advisory+dup+PL excluded
        finally:
            shutil.rmtree(tmp, ignore_errors=True)

    def test_nested_background_byte_shape(self):
        from benchmarkkit.metrics import StageCoverage
        self.assertEqual(list(StageCoverage([], [], [], 0).to_dict().keys()),
                         ["agents", "skills", "commands", "tool_calls"])  # 4-key preserved
        self.assertIn("nested_background", StageCoverage([], [], [], 0, nested_background=3).to_dict())


if __name__ == "__main__":
    unittest.main()
