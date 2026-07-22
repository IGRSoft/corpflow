"""Offline analysis over a single BenchmarkRecord dict (AC-8: no subprocess, no
benchmarklive import — pure, operates on the parsed JSON shape metrics.py emits).

``analyze`` derives totals/premium, per-stage cost/token/cache shares, cache
economics, a quality delta, and MECHANICAL outlier flags (threshold-based, never
a judgment call) plus validity caveats (partial run, placeholder WITHOUT arm,
cross-era token payload, single-sample). ``render_markdown`` renders that dict,
closing with an ``## improvement-candidates`` checklist built strictly from the
outlier flags — no fabricated recommendations.
"""

from __future__ import annotations

from typing import Optional

_OUTLIER_FACTOR = 1.5


def _num(v):
    if isinstance(v, bool):
        return None
    return v if isinstance(v, (int, float)) else None


def _median(values: list) -> Optional[float]:
    vals = sorted(values)
    n = len(vals)
    if n == 0:
        return None
    mid = n // 2
    return vals[mid] if n % 2 else (vals[mid - 1] + vals[mid]) / 2.0


def _totals(comparison: dict) -> dict:
    out = {}
    for key in ("tokens_total", "cost_usd"):
        entry = comparison.get(key)
        if not isinstance(entry, dict):
            out[key] = None
            continue
        w = _num(entry.get("with"))
        wo = _num(entry.get("without"))
        d = _num(entry.get("delta"))
        premium = (d / wo * 100.0) if (d is not None and wo not in (None, 0)) else None
        out[key] = {"with": w, "without": wo, "delta": d, "premium_pct": premium}
    return out


def _stage_rows(stages: list) -> list:
    total_cost = sum(_num(s.get("cost_usd")) or 0 for s in stages)
    total_out = sum(_num(s.get("out")) or 0 for s in stages)
    rows = []
    for s in stages:
        cost = _num(s.get("cost_usd"))
        out_tok = _num(s.get("out"))
        fresh_in = _num(s.get("fresh_in")) or 0
        cache_creation = _num(s.get("cache_creation")) or 0
        cache_read = _num(s.get("cache_read")) or 0
        denom = fresh_in + cache_creation + cache_read
        cache_hit = (cache_read / denom * 100.0) if denom > 0 else None
        cost_share = (cost / total_cost * 100.0) if (cost is not None and total_cost) else None
        out_share = (out_tok / total_out * 100.0) if (out_tok is not None and total_out) else None
        cov = s.get("coverage") if isinstance(s.get("coverage"), dict) else {}
        rows.append({
            "stage": s.get("stage") or "?",
            "cost_usd": cost,
            "cost_share_pct": cost_share,
            "out_tokens": out_tok,
            "out_token_share_pct": out_share,
            "cache_hit_pct": cache_hit,
            "cache_creation": cache_creation,
            "tool_calls": _num(cov.get("tool_calls")),
            "nested_background": _num(cov.get("nested_background")) or 0,
        })
    return rows


_TOOL_CALL_FLOOR = 40


def _paired_tokens(stages: list) -> list:
    """Per-stage WITH-vs-WITHOUT in/out token rows (U5). Empty unless stage rows carry
    an ``arm`` tag (the paired path); order follows first WITH-arm appearance."""
    by_stage: dict = {}
    order: list = []
    for s in stages:
        arm = s.get("arm")
        if arm not in ("with", "without"):
            continue
        name = s.get("stage") or "?"
        if name not in by_stage:
            by_stage[name] = {"stage": name, "with_in": None, "with_out": None,
                              "without_in": None, "without_out": None}
            order.append(name)
        by_stage[name][f"{arm}_in"] = _num(s.get("fresh_in"))
        by_stage[name][f"{arm}_out"] = _num(s.get("out"))
    return [by_stage[n] for n in order]


def scan_generated_project(arm_dir: str) -> Optional[dict]:
    """Walk an arm folder for generated *.swift (U2): per-file LOC, total LOC, path.
    Returns None when the folder is absent or holds no Swift outside build dirs."""
    import os

    if not os.path.isdir(arm_dir):
        return None
    ignore = {".build", ".swiftpm", ".context"}
    files = []
    for root, dirs, names in os.walk(arm_dir):
        dirs[:] = [d for d in dirs if d not in ignore]
        for name in sorted(names):
            if not name.endswith(".swift"):
                continue
            full = os.path.join(root, name)
            try:
                with open(full, encoding="utf-8") as f:
                    text = f.read()
            except OSError:
                continue
            loc = sum(1 for ln in text.split("\n")
                      if ln.strip() and not ln.strip().startswith("//"))
            files.append((os.path.relpath(full, arm_dir), loc))
    if not files:
        return None
    files.sort()
    return {"path": arm_dir, "files": files, "total_loc": sum(loc for _, loc in files)}


def generated_projects(record: dict, workdirs_root: Optional[str]) -> dict:
    """Per-arm generated-project scans keyed by arm name; empty when no root given."""
    import os

    if not workdirs_root:
        return {}
    run_id = record.get("run_id") or ""
    out = {}
    for arm in ("with", "without"):
        scan = scan_generated_project(os.path.join(workdirs_root, run_id, arm))
        if scan is not None:
            out[arm] = scan
    return out


def _cache_top(stages: list, top_n: int = 5) -> list:
    entries = [(s.get("stage") or "?", _num(s.get("cache_creation")) or 0) for s in stages]
    entries = [e for e in entries if e[1] > 0]
    entries.sort(key=lambda e: e[1], reverse=True)
    return [{"stage": name, "cache_creation": val} for name, val in entries[:top_n]]


def _arm_quality(pm: dict) -> dict:
    tokens = pm.get("tokens") or {}
    loc = _num(pm.get("loc_produced"))
    tok_total = _num(tokens.get("total"))
    tpl = (tok_total / loc) if (tok_total is not None and loc not in (None, 0)) else None
    return {
        "loc_produced": pm.get("loc_produced"),
        "test_count": pm.get("test_count"),
        "pass_fail": pm.get("pass_fail"),
        "tokens_per_loc": tpl,
    }


def _outliers(stages: list, with_pm: dict, without_pm: dict) -> list:
    flags = []

    costs = [(_num(s.get("cost_usd")), s.get("stage") or "?") for s in stages]
    costs = [(c, name) for c, name in costs if c is not None]
    median_cost = _median([c for c, _ in costs])
    if median_cost:
        for c, name in costs:
            if c > _OUTLIER_FACTOR * median_cost:
                flags.append({
                    "type": "stage_cost_outlier", "stage": name,
                    "detail": f"cost ${c:.4f} is {c / median_cost:.2f}x the per-stage "
                             f"median (${median_cost:.4f})",
                })

    outs = [(_num(s.get("out")), s.get("stage") or "?") for s in stages]
    outs = [(o, name) for o, name in outs if o is not None]
    median_out = _median([o for o, _ in outs])
    if median_out:
        for o, name in outs:
            if o > _OUTLIER_FACTOR * median_out:
                flags.append({
                    "type": "out_token_spike", "stage": name,
                    "detail": f"out-tokens {o} is {o / median_out:.2f}x the per-stage "
                             f"median ({median_out:.0f})",
                })

    for label, pm in (("with", with_pm), ("without", without_pm)):
        if pm.get("pass_fail") == "fail":
            flags.append({
                "type": "missing_app_verdict", "stage": label,
                "detail": f"{label} arm pass_fail=fail (no verified app / failing tests)",
            })

    for s in stages:
        if s.get("cost_usd") is None and s.get("fresh_in") is None and s.get("out") is None:
            flags.append({
                "type": "degraded_capture", "stage": s.get("stage") or "?",
                "detail": "no usage captured for this stage (Layer-3 degradation)",
            })

    def _tool_calls(s):
        cov = s.get("coverage") if isinstance(s.get("coverage"), dict) else {}
        return _num(cov.get("tool_calls"))

    tcs = [(_tool_calls(s), s.get("stage") or "?") for s in stages]
    tcs = [(t, name) for t, name in tcs if t is not None]
    median_tc = _median([t for t, _ in tcs])
    threshold = max(_TOOL_CALL_FLOOR, _OUTLIER_FACTOR * median_tc) if median_tc else _TOOL_CALL_FLOOR
    for t, name in tcs:
        if t > threshold:
            flags.append({
                "type": "tool_call_spike", "stage": name,
                "detail": f"{t} tool calls exceeds max(40, 1.5x median) = {threshold:.0f}",
            })

    for s in stages:
        cov = s.get("coverage") if isinstance(s.get("coverage"), dict) else {}
        nested = _num(cov.get("nested_background")) or 0
        if nested > 0:
            flags.append({
                "type": "background_nested_spawn", "stage": s.get("stage") or "?",
                "detail": f"{nested} nested background subagent spawn(s) recorded",
            })

    return flags


def _is_placeholder_without(pm: dict) -> bool:
    tokens = pm.get("tokens") or {}
    return (tokens.get("total") is None and pm.get("cost_usd") is None
            and pm.get("wall_clock_s") == 0.0 and pm.get("pass_fail") == "pass"
            and pm.get("stage_count") == 1)


def _is_cross_era(pm: dict) -> bool:
    tokens = pm.get("tokens") or {}
    return (tokens.get("total") is not None
            and tokens.get("cache_read") is None and tokens.get("cache_creation") is None)


def _caveats(record: dict, with_pm: dict, without_pm: dict, reference: Optional[dict]) -> list:
    caveats = []
    if record.get("live_partial"):
        caveats.append(
            "live_partial: this run degraded or breached budget mid-flight; "
            "treat metrics as incomplete.")
    if _is_placeholder_without(without_pm):
        caveats.append(
            "WITHOUT arm is the mechanism-default placeholder (never dispatched); "
            "premium/delta figures are unavailable for this run.")
    if _is_cross_era(with_pm) or _is_cross_era(without_pm):
        caveats.append(
            "cross-era record: token payload predates cache_read/cache_creation "
            "tracking; cache-hit and cache-economics figures are unavailable for "
            "the affected arm.")
    caveats.append(
        "n=1: single-run comparison; treat deltas as directional, not statistically robust.")
    if reference is not None:
        ref_sha = reference.get("git_sha")
        cur_sha = record.get("git_sha")
        if ref_sha and cur_sha and ref_sha != cur_sha:
            caveats.append(
                f"cross-era reference: comparing against git_sha {ref_sha} (current "
                f"{cur_sha}); wall-clock deltas across harness generations are not "
                "valid (see README wall-clock boundary note).")
    return caveats


def analyze(record: dict, reference: Optional[dict] = None,
            workdirs_root: Optional[str] = None) -> dict:
    """Pure derivation over one parsed BenchmarkRecord dict. Never fabricates a
    value absent from the record — every None/omission flows through as None.
    ``workdirs_root`` opts into the per-arm generated-project scan (U2)."""
    paths = record.get("paths") or {}
    with_pm = paths.get("with") or {}
    without_pm = paths.get("without") or {}
    comparison = record.get("comparison") or {}
    stages = record.get("stages") or []

    return {
        "run_id": record.get("run_id") or "?",
        "mode": record.get("mode") or "?",
        "timestamp_utc": record.get("timestamp_utc") or "?",
        "totals": _totals(comparison),
        "stages": _stage_rows(stages),
        "paired_tokens": _paired_tokens(stages),
        "cache_top": _cache_top(stages),
        "quality": {"with": _arm_quality(with_pm), "without": _arm_quality(without_pm)},
        "outliers": _outliers(stages, with_pm, without_pm),
        "caveats": _caveats(record, with_pm, without_pm, reference),
        "generated": generated_projects(record, workdirs_root),
    }


def _fmt(v) -> str:
    if v is None:
        return "—"
    if isinstance(v, float):
        if v == round(v):
            return str(int(v))
        return f"{v:.4f}".rstrip("0").rstrip(".")
    return str(v)


def _pct(v: Optional[float]) -> str:
    return f"{v:.1f}%" if v is not None else "—"


def render_markdown(analysis: dict) -> str:
    lines = [
        f"# Benchmark Analysis — {analysis['run_id']} ({analysis['mode']})",
        "",
        f"_as of {analysis.get('timestamp_utc', '?')}_",
        "",
        "## totals",
        "",
        "| metric | WITH | WITHOUT | Δ | premium % |",
        "|---|---|---|---|---|",
    ]
    for key, label in (("tokens_total", "tokens total"), ("cost_usd", "cost (USD)")):
        entry = analysis["totals"].get(key)
        if entry is None:
            lines.append(f"| {label} | — | — | — | — |")
            continue
        premium = f"{entry['premium_pct']:.1f}%" if entry["premium_pct"] is not None else "—"
        lines.append(
            f"| {label} | {_fmt(entry['with'])} | {_fmt(entry['without'])} | "
            f"{_fmt(entry['delta'])} | {premium} |")

    lines += ["", "## per-stage", ""]
    if analysis["stages"]:
        lines.append("| stage | cost (USD) | cost share % | out tokens | out share % | "
                     "cache-hit % | tool calls |")
        lines.append("|---|---|---|---|---|---|---|")
        for row in analysis["stages"]:
            lines.append(
                f"| {row['stage']} | {_fmt(row['cost_usd'])} | {_pct(row['cost_share_pct'])} | "
                f"{_fmt(row['out_tokens'])} | {_pct(row['out_token_share_pct'])} | "
                f"{_pct(row['cache_hit_pct'])} | {_fmt(row.get('tool_calls'))} |")
    else:
        lines.append("_no per-stage attribution on this record._")

    if analysis.get("paired_tokens"):
        lines += ["", "## paired-tokens", "",
                  "| stage | WITH in | WITH out | WITHOUT in | WITHOUT out |",
                  "|---|---|---|---|---|"]
        for row in analysis["paired_tokens"]:
            lines.append(
                f"| {row['stage']} | {_fmt(row['with_in'])} | {_fmt(row['with_out'])} | "
                f"{_fmt(row['without_in'])} | {_fmt(row['without_out'])} |")

    lines += ["", "## cache-economics", ""]
    if analysis["cache_top"]:
        lines.append("| stage | cache_creation |")
        lines.append("|---|---|")
        for row in analysis["cache_top"]:
            lines.append(f"| {row['stage']} | {_fmt(row['cache_creation'])} |")
    else:
        lines.append("_no cache-creation activity recorded._")

    qw, qo = analysis["quality"]["with"], analysis["quality"]["without"]
    lines += [
        "", "## quality-delta", "",
        "| metric | WITH | WITHOUT |",
        "|---|---|---|",
        f"| loc_produced | {_fmt(qw['loc_produced'])} | {_fmt(qo['loc_produced'])} |",
        f"| test_count | {_fmt(qw['test_count'])} | {_fmt(qo['test_count'])} |",
        f"| pass_fail | {qw['pass_fail'] or '—'} | {qo['pass_fail'] or '—'} |",
        f"| tokens per LOC | {_fmt(qw['tokens_per_loc'])} | {_fmt(qo['tokens_per_loc'])} |",
    ]

    lines += ["", "## validity-caveats", ""]
    if analysis["caveats"]:
        lines += [f"- {c}" for c in analysis["caveats"]]
    else:
        lines.append("_none._")

    generated = analysis.get("generated") or {}
    if generated:
        lines += ["", "## generated-project", ""]
        for arm in ("with", "without"):
            proj = generated.get(arm)
            if proj is None:
                continue
            lines.append(f"### {arm} arm — `{proj['path']}`")
            lines.append(f"_total LOC: {proj['total_loc']}_")
            lines.append("")
            lines.append("| file | LOC |")
            lines.append("|---|---|")
            for rel, loc in proj["files"]:
                lines.append(f"| {rel} | {loc} |")
            lines.append("")

    lines += ["", "## improvement-candidates", ""]
    if analysis["outliers"]:
        lines += [f"- [ ] ({flag['type']}) {flag['stage']}: {flag['detail']}"
                  for flag in analysis["outliers"]]
    else:
        lines.append("_no mechanical outliers flagged on this record._")
    lines.append("")

    return "\n".join(lines)
