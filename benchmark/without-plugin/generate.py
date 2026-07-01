"""benchmark/without-plugin/generate.py — single-shot baseline generator (DV0d).

The WITHOUT-plugin path: no estimation, no staging, no review.
  - estimate_complexity_score = 0
  - stage_count = 1 (one single-shot copy)
Writes the SAME ttt-template/ directly into the workdir in one operation, then
runs the generated app's unittest suite and records REAL test_count/pass_fail,
loc_produced, and wall_clock_s.

Deterministic mode only. No network, no LLM, never imports benchmark/live/.
Returns a metrics.PathMetrics (the "without" side).

CLI: python3 generate.py --workdir <dir> [--json]  -> prints the PathMetrics JSON.
"""

from __future__ import annotations

import argparse
import json
import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
_BENCH = os.path.dirname(_HERE)
sys.path.insert(0, os.path.join(_BENCH, "lib"))
import genlib  # noqa: E402
import metrics  # noqa: E402


def generate(workdir: str, *, measure_cov: bool = False) -> metrics.PathMetrics:
    app_dir = os.path.join(workdir, "without")
    with genlib.Timer() as t:
        # Single-shot: one copy operation, no estimate, no staging.
        stage_count = genlib.copy_template_single_shot(app_dir)  # == 1
    return genlib.build_path_metrics(
        app_dir=app_dir,
        stage_count=stage_count,
        estimate_complexity_score=0,
        cost_usd=None,
        wall_clock_s=t.elapsed,
        measure_cov=measure_cov,
    )


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="without-plugin/generate.py")
    p.add_argument("--workdir", required=True, help="per-run workdir (the app goes under <workdir>/without)")
    p.add_argument("--coverage", action="store_true", help="measure per-app coverage_pct (needs coverage.py)")
    p.add_argument("--json", action="store_true", help="print the PathMetrics as JSON")
    args = p.parse_args(argv)
    os.makedirs(args.workdir, exist_ok=True)
    pm = generate(args.workdir, measure_cov=args.coverage)
    if args.json:
        print(json.dumps(pm.to_json(), indent=2))
    return 0 if pm.pass_fail == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
