"""benchmark/lib/deterministic_run.py — deterministic dual-path orchestration (DV0d).

Builds BOTH real TTT apps, records REAL metrics, writes a full-schema comparison
BenchmarkRecord, and rotates per-mode latest-3 history. Pure Python so the logic
is unit-testable and run-benchmark.sh stays a thin shell. No network, no live.

CLI:
  python3 -m deterministic_run \
      --workdir <dir> --run-id <id> --timestamp <YYYYmmddTHHMMSSZ> \
      --git-sha <sha> --record <path> --history <path> --runs-dir <dir>
"""

from __future__ import annotations

import argparse
import importlib.util
import os
import sys

_LIB_DIR = os.path.dirname(os.path.abspath(__file__))
BENCHMARK_DIR = os.path.dirname(_LIB_DIR)
sys.path.insert(0, _LIB_DIR)

import metrics  # noqa: E402
import rotation  # noqa: E402


def _load(name: str, path: str):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _iso(ts: str) -> str:
    # YYYYmmddTHHMMSSZ -> YYYY-mm-ddTHH:MM:SSZ
    return f"{ts[:4]}-{ts[4:6]}-{ts[6:8]}T{ts[9:11]}:{ts[11:13]}:{ts[13:15]}Z"


def run(
    *,
    workdir: str,
    run_id: str,
    timestamp: str,
    git_sha: str,
    record_path: str,
    history: str,
    runs_dir: str,
) -> metrics.BenchmarkRecord:
    with_gen = _load("with_gen", os.path.join(BENCHMARK_DIR, "with-plugin", "generate.py"))
    without_gen = _load("without_gen", os.path.join(BENCHMARK_DIR, "without-plugin", "generate.py"))

    try:
        import coverage  # noqa: F401
        measure_cov = True
    except Exception:
        measure_cov = False

    with_pm = with_gen.generate(workdir, measure_cov=measure_cov)
    without_pm = without_gen.generate(workdir, measure_cov=measure_cov)

    rec = metrics.make_record(
        run_id=run_id,
        timestamp_utc=_iso(timestamp),
        mode="deterministic",
        git_sha=git_sha,
        budget_usd=None,
        with_p=with_pm,
        without_p=without_pm,
    )

    os.makedirs(os.path.dirname(record_path), exist_ok=True)
    metrics.write_record(rec, record_path)
    rotation.rotate(history, rec.to_json())
    rotation.rotate_detail(runs_dir, run_id, rec.to_json())
    return rec


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="deterministic_run")
    p.add_argument("--workdir", required=True)
    p.add_argument("--run-id", required=True)
    p.add_argument("--timestamp", required=True)
    p.add_argument("--git-sha", required=True)
    p.add_argument("--record", required=True)
    p.add_argument("--history", required=True)
    p.add_argument("--runs-dir", required=True)
    a = p.parse_args(argv)

    rec = run(
        workdir=a.workdir,
        run_id=a.run_id,
        timestamp=a.timestamp,
        git_sha=a.git_sha,
        record_path=a.record,
        history=a.history,
        runs_dir=a.runs_dir,
    )
    w = rec.paths["with"]
    wo = rec.paths["without"]
    print(f"[benchmark] WITH:    loc={w.loc_produced} tests={w.test_count} "
          f"pass={w.pass_fail} stages={w.stage_count} score={w.estimate_complexity_score}")
    print(f"[benchmark] WITHOUT: loc={wo.loc_produced} tests={wo.test_count} "
          f"pass={wo.pass_fail} stages={wo.stage_count} score={wo.estimate_complexity_score}")
    print(f"[benchmark] record:  {a.record}")
    print(f"[benchmark] history: {a.history}")

    if w.pass_fail != "pass" or wo.pass_fail != "pass":
        print("[benchmark] FAIL: a generated app's tests did not pass", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
