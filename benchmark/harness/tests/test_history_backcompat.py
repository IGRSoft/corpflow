"""R1 byte-compat gate (highest priority): the Python schema MUST decode today's
real history.json (vendored verbatim under fixtures/), and rotation on a copy MUST
preserve the other mode's bucket byte-identically.

The vendored copy includes a legacy live record whose tokens carry only 3 keys
(in/out/total, no cache keys) and float artifacts like 0.6807679999999999 — decode
must tolerate all of it.

# @test-required
# @test-tag: smoke
# @depends-on: BenchmarkRecord
# @depends-on: rotate
"""

import json
import os
import shutil
import tempfile
import unittest

from benchmarkkit import metrics, rotation
from benchmarkkit.metrics import BenchmarkRecord, PathMetrics, Tokens, make_record

_FIXTURE = os.path.join(os.path.dirname(__file__), "fixtures", "history.json")


def _fixture_text() -> str:
    with open(_FIXTURE, encoding="utf-8") as f:
        return f.read()


class HistoryBackCompat(unittest.TestCase):
    def test_vendored_history_parses(self):
        parsed = json.loads(_fixture_text())
        self.assertEqual(len(parsed["deterministic"]), 3)
        self.assertEqual(len(parsed["live"]), 1)

    def test_every_record_decodes_through_schema(self):
        parsed = json.loads(_fixture_text())
        for mode in ("deterministic", "live"):
            for rec_json in parsed[mode]:
                rec = BenchmarkRecord.from_dict(rec_json)
                self.assertTrue(rec.run_id)
                self.assertEqual(rec.mode, mode)
                self.assertIsNotNone(rec.path_with)
                self.assertIsNotNone(rec.path_without)

    def test_legacy_live_record_tokens_decode_with_nil_cache(self):
        parsed = json.loads(_fixture_text())
        rec = BenchmarkRecord.from_dict(parsed["live"][0])
        tokens = rec.path_with.tokens
        self.assertEqual(tokens.input, 574557)
        self.assertEqual(tokens.output, 7329)
        self.assertEqual(tokens.total, 581886)
        # Legacy record lacks cache keys — decode yields None, never fabricated.
        self.assertIsNone(tokens.cache_read)
        self.assertIsNone(tokens.cache_creation)
        self.assertEqual(rec.path_with.cost_usd, 1.241815)
        self.assertEqual(rec.stages, [])
        self.assertFalse(rec.live_partial)

    def test_deterministic_records_carry_app_path_and_five_token_keys(self):
        parsed = json.loads(_fixture_text())
        for rec_json in parsed["deterministic"]:
            token_keys = list(rec_json["paths"]["with"]["tokens"].keys())
            self.assertEqual(
                token_keys, ["in", "out", "total", "cache_read", "cache_creation"]
            )
            rec = BenchmarkRecord.from_dict(rec_json)
            self.assertTrue(rec.path_with.app_path.startswith("benchmark/workdirs/"))

    def test_float_artifacts_survive_reserialization(self):
        # Python emitted 0.035500000000000004 / 0.6807679999999999 — native json
        # round-trips these doubles exactly (shortest-round-trip repr).
        text = json.dumps(json.loads(_fixture_text()), indent=2)
        self.assertIn("0.035500000000000004", text)
        self.assertIn("0.6807679999999999", text)

    def test_whole_file_roundtrip_is_byte_identical(self):
        # The strongest byte-compat oracle: native json is exactly the writer that
        # produced the on-disk file (indent=2, no trailing newline).
        text = _fixture_text()
        self.assertEqual(json.dumps(json.loads(text), indent=2), text)

    def test_rotation_on_real_history_preserves_other_mode(self):
        td = tempfile.mkdtemp(prefix="backcompat-")
        try:
            history_path = os.path.join(td, "history.json")
            with open(history_path, "w", encoding="utf-8") as f:
                f.write(_fixture_text())

            with open(history_path, encoding="utf-8") as f:
                live_before = json.dumps(json.load(f)["live"], indent=2)

            pm = PathMetrics(
                tokens=Tokens(input=None, output=None, total=None),
                cost_usd=None,
                wall_clock_s=0.01,
                loc_produced=500,
                test_count=48,
                coverage_pct=0.0,
                estimate_complexity_score=15,
                stage_count=9,
                pass_fail="pass",
                app_path="benchmark/workdirs/new/with",
            )
            new_rec = make_record(
                run_id="deterministic-new",
                timestamp_utc="2026-07-06T00:00:00Z",
                mode="deterministic",
                git_sha="abc1234",
                budget_usd=None,
                with_pm=pm,
                without_pm=pm,
            )
            rotation.rotate(history_path, new_rec.to_dict())

            with open(history_path, encoding="utf-8") as f:
                after = json.load(f)
            self.assertEqual(
                json.dumps(after["live"], indent=2),
                live_before,
                "live bucket must be untouched by a deterministic rotation",
            )
            self.assertEqual(len(after["deterministic"]), 3)
            self.assertEqual(after["deterministic"][-1]["run_id"], "deterministic-new")
        finally:
            shutil.rmtree(td, ignore_errors=True)

    def test_fresh_deterministic_record_delta_numtypes(self):
        # D-NUMTYPES gate: coverage_pct delta stays float 0.0, loc_produced delta
        # stays int 0 — no Swift-style whole-float->int coercion.
        pm = PathMetrics(
            tokens=Tokens(),
            cost_usd=None,
            wall_clock_s=0.03,
            loc_produced=345,
            test_count=20,
            coverage_pct=0.0,
            estimate_complexity_score=15,
            stage_count=5,
            pass_fail="pass",
            app_path="benchmark/workdirs/x/with",
        )
        without = PathMetrics(
            tokens=Tokens(),
            cost_usd=None,
            wall_clock_s=0.001,
            loc_produced=345,
            test_count=20,
            coverage_pct=0.0,
            estimate_complexity_score=0,
            stage_count=1,
            pass_fail="pass",
            app_path="benchmark/workdirs/x/without",
        )
        rec = make_record(
            run_id="deterministic-x",
            timestamp_utc="2026-07-06T00:00:00Z",
            mode="deterministic",
            git_sha="abc1234",
            budget_usd=None,
            with_pm=pm,
            without_pm=without,
        )
        d = rec.to_dict()
        cov = d["comparison"]["coverage_pct"]["delta"]
        loc = d["comparison"]["loc_produced"]["delta"]
        self.assertIsInstance(cov, float)
        self.assertEqual(cov, 0.0)
        self.assertIsInstance(loc, int)
        self.assertEqual(loc, 0)
        # And the serialized bytes show the type distinction.
        text = metrics.dumps(rec)
        self.assertIn('"delta": 0.0', text)  # coverage_pct
        self.assertIn('"delta": 0', text)     # loc_produced (int)
        # No comparison beyond the 6 deterministic keys.
        self.assertEqual(list(d["comparison"].keys()), metrics.DETERMINISTIC_COMPARISON_KEYS)


if __name__ == "__main__":
    unittest.main()
