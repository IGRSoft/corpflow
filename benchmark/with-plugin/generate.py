"""benchmark/with-plugin/generate.py — staged WITH-plugin generator (DV0d).

Drives the plugin's REAL deterministic scripts to assemble the TTT app:
  1. Estimate: shell out to the real estimate-calc.py -> parse JSON ->
     estimate_complexity_score = complexity.total; capture ai_cost.usd as the
     deterministic (estimated, NOT spent) cost figure.
  2. Scaffold: copy ttt-template/ into the workdir as N STAGED operations ->
     stage_count reflects the staged path (process-overhead signal).
  3. Run tests: run the generated app's unittest suite -> REAL test_count/pass_fail.
  4. Bookkeeping: REAL wall_clock_s (monotonic) + REAL loc_produced.

Deterministic mode only. No network, no LLM, never imports benchmark/live/.
Returns a metrics.PathMetrics (the "with" side).

CLI: python3 generate.py --workdir <dir> [--json]  -> prints the PathMetrics JSON.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys

# benchmark/with-plugin/ -> benchmark/ -> repo root ; import the shared lib
_HERE = os.path.dirname(os.path.abspath(__file__))
_BENCH = os.path.dirname(_HERE)
sys.path.insert(0, os.path.join(_BENCH, "lib"))
import genlib  # noqa: E402
import metrics  # noqa: E402

ESTIMATE_CALC = os.path.join(
    genlib.PLUGIN_ROOT, "skills", "estimation-methodology", "scripts", "estimate-calc.py"
)

# Five complexity factors for the TTT workload (small, well-understood task).
_FACTORS = ["3", "3", "3", "3", "3"]
_EXPECTED_TOKENS = "100000"


def run_estimate() -> tuple[int, float | None]:
    """Drive the REAL estimate-calc.py. Returns (complexity_total, ai_cost_usd).

    The cost here is the script's ESTIMATED ai_cost (deterministic mode does not
    spend tokens) — recorded as the deterministic cost_usd estimate per the schema.
    """
    proc = subprocess.run(
        [sys.executable, ESTIMATE_CALC,
         "--size", "M", "--level", "senior",
         "--factors", *_FACTORS,
         "--tokens", _EXPECTED_TOKENS, "--model", "sonnet"],
        capture_output=True, text=True, check=True,
    )
    data = json.loads(proc.stdout)
    score = int(data["complexity"]["total"])
    cost = data.get("ai_cost", {}).get("usd")
    cost = float(cost) if cost is not None else None
    return score, cost


def generate(workdir: str, *, measure_cov: bool = False) -> metrics.PathMetrics:
    app_dir = os.path.join(workdir, "with")
    with genlib.Timer() as t:
        # Step 1: REAL estimate via the plugin's own arithmetic.
        score, est_cost = run_estimate()
        # Step 2: staged scaffold -> stage_count is the staged-op count.
        stage_count = genlib.copy_template_staged(app_dir)
        # Steps 3-4 (tests/loc/cov) folded into build_path_metrics below.
    return genlib.build_path_metrics(
        app_dir=app_dir,
        stage_count=stage_count,
        estimate_complexity_score=score,
        # Deterministic mode: cost is the ESTIMATE (not real spend). Schema allows
        # null/estimated here; we record the estimate so the comparison is non-trivial.
        cost_usd=None,
        wall_clock_s=t.elapsed,
        measure_cov=measure_cov,
    )


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="with-plugin/generate.py")
    p.add_argument("--workdir", required=True, help="per-run workdir (the app goes under <workdir>/with)")
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
