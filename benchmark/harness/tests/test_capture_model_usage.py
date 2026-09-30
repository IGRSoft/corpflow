"""Token totals sum ``result.modelUsage`` (sub-agents included), not parent-only ``usage``.

The result event in ``fixtures/ar-config-leak.jsonl`` is a real one: its ``usage`` says 26k
output tokens while its ``modelUsage`` says 64k, which is what ``total_cost_usd`` paid for.
"""

import json
import os
import shutil
import tempfile
import unittest

from benchmarkkit import analysis, report
from benchmarkkit.metrics import StageAttribution
from benchmarklive import capture
from benchmarklive.dispatch import capture_stage_usage, dispatch

import sys as _sys
_sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _helpers import (
    SequencedFakeDispatcher,
    fake_estimate_runner,
    load_json,
    make_live_sandbox,
    stub_git_sha,
)

_ENV = {"ANTHROPIC_API_KEY": "k"}
_FIXTURE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures", "ar-config-leak.jsonl")


def real_stream() -> str:
    with open(_FIXTURE, encoding="utf-8") as f:
        return f.read()


def result_line(usage=None, model_usage=None, cost=1.5) -> str:
    obj = {"type": "result", "total_cost_usd": cost}
    if usage is not None:
        obj["usage"] = usage
    if model_usage is not None:
        obj["modelUsage"] = model_usage
    return json.dumps(obj)


class ParseModelUsage(unittest.TestCase):
    def test_real_result_sums_every_model_and_keeps_parent_figures(self):
        parsed = capture.parse(real_stream())
        self.assertEqual(
            (parsed.input_tokens, parsed.output_tokens, parsed.cache_read, parsed.cache_creation),
            (1533 + 48, 20 + 64295, 0 + 957751, 0 + 153212))
        self.assertEqual(
            (parsed.parent_input_tokens, parsed.parent_output_tokens,
             parsed.parent_cache_read, parsed.parent_cache_creation),
            (20, 26443, 436240, 67010))
        self.assertEqual(parsed.cost_usd, 2.4463652)

    def test_single_object_json_capture_sums_too(self):
        line = [ln for ln in real_stream().split("\n") if '"type": "result"' in ln][0]
        self.assertEqual(capture.parse(line).output_tokens, 64315)

    def test_absent_model_usage_falls_back_to_usage_with_no_parent_fields(self):
        parsed = capture.parse(result_line(usage={"input_tokens": 7, "output_tokens": 3,
                                                  "cache_read_input_tokens": 5,
                                                  "cache_creation_input_tokens": 2}))
        self.assertEqual((parsed.input_tokens, parsed.output_tokens, parsed.cache_read,
                          parsed.cache_creation), (7, 3, 5, 2))
        self.assertIsNone(parsed.parent_output_tokens)

    def test_empty_model_usage_falls_back_to_usage(self):
        parsed = capture.parse(result_line(usage={"input_tokens": 7, "output_tokens": 3}, model_usage={}))
        self.assertEqual(parsed.output_tokens, 3)
        self.assertIsNone(parsed.parent_output_tokens)

    def test_a_key_no_model_reports_falls_back_per_field(self):
        parsed = capture.parse(result_line(
            usage={"input_tokens": 1, "output_tokens": 2, "cache_read_input_tokens": 9},
            model_usage={"m1": {"outputTokens": 10}, "m2": {"outputTokens": 5}}))
        self.assertEqual((parsed.output_tokens, parsed.cache_read), (15, 9))
        self.assertEqual(parsed.parent_output_tokens, 2)

    def test_model_usage_without_usage_is_still_a_capture(self):
        parsed = capture.parse(result_line(model_usage={"m": {"inputTokens": 4, "outputTokens": 6}}))
        self.assertEqual((parsed.input_tokens, parsed.output_tokens), (4, 6))
        self.assertIsNone(parsed.parent_input_tokens)

    def test_non_integer_and_bool_values_are_ignored(self):
        parsed = capture.parse(result_line(
            usage={"output_tokens": 2},
            model_usage={"m1": {"outputTokens": "12"}, "m2": {"outputTokens": True},
                         "m3": {"outputTokens": 4}}))
        self.assertEqual(parsed.output_tokens, 4)

    def test_neither_usage_nor_model_usage_is_no_capture(self):
        self.assertIsNone(capture.parse(json.dumps({"type": "result"})))

    def test_stage_usage_carries_both_definitions(self):
        usage = capture_stage_usage(real_stream(), "/nonexistent/audit.jsonl", "AR")
        self.assertEqual((usage.output_tokens, usage.parent_output_tokens), (64315, 26443))
        self.assertEqual(usage.capture_layer, 1)


class StageAttributionRoundTrip(unittest.TestCase):
    def test_parent_fields_are_emitted_only_when_present(self):
        bare = StageAttribution("PL", 1, 2, 3, 4, 0.1).to_dict()
        self.assertFalse([k for k in bare if k.startswith("parent_")])
        full = StageAttribution("PL", 1, 2, 3, 4, 0.1, parent_fresh_in=1, parent_out=2,
                                parent_cache_read=3, parent_cache_creation=4)
        self.assertEqual(StageAttribution.from_dict(full.to_dict()), full)


class RecordCarriesBothDefinitions(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="mu-")
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self.sb = make_live_sandbox(self.tmp)

    def _run(self, stdout):
        dispatch(
            workdir=self.sb.run_id, budget=100.0, record_path=self.sb.record_path,
            benchmark_dir=self.sb.benchmark_dir, workdir_root=self.sb.workdir_root,
            dispatcher=SequencedFakeDispatcher([stdout]), env=_ENV,
            estimate_runner=fake_estimate_runner(0.001), stages=["PL"],
            git_sha_runner=stub_git_sha, without_arm="real", capture_mode="json",
            stderr=lambda s: None)
        return load_json(self.sb.record_path)

    def _json_result(self):
        line = [ln for ln in real_stream().split("\n") if '"type": "result"' in ln][0]
        return line

    def test_stage_rows_and_arm_totals_are_sub_agent_inclusive(self):
        record = self._run(self._json_result())
        row = next(s for s in record["stages"] if s["arm"] == "with")
        self.assertEqual((row["fresh_in"], row["out"], row["cache_read"], row["cache_creation"]),
                         (1581, 64315, 957751, 153212))
        self.assertEqual((row["parent_fresh_in"], row["parent_out"], row["parent_cache_read"],
                          row["parent_cache_creation"]), (20, 26443, 436240, 67010))
        self.assertEqual(record["paths"]["with"]["tokens"]["out"], 64315)

    def test_rows_without_model_usage_keep_their_old_shape(self):
        record = self._run(json.dumps({"type": "result", "total_cost_usd": 0.1,
                                       "usage": {"input_tokens": 3, "output_tokens": 2}}))
        row = next(s for s in record["stages"] if s["arm"] == "with")
        self.assertFalse([k for k in row if k.startswith("parent_")])

    def test_analysis_and_report_accept_the_new_fields(self):
        record = self._run(self._json_result())
        result = analysis.analyze(record)
        self.assertTrue(result["stages"])
        html = report.render_html({"live": [record]})
        self.assertIn("64,315", html.replace("&#44;", ","))


if __name__ == "__main__":
    unittest.main()
