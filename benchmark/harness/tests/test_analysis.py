"""Analysis parity: totals/premium math on a synthetic paired record, placeholder-
WITHOUT record → caveat + no premium, per-stage cost/out/cache-hit shares, mechanical
outlier thresholds, markdown section/checkbox presence, and the vendored live fixture
analyzing cleanly with a cross-era caveat (its tokens lack cache_read/cache_creation).
"""

import json
import os
import unittest

from benchmarkkit import analysis
from benchmarkkit.metrics import PathMetrics, StageAttribution, Tokens, make_record

_FIXTURE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures", "history.json")


def _paired_live_record(stages=None):
    with_tokens = Tokens(input=1000, output=500, total=1500, cache_read=300, cache_creation=100)
    with_pm = PathMetrics(with_tokens, 0.20, 10.0, 400, 10, 0.0, 15, len(stages or []) or 1,
                          "pass", "benchmark/workdirs/x/with")
    without_tokens = Tokens(input=400, output=200, total=600)
    without_pm = PathMetrics(without_tokens, 0.10, 5.0, 300, 8, 0.0, 0, 1,
                             "pass", "benchmark/workdirs/x/without")
    return make_record("r-1", "2026-07-20T00:00:00Z", "live", "sha1", None,
                       with_pm, without_pm, stages=stages).to_dict()


def _placeholder_without_paired_live_record():
    with_tokens = Tokens(input=1000, output=500, total=1500, cache_read=0, cache_creation=0)
    with_pm = PathMetrics(with_tokens, 0.20, 10.0, 400, 10, 0.0, 15, 1, "pass",
                          "benchmark/workdirs/x/with")
    without_pm = PathMetrics(Tokens(), None, 0.0, 0, 0, 0.0, 0, 1, "pass", None)
    return make_record("r-2", "2026-07-20T00:00:00Z", "live", "sha1", None,
                       with_pm, without_pm).to_dict()


def _stage(name, cost, out, fresh_in=1000, cache_creation=0, cache_read=0):
    return StageAttribution(stage=name, fresh_in=fresh_in, cache_creation=cache_creation,
                            cache_read=cache_read, out=out, cost_usd=cost)


class Totals(unittest.TestCase):
    def test_premium_math_on_paired_record(self):
        rec = _paired_live_record()
        result = analysis.analyze(rec)
        tt = result["totals"]["tokens_total"]
        self.assertEqual(tt["with"], 1500)
        self.assertEqual(tt["without"], 600)
        self.assertEqual(tt["delta"], 900)
        self.assertAlmostEqual(tt["premium_pct"], 900 / 600 * 100.0)

        cost = result["totals"]["cost_usd"]
        self.assertAlmostEqual(cost["delta"], 0.10, places=9)
        self.assertAlmostEqual(cost["premium_pct"], 0.10 / 0.10 * 100.0)

    def test_placeholder_without_no_premium_and_caveat(self):
        rec = _placeholder_without_paired_live_record()
        result = analysis.analyze(rec)
        self.assertIsNone(result["totals"]["tokens_total"]["premium_pct"])
        self.assertIsNone(result["totals"]["cost_usd"]["premium_pct"])
        self.assertTrue(any("placeholder" in c for c in result["caveats"]))


class PerStage(unittest.TestCase):
    def test_cost_share_out_share_and_cache_hit(self):
        stages = [
            _stage("PL", cost=1.0, out=100, fresh_in=700, cache_creation=100, cache_read=200),
            _stage("AR", cost=3.0, out=300, fresh_in=900, cache_creation=0, cache_read=100),
        ]
        rec = _paired_live_record(stages=stages)
        result = analysis.analyze(rec)
        rows = {r["stage"]: r for r in result["stages"]}

        self.assertAlmostEqual(rows["PL"]["cost_share_pct"], 1.0 / 4.0 * 100.0)
        self.assertAlmostEqual(rows["AR"]["cost_share_pct"], 3.0 / 4.0 * 100.0)
        self.assertAlmostEqual(rows["PL"]["out_token_share_pct"], 100 / 400 * 100.0)
        self.assertAlmostEqual(rows["AR"]["out_token_share_pct"], 300 / 400 * 100.0)

        # cache-hit% = cache_read / (fresh_in + cache_creation + cache_read)
        self.assertAlmostEqual(rows["PL"]["cache_hit_pct"], 200 / (700 + 100 + 200) * 100.0)
        self.assertAlmostEqual(rows["AR"]["cache_hit_pct"], 100 / (900 + 0 + 100) * 100.0)

    def test_cache_top_sorted_descending(self):
        stages = [
            _stage("PL", cost=1.0, out=10, cache_creation=50),
            _stage("AR", cost=1.0, out=10, cache_creation=200),
            _stage("TL", cost=1.0, out=10, cache_creation=0),
        ]
        rec = _paired_live_record(stages=stages)
        result = analysis.analyze(rec)
        self.assertEqual([e["stage"] for e in result["cache_top"]], ["AR", "PL"])  # TL excluded (0)


class OutlierFlags(unittest.TestCase):
    def test_stage_cost_outlier_fires_above_1_5x_median(self):
        # Median of [1,1,1] is 1; 1.6 > 1.5x median -> flags; nothing else does.
        stages = [_stage("PL", cost=1.0, out=10), _stage("AR", cost=1.0, out=10),
                  _stage("TL", cost=1.6, out=10)]
        rec = _paired_live_record(stages=stages)
        result = analysis.analyze(rec)
        cost_flags = [f for f in result["outliers"] if f["type"] == "stage_cost_outlier"]
        self.assertEqual([f["stage"] for f in cost_flags], ["TL"])

    def test_no_outlier_below_threshold(self):
        stages = [_stage("PL", cost=1.0, out=10), _stage("AR", cost=1.0, out=10),
                  _stage("TL", cost=1.4, out=10)]
        rec = _paired_live_record(stages=stages)
        result = analysis.analyze(rec)
        cost_flags = [f for f in result["outliers"] if f["type"] == "stage_cost_outlier"]
        self.assertEqual(cost_flags, [])

    def test_missing_app_verdict_flag(self):
        rec = _paired_live_record()
        rec["paths"]["with"]["pass_fail"] = "fail"
        result = analysis.analyze(rec)
        self.assertTrue(any(f["type"] == "missing_app_verdict" and f["stage"] == "with"
                            for f in result["outliers"]))

    def test_degraded_capture_flag(self):
        stages = [StageAttribution(stage="QA", fresh_in=None, cache_creation=None,
                                   cache_read=None, out=None, cost_usd=None)]
        rec = _paired_live_record(stages=stages)
        result = analysis.analyze(rec)
        self.assertTrue(any(f["type"] == "degraded_capture" and f["stage"] == "QA"
                            for f in result["outliers"]))


class Markdown(unittest.TestCase):
    def test_required_sections_and_checkboxes_present(self):
        stages = [_stage("PL", cost=1.0, out=10), _stage("AR", cost=1.0, out=10),
                  _stage("TL", cost=1.6, out=10)]
        rec = _paired_live_record(stages=stages)
        md = analysis.render_markdown(analysis.analyze(rec))
        for section in ("## totals", "## per-stage", "## cache-economics",
                        "## quality-delta", "## validity-caveats", "## improvement-candidates"):
            self.assertIn(section, md)
        self.assertIn("- [ ]", md)
        self.assertTrue(md.rstrip().endswith(")"))  # ends inside the improvement-candidates block

    def test_no_outliers_renders_without_checkboxes(self):
        rec = _paired_live_record()
        md = analysis.render_markdown(analysis.analyze(rec))
        self.assertIn("## improvement-candidates", md)
        self.assertNotIn("- [ ]", md)


class CSurfacing(unittest.TestCase):
    """C: per-stage tool-call column, tool_call_spike (> max(40, 1.5x median)),
    background_nested_spawn (>0), and paired WITH/WITHOUT per-prompt token columns."""

    def _cov_stage(self, name, tool_calls, nested=0, arm=None):
        from benchmarkkit.metrics import StageCoverage
        cov = StageCoverage(agents=[], skills=[], commands=[], tool_calls=tool_calls,
                            nested_background=nested)
        return StageAttribution(stage=name, fresh_in=100, cache_creation=0, cache_read=0,
                                out=50, cost_usd=0.1, coverage=cov, arm=arm)

    def test_tool_call_spike_and_nested_flags(self):
        stages = [self._cov_stage("PL", 5), self._cov_stage("AR", 5),
                  self._cov_stage("DV", 60, nested=2)]
        rec = _paired_live_record(stages=stages)
        result = analysis.analyze(rec)
        types = {(f["type"], f["stage"]) for f in result["outliers"]}
        self.assertIn(("tool_call_spike", "DV"), types)  # 60 > max(40, 1.5*5)
        self.assertIn(("background_nested_spawn", "DV"), types)
        self.assertNotIn(("tool_call_spike", "PL"), types)

    def test_tool_calls_column_and_paired_tokens(self):
        stages = [self._cov_stage("PL", 3, arm="with"), self._cov_stage("PL", 2, arm="without")]
        rec = _paired_live_record(stages=stages)
        result = analysis.analyze(rec)
        self.assertEqual(len(result["paired_tokens"]), 1)
        pt = result["paired_tokens"][0]
        self.assertEqual((pt["with_in"], pt["without_in"]), (100, 100))
        md = analysis.render_markdown(result)
        self.assertIn("tool calls", md)
        self.assertIn("## paired-tokens", md)


class ArmAttribution(unittest.TestCase):
    """Item 2: per-stage rows, cache-economics rows, and improvement-candidate lines carry an
    explicit arm label on the paired path; records without an ``arm`` tag degrade to '—'."""

    def _armed(self, name, arm, cost=0.1, out=50, cache_creation=0):
        return StageAttribution(stage=name, fresh_in=100, cache_creation=cache_creation,
                                cache_read=0, out=out, cost_usd=cost, arm=arm)

    def test_per_stage_rows_and_table_carry_arm(self):
        stages = [self._armed("DV", "with", cost=9.0, out=900, cache_creation=500),
                  self._armed("DV", "without", cost=1.0, out=100, cache_creation=50)]
        result = analysis.analyze(_paired_live_record(stages=stages))
        self.assertEqual([r["arm"] for r in result["stages"]], ["with", "without"])
        md = analysis.render_markdown(result)
        self.assertIn("| stage | arm | cost (USD)", md)
        self.assertIn("| DV | with |", md)
        self.assertIn("| DV | without |", md)
        # cache-economics disambiguates the twin DV rows by arm.
        self.assertIn("| stage | arm | cache_creation |", md)
        self.assertEqual([e["arm"] for e in result["cache_top"]], ["with", "without"])

    def test_improvement_candidate_lines_name_the_arm(self):
        # DV(with) cost 9.0 is the lone outlier vs the [9,1,1,1] median of 1.
        stages = [self._armed("DV", "with", cost=9.0), self._armed("PL", "with", cost=1.0),
                  self._armed("DV", "without", cost=1.0), self._armed("PL", "without", cost=1.0)]
        md = analysis.render_markdown(analysis.analyze(_paired_live_record(stages=stages)))
        self.assertIn("(stage_cost_outlier) DV [with]:", md)

    def test_untagged_record_shows_em_dash_arm(self):
        stages = [_stage("PL", cost=1.0, out=10)]  # no arm
        md = analysis.render_markdown(analysis.analyze(_paired_live_record(stages=stages)))
        self.assertIn("| PL | — |", md)


class PairedCachedInput(unittest.TestCase):
    """Item 1: the paired-tokens table exposes per-arm cached-input mass (cache_creation +
    cache_read) so input columns are no longer a fresh-only understatement."""

    def _stage(self, name, arm, fresh_in, cc, cr):
        return StageAttribution(stage=name, fresh_in=fresh_in, cache_creation=cc,
                                cache_read=cr, out=10, cost_usd=0.1, arm=arm)

    def test_cached_in_derived_and_rendered(self):
        stages = [self._stage("PL", "with", 45, cc=100, cr=1_241_703),
                  self._stage("PL", "without", 8, cc=5, cr=200)]
        result = analysis.analyze(_paired_live_record(stages=stages))
        pt = result["paired_tokens"][0]
        self.assertEqual(pt["with_cached"], 100 + 1_241_703)
        self.assertEqual(pt["without_cached"], 205)
        md = analysis.render_markdown(result)
        self.assertIn("WITH cached-in", md)
        self.assertIn("WITHOUT cached-in", md)
        self.assertIn(f"| PL | 45 | {100 + 1_241_703} |", md)

    def test_cross_era_stage_without_cache_keys_stays_em_dash(self):
        stages = [StageAttribution(stage="PL", fresh_in=45, cache_creation=None,
                                   cache_read=None, out=10, cost_usd=0.1, arm="with")]
        result = analysis.analyze(_paired_live_record(stages=stages))
        self.assertIsNone(result["paired_tokens"][0]["with_cached"])
        self.assertIn("| PL | 45 | — |", analysis.render_markdown(result))


class CoverageAbsentVsZero(unittest.TestCase):
    """Item 3: an unmeasured (None) coverage arm omits the quality-delta coverage row, so absent
    never reads as a measured 0.0%; a real 0.0 keeps the row."""

    def _record(self, with_cov, without_cov):
        wt = Tokens(input=1000, output=500, total=1500, cache_read=300, cache_creation=100)
        with_pm = PathMetrics(wt, 0.20, 10.0, 400, 10, with_cov, 15, 1, "pass",
                              "benchmark/workdirs/x/with")
        without_pm = PathMetrics(Tokens(input=400, output=200, total=600), 0.10, 5.0, 300, 8,
                                 without_cov, 0, 1, "pass", "benchmark/workdirs/x/without")
        return make_record("r", "t", "live", "s", None, with_pm, without_pm).to_dict()

    def test_absent_coverage_omits_row(self):
        result = analysis.analyze(self._record(None, None))
        self.assertIsNone(result["quality"]["with"]["coverage_pct"])
        self.assertNotIn("| coverage % |", analysis.render_markdown(result))

    def test_measured_zero_keeps_row(self):
        md = analysis.render_markdown(analysis.analyze(self._record(0.0, 0.0)))
        self.assertIn("| coverage % | 0.0% | 0.0% |", md)

    def test_one_measured_arm_keeps_row(self):
        md = analysis.render_markdown(analysis.analyze(self._record(85.0, None)))
        self.assertIn("| coverage % | 85.0% | — |", md)


class FixtureRecord(unittest.TestCase):
    def test_vendored_live_fixture_analyzes_without_error_cross_era_caveat(self):
        with open(_FIXTURE, encoding="utf-8") as f:
            history = json.load(f)
        record = history["live"][0]
        result = analysis.analyze(record)
        self.assertTrue(any("cross-era" in c for c in result["caveats"]))
        md = analysis.render_markdown(result)
        self.assertIn("## totals", md)


if __name__ == "__main__":
    unittest.main()


class EraComparability(unittest.TestCase):
    """Cross-era drift must surface without anyone remembering to pass --reference."""

    def _era(self, harness="python-1", contract="scripted-cli-v1", dv="claude-opus-5"):
        return {"harness": harness, "prompt_contract": contract,
                "model_pins": {"DV": dv, "QA": "claude-sonnet-5"}}

    def test_identical_eras_have_no_differences(self):
        self.assertEqual(analysis.era_differences(self._era(), self._era()), [])

    def test_model_repin_is_named_per_stage(self):
        diffs = analysis.era_differences(self._era(), self._era(dv="claude-opus-6"))
        self.assertEqual(len(diffs), 1)
        self.assertIn("DV", diffs[0])
        self.assertIn("claude-opus-6", diffs[0])

    def test_prompt_contract_change_is_flagged(self):
        diffs = analysis.era_differences(self._era(), self._era(contract="scripted-cli-v2"))
        self.assertTrue(any("prompt_contract" in d for d in diffs))

    def test_missing_era_is_its_own_difference(self):
        self.assertEqual(analysis.era_differences(None, self._era()), ["era-unstamped"])

    def test_unstamped_record_is_caveated(self):
        record = json.loads(json.dumps(_paired_live_record()))
        record.pop("era", None)
        caveats = analysis.analyze(record)["caveats"]
        self.assertTrue(any("unstamped record" in c for c in caveats))

    def test_cross_era_previous_run_is_caveated_without_reference(self):
        current = json.loads(json.dumps(_paired_live_record()))
        current["era"] = self._era()
        previous = json.loads(json.dumps(_paired_live_record()))
        previous["run_id"] = "live-earlier"
        previous["era"] = self._era(dv="claude-opus-4")

        caveats = analysis.analyze(current, previous=previous)["caveats"]
        cross = [c for c in caveats if "cross-era vs previous run" in c]
        self.assertEqual(len(cross), 1, caveats)
        self.assertIn("live-earlier", cross[0])
        self.assertIn("NOT comparable", cross[0])

    def test_same_era_previous_run_is_not_caveated(self):
        current = json.loads(json.dumps(_paired_live_record()))
        current["era"] = self._era()
        previous = json.loads(json.dumps(_paired_live_record()))
        previous["run_id"] = "live-earlier"
        previous["era"] = self._era()

        caveats = analysis.analyze(current, previous=previous)["caveats"]
        self.assertEqual([c for c in caveats if "cross-era vs previous run" in c], [])
