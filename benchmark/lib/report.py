#!/usr/bin/env python3
"""Render benchmark/results/history.json into a self-contained result.html.

Shows ALL metrics (WITH vs WITHOUT + deltas) for every retained run, per mode
(deterministic / live), newest first, plus the filesystem PATH of each generated
Tic-Tac-Toe app so it can be inspected/run directly.

Stdlib only. CLI:
    python3 benchmark/lib/report.py [--history <path>] [--out <path>]
Defaults: history = benchmark/results/history.json, out = benchmark/results/result.html
"""

from __future__ import annotations

import argparse
import html
import json
import os
import sys

_THIS_DIR = os.path.dirname(os.path.abspath(__file__))
_BENCH_DIR = os.path.dirname(_THIS_DIR)
DEFAULT_HISTORY = os.path.join(_BENCH_DIR, "results", "history.json")
DEFAULT_OUT = os.path.join(_BENCH_DIR, "results", "result.html")

# Per-path metric rows: (json accessor, label, is_delta_numeric)
_METRIC_ROWS = [
    ("tokens.input", "tokens in", True),
    ("tokens.output", "tokens out", True),
    ("tokens.total", "tokens total", True),
    ("cost_usd", "cost (USD)", True),
    ("wall_clock_s", "wall clock (s)", True),
    ("loc_produced", "LOC produced", True),
    ("test_count", "test count", True),
    ("coverage_pct", "coverage %", True),
    ("estimate_complexity_score", "complexity score", True),
    ("stage_count", "stage count", True),
    ("tokens.cache_read", "cache read", True),        # NEW raw row (em-dash on legacy)
    ("tokens.cache_creation", "cache creation", True),  # NEW raw row (em-dash on legacy)
    ("pass_fail", "pass/fail", False),
]


def _get(path_metrics: dict, accessor: str):
    if "." in accessor:
        a, b = accessor.split(".", 1)
        return (path_metrics.get(a) or {}).get(b)
    return path_metrics.get(accessor)


def _fmt(v) -> str:
    if v is None:
        return "&mdash;"
    if isinstance(v, bool):
        return "pass" if v else "fail"
    if isinstance(v, float):
        # money/seconds get 4 dp; whole floats stay compact
        return f"{v:,.4f}".rstrip("0").rstrip(".") if v != int(v) else f"{int(v):,}"
    if isinstance(v, int):
        return f"{v:,}"
    return html.escape(str(v))


def _delta(with_v, without_v) -> str:
    if isinstance(with_v, (int, float)) and isinstance(without_v, (int, float)) \
            and not isinstance(with_v, bool) and not isinstance(without_v, bool):
        d = with_v - without_v
        sign = "+" if d > 0 else ""
        return f"{sign}{_fmt(d)}"
    return "&mdash;"


def _app_path(rec: dict, which: str) -> str:
    pm = (rec.get("paths") or {}).get(which) or {}
    p = pm.get("app_path")
    if not p:
        # Convention fallback for records written before app_path existed.
        p = f"benchmark/workdirs/{rec.get('run_id', 'unknown')}/{which}"
    return p


def _num(v):
    """Return v as a number iff it is a real non-bool int/float, else None."""
    if isinstance(v, bool) or not isinstance(v, (int, float)):
        return None
    return v


def _ratio_fmt(v: float) -> str:
    """Format a derived ratio/percentage-free float compactly (2 dp, strip zeros)."""
    return f"{v:,.2f}".rstrip("0").rstrip(".")


def _analysis_rows(rec: dict) -> list[tuple[str, str]]:
    """Derive the analysis rows at render time (q2 — NOT persisted).

    Every row degrades to an em-dash (&mdash;) when its inputs are missing, so the 1
    on-disk live record (no cache fields / no stages) and old deterministic records
    never crash. Rows: input:output ratio, cache-hit %, per-stage token share,
    tokens-per-LOC, WITH-vs-WITHOUT premium.
    """
    with_pm = (rec.get("paths") or {}).get("with") or {}
    without_pm = (rec.get("paths") or {}).get("without") or {}
    wt = with_pm.get("tokens") or {}
    ot = without_pm.get("tokens") or {}

    w_total = _num(wt.get("total"))
    w_out = _num(wt.get("out"))
    w_fresh = _num(wt.get("in"))
    w_cr = _num(wt.get("cache_read"))
    w_cc = _num(wt.get("cache_creation"))
    w_loc = _num(with_pm.get("loc_produced"))
    o_total = _num(ot.get("total"))

    rows: list[tuple[str, str]] = []

    # input:output ratio = total input / output
    if w_total is not None and w_out:
        rows.append(("input:output ratio", f"{_ratio_fmt(w_total / w_out)}:1"))
    else:
        rows.append(("input:output ratio", "&mdash;"))

    # cache-hit % = cache_read / (fresh + cache_creation + cache_read)
    if w_cr is not None and w_cc is not None and w_fresh is not None:
        denom = w_fresh + w_cc + w_cr
        rows.append(
            ("cache-hit %", f"{_ratio_fmt(w_cr / denom * 100)}%" if denom else "&mdash;")
        )
    else:
        rows.append(("cache-hit %", "&mdash;"))

    # per-stage token share = each stage's total input / Σ all stages' total input
    stages = rec.get("stages") or []
    share_parts: list[str] = []
    stage_totals: list[tuple[str, int]] = []
    for s in stages:
        fi = _num(s.get("fresh_in")) or 0
        cc = _num(s.get("cache_creation")) or 0
        cr = _num(s.get("cache_read")) or 0
        stage_totals.append((str(s.get("stage", "?")), fi + cc + cr))
    grand = sum(t for _, t in stage_totals)
    if stage_totals and grand:
        for name, t in stage_totals:
            share_parts.append(f"{html.escape(name)} {_ratio_fmt(t / grand * 100)}%")
        rows.append(("per-stage token share", " &middot; ".join(share_parts)))
    else:
        rows.append(("per-stage token share", "&mdash;"))

    # tokens-per-LOC = total tokens / LOC produced
    if w_total is not None and w_loc:
        rows.append(("tokens per LOC", _ratio_fmt(w_total / w_loc)))
    else:
        rows.append(("tokens per LOC", "&mdash;"))

    # WITH-vs-WITHOUT premium = (with_total - without_total) / without_total
    if w_total is not None and o_total:
        rows.append(
            ("WITH-vs-WITHOUT premium", f"{_ratio_fmt((w_total - o_total) / o_total * 100)}%")
        )
    else:
        rows.append(("WITH-vs-WITHOUT premium", "&mdash;"))

    return rows


def _record_html(rec: dict) -> str:
    run_id = html.escape(str(rec.get("run_id", "?")))
    ts = html.escape(str(rec.get("timestamp_utc", "?")))
    mode = html.escape(str(rec.get("mode", "?")))
    sha = html.escape(str(rec.get("git_sha", "?")))
    budget = rec.get("budget_usd")
    partial = rec.get("live_partial")
    with_pm = (rec.get("paths") or {}).get("with") or {}
    without_pm = (rec.get("paths") or {}).get("without") or {}

    rows = []
    for accessor, label, _num in _METRIC_ROWS:
        wv = _get(with_pm, accessor)
        ov = _get(without_pm, accessor)
        rows.append(
            f"<tr><td class='metric'>{html.escape(label)}</td>"
            f"<td class='with'>{_fmt(wv)}</td>"
            f"<td class='without'>{_fmt(ov)}</td>"
            f"<td class='delta'>{_delta(wv, ov)}</td></tr>"
        )

    badges = f"<span class='badge mode-{mode}'>{mode}</span>"
    if budget is not None:
        badges += f"<span class='badge budget'>budget ${_fmt(budget)}</span>"
    if partial:
        badges += "<span class='badge partial'>live_partial</span>"

    with_app = html.escape(_app_path(rec, "with"))
    without_app = html.escape(_app_path(rec, "without"))

    analysis = [
        f"<tr><td class='metric'>{html.escape(label)}</td>"
        f"<td class='analysis' colspan='3'>{value}</td></tr>"
        for label, value in _analysis_rows(rec)
    ]

    return f"""
    <section class="run">
      <h3>{run_id} {badges}</h3>
      <div class="meta">{ts} &middot; git {sha}</div>
      <table>
        <thead><tr><th>metric</th><th>WITH plugin</th><th>WITHOUT plugin</th><th>&Delta; (with&minus;without)</th></tr></thead>
        <tbody>{''.join(rows)}</tbody>
      </table>
      <table class="analysis-table">
        <thead><tr><th>analysis (derived)</th><th colspan="3">value</th></tr></thead>
        <tbody>{''.join(analysis)}</tbody>
      </table>
      <div class="apps">
        <div><span class="lbl">WITH app:</span> <code>{with_app}</code></div>
        <div><span class="lbl">WITHOUT app:</span> <code>{without_app}</code></div>
      </div>
    </section>"""


_CSS = """
:root { --with:#2563eb; --without:#64748b; --pos:#16a34a; --bg:#0b1020; --card:#141b2e; --fg:#e5e9f0; }
* { box-sizing:border-box; } body { margin:0; font:14px/1.5 -apple-system,Segoe UI,Roboto,sans-serif;
  background:var(--bg); color:var(--fg); padding:24px; }
h1 { font-size:20px; margin:0 0 4px; } h2 { font-size:16px; margin:28px 0 8px; border-bottom:1px solid #26304a; padding-bottom:4px; }
.sub { color:#94a3b8; margin:0 0 20px; }
.run { background:var(--card); border:1px solid #26304a; border-radius:10px; padding:16px; margin:12px 0; }
.run h3 { margin:0 0 2px; font-size:14px; font-family:ui-monospace,Menlo,monospace; }
.meta { color:#94a3b8; font-size:12px; margin-bottom:10px; }
table { width:100%; border-collapse:collapse; }
th,td { text-align:right; padding:5px 10px; border-bottom:1px solid #232c44; }
th:first-child, td.metric { text-align:left; color:#cbd5e1; }
td.with { color:#93b4fb; } td.without { color:#cbd5e1; } td.delta { color:#86efac; font-variant-numeric:tabular-nums; }
td.analysis { color:#fcd34d; text-align:right; font-variant-numeric:tabular-nums; }
.analysis-table { margin-top:8px; } .analysis-table th { color:#fbbf24; }
td { font-variant-numeric:tabular-nums; }
.apps { margin-top:12px; font-size:13px; } .apps .lbl { color:#94a3b8; display:inline-block; width:90px; }
.apps code { background:#0b1224; padding:2px 6px; border-radius:5px; color:#e2e8f0; }
.badge { font-size:11px; padding:2px 7px; border-radius:999px; margin-left:8px; vertical-align:middle; }
.mode-deterministic { background:#1e3a5f; color:#93c5fd; } .mode-live { background:#4a1d3f; color:#f0abfc; }
.budget { background:#3a2f0b; color:#fde047; } .partial { background:#4a1d1d; color:#fca5a5; }
.empty { color:#94a3b8; }
footer { color:#64748b; margin-top:28px; font-size:12px; }
"""


def render_html(history: dict) -> str:
    modes = [m for m in ("deterministic", "live") if history.get(m)]
    body_parts: list[str] = []
    latest_ts = ""
    for mode in modes:
        recs = history.get(mode) or []
        # history stores newest LAST; show newest first.
        body_parts.append(f"<h2>{html.escape(mode)} &mdash; latest {len(recs)}</h2>")
        for rec in reversed(recs):
            latest_ts = latest_ts or str(rec.get("timestamp_utc", ""))
            body_parts.append(_record_html(rec))
    if not body_parts:
        body_parts.append("<p class='empty'>No benchmark results yet. Run <code>make benchmark</code>.</p>")

    asof = html.escape(latest_ts) if latest_ts else "no runs"
    return f"""<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>igrsoft benchmark &mdash; Tic-Tac-Toe with/without plugin</title>
<style>{_CSS}</style></head>
<body>
  <h1>Tic-Tac-Toe benchmark &mdash; WITH vs WITHOUT plugin</h1>
  <p class="sub">All metrics per retained run (latest-3 per mode). As of {asof}. Deterministic tokens/cost are null by design; live fills them.</p>
  {''.join(body_parts)}
  <footer>Generated by benchmark/lib/report.py from benchmark/results/history.json &middot; app paths point to gitignored per-run workdirs.</footer>
</body></html>
"""


def build_report(history_path: str = DEFAULT_HISTORY, out_path: str = DEFAULT_OUT) -> str:
    try:
        with open(history_path, "r", encoding="utf-8") as f:
            history = json.load(f)
    except (OSError, json.JSONDecodeError):
        history = {}
    if not isinstance(history, dict):
        history = {}
    html_text = render_html(history)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(html_text)
    return out_path


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="report.py", description="Render benchmark history to result.html")
    p.add_argument("--history", default=DEFAULT_HISTORY, help="path to history.json")
    p.add_argument("--out", default=DEFAULT_OUT, help="output HTML path")
    args = p.parse_args(argv)
    out = build_report(args.history, args.out)
    print(f"[report] wrote {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
