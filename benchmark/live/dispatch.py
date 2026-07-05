#!/usr/bin/env python3
"""benchmark/live/dispatch.py — live full-pipeline dispatch adapter (DV0e).

Reached ONLY via `benchmark/run-benchmark.sh --live` (AC-8). Runs the full worktask
pipeline PL -> AR -> TL -> DV -> DR -> SR -> QA -> DC -> FN -> ST on the generated
TTT app, one stage per headless `claude -p` dispatch, summing REAL tokens/cost,
budget-gated, credential-gated. Writes a full `BenchmarkRecord` (frozen schema,
mode="live") to the `--record <path>` given by the frozen seam.

FROZEN seam argv (DV0d):
    python3 benchmark/live/dispatch.py --workdir <run_id> --budget <usd> --record <path>

Token/cost capture is LAYERED (q4-residual UNRESOLVED -> defensive):
  Layer 1: `claude agents run --output-format json` result `usage` object, IF present
           (check key presence before access; fall through on ANY parse failure).
  Layer 2: `.context/logs/audit.jsonl` `external_dispatch` lines for this run.
  Layer 3: tokens=null + record.live_partial=True. NEVER fabricate tokens/cost.

Budget enforcement:
  (a) pre-flight estimate before stage 1 — projection > budget -> exit non-zero,
      dispatch NOTHING.
  (b) running-tally abort before each stage — spent + next_estimate > budget ->
      abort, write a partial record (pass_fail="fail", live_partial=True).

Credential probe: checked before stage 1 via EITHER source — a non-empty
ANTHROPIC_API_KEY (checked first, cheap short-circuit) OR an active `claude`
CLI login (`claude auth status --json`, machine-login PREFERRED source; see
`credentials.py` module docstring for the OAuth-token/env-override pitfall).
Absent both -> fast exit with the frozen message; neither the key value nor
any CLI-login identity detail is EVER printed/logged/echoed.

DEPENDENCY INJECTION: the real headless `claude -p` call is wrapped behind a
`dispatcher` callable. Production uses `subprocess_dispatcher`. AC-8 tests inject a
fake dispatcher (and a tripwire) so NO real LLM call / spend ever happens in tests.
"""

from __future__ import annotations

import argparse
import functools
import json
import os
import subprocess
import sys
from dataclasses import dataclass

_THIS_DIR = os.path.dirname(os.path.abspath(__file__))
_BENCH_DIR = os.path.dirname(_THIS_DIR)
_PLUGIN_ROOT = os.path.dirname(_BENCH_DIR)

# Make the frozen metrics schema importable without mutating sys.path globally for
# importers — only this module's process needs it.
if os.path.join(_BENCH_DIR, "lib") not in sys.path:
    sys.path.insert(0, os.path.join(_BENCH_DIR, "lib"))

import metrics  # noqa: E402  (frozen DV0d schema)

import preamble  # noqa: E402  (REQ-1 production-faithful prompt assembly)
from credentials import require_credential, CredentialError  # noqa: E402
from budget import (  # noqa: E402
    RunningTally,
    BudgetExceeded,
    assert_preflight_within_budget,
    estimate_stage_cost,
    PIPELINE_STAGES,
)

ESTIMATE_CALC = os.path.join(
    _PLUGIN_ROOT, "skills", "estimation-methodology", "scripts", "estimate-calc.py"
)

# Per-stage dispatch table: stage -> (agent, model_id, effort).
# Models/efforts track skills/shared/stage-codes.md + model-selection.md.
STAGE_TABLE: dict[str, tuple[str, str, str]] = {
    "PL": ("igrsoft:product-manager", "claude-opus-4-8", "high"),
    "AR": ("igrsoft:software-architector", "claude-opus-4-8", "xhigh"),
    "TL": ("igrsoft:team-lead", "claude-sonnet-4-6", "medium"),
    "DV": ("igrsoft:developer", "claude-opus-4-8", "xhigh"),
    "DR": ("igrsoft:technical-lead", "claude-opus-4-8", "xhigh"),
    "SR": ("igrsoft:security-reviewer", "claude-opus-4-8", "xhigh"),
    "QA": ("igrsoft:qa-engineer", "claude-sonnet-4-6", "high"),
    "DC": ("igrsoft:technical-writer", "claude-haiku-4-5", "low"),
    "FN": ("igrsoft:project-manager", "claude-opus-4-8", "medium"),
    "ST": ("igrsoft:stakeholder", "claude-sonnet-4-6", "medium"),
}


@dataclass
class StageUsage:
    """Per-stage captured usage. None fields mean "no real data" (never fabricated)."""

    input_tokens: int | None
    output_tokens: int | None
    cost_usd: float | None
    capture_layer: int | None  # 1, 2, or None (Layer 3 = degraded)
    # NEW additive cache-attribution fields (default None => Layer-3 / legacy safe, and
    # keeps every existing keyword StageUsage(...) construction valid). Sourced from the
    # usage object's cache_read_input_tokens / cache_creation_input_tokens; never fabricated.
    cache_read: int | None = None
    cache_creation: int | None = None


# ---------------------------------------------------------------------------
# Dispatcher seam (injectable). Production = subprocess; tests = fake.
# ---------------------------------------------------------------------------


def build_stage_argv(
    stage: str, *, workdir: str, prompt_path: str
) -> list[str]:
    """Construct the exact headless `claude -p` argv for one stage.

    Shape (RECONCILED q4-residual, was DV0e mandate — see deviations in
    development-0.md): `claude agents run` has NO `--output-format` option on
    this CLI build (verified directly: `claude agents run --help` lists only
    --add-dir/--agent/--all/--cwd/--effort/--json/--mcp-config/--model/
    --permission-mode/--plugin-dir/--settings/--setting-sources/
    --strict-mcp-config — `--json` there means "list active sessions", not a
    per-run output format). Layer-1 JSON `usage` capture is therefore
    UNAVAILABLE on `agents run`.

    Switched to the headless PRINT form, which DOES support the full flag
    surface needed for fidelity + Layer-1 capture:
      claude -p --model <m> --effort <e> --permission-mode default
             --output-format json --agent <agent>
    `--cwd` has no equivalent flag on `-p`; the dispatcher sets the subprocess
    working directory via `subprocess.run(cwd=workdir)` instead (see
    subprocess_dispatcher). `--agent <plugin:name>` resolves the same
    plugin-prefixed agent id `claude agents run -- <agent>` used positionally.
    The stage prompt is fed on stdin (assembled [1][2][3][4][5], REQ-1).
    """
    agent, model, effort = STAGE_TABLE[stage]
    return [
        "claude",
        "-p",
        "--model",
        model,
        "--effort",
        effort,
        "--permission-mode",
        "default",
        "--output-format",
        "json",
        "--agent",
        agent,
    ]


def subprocess_dispatcher(argv: list[str], *, prompt_text: str, workdir: str | None = None) -> str:
    """Production dispatcher: shell out to headless `claude -p`, prompt on stdin.

    `prompt_text` is the FULLY ASSEMBLED [1][2][3][4][5] stage prompt (REQ-1,
    built by `preamble.assemble_stage_prompt` at the run_pipeline read site) —
    NOT a bare `prompts/<stage>.txt` body. Feeding the assembled string here (a
    pure change at the caller) is what makes the live A/B exercise the
    production cache-prefix layout. `workdir`, when given, is passed as the
    subprocess `cwd` — `claude -p` has no `--cwd` flag (q4 remediation).

    Returns the process stdout (`--output-format json` is a real, documented
    flag on `-p`, so Layer 1 parsing is no longer defensive-only for this
    path — Layer 2 audit.jsonl remains the fallback for any CLI variance).
    This is the ONLY place a real LLM call happens, and it is NEVER invoked by
    the AC-8 tests (they inject a fake/tripwire dispatcher).
    """
    completed = subprocess.run(
        argv, input=prompt_text, capture_output=True, text=True, check=False,
        cwd=workdir,
    )
    if completed.returncode != 0:
        raise RuntimeError(
            f"claude -p failed (rc={completed.returncode}) for argv "
            f"{argv[:6]}…"  # never echo the full prompt or any credential
        )
    return completed.stdout


# ---------------------------------------------------------------------------
# Layered usage capture
# ---------------------------------------------------------------------------


def capture_layer1(stdout: str) -> StageUsage | None:
    """Layer 1: parse `--output-format json` result `usage` object IF present.

    Defensive: any JSON error, missing `usage`, or missing token keys -> return None
    so the caller falls through to Layer 2. NEVER fabricates a value.
    """
    try:
        obj = json.loads(stdout)
    except (json.JSONDecodeError, TypeError):
        return None
    if not isinstance(obj, dict):
        return None
    usage = obj.get("usage")
    if not isinstance(usage, dict):
        return None
    in_tok = usage.get("input_tokens")
    out_tok = usage.get("output_tokens")
    cr = usage.get("cache_read_input_tokens")           # NEW: cache-hit input
    cc = usage.get("cache_creation_input_tokens")       # NEW: cache-write input
    # cost may be at result top-level or inside usage depending on CLI version.
    cost = obj.get("total_cost_usd")
    if cost is None:
        cost = usage.get("total_cost_usd")
    # Return None only if NO field carries real data (never fabricate).
    if in_tok is None and out_tok is None and cost is None and cr is None and cc is None:
        return None
    return StageUsage(
        input_tokens=in_tok,
        output_tokens=out_tok,
        cost_usd=float(cost) if cost is not None else None,
        capture_layer=1,
        cache_read=cr,
        cache_creation=cc,
    )


def capture_layer2(audit_path: str, stage: str) -> StageUsage | None:
    """Layer 2: scan audit.jsonl for this stage's `external_dispatch` usage.

    Reads `.context/logs/audit.jsonl`; finds the last `external_dispatch` line whose
    metadata names this stage, and reads any usage it carries. Defensive on every
    line (bad JSON skipped). Returns None when no usable usage is found.
    """
    if not os.path.isfile(audit_path):
        return None
    found: StageUsage | None = None
    try:
        with open(audit_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    rec = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if rec.get("action") != "external_dispatch":
                    continue
                meta = rec.get("metadata") or {}
                if meta.get("stage") != stage:
                    continue
                usage = meta.get("usage") or {}
                in_tok = usage.get("input_tokens")
                out_tok = usage.get("output_tokens")
                cr = usage.get("cache_read_input_tokens")           # NEW
                cc = usage.get("cache_creation_input_tokens")       # NEW
                cost = usage.get("cost_usd", usage.get("total_cost_usd"))
                if (
                    in_tok is None and out_tok is None and cost is None
                    and cr is None and cc is None
                ):
                    continue
                # Keep the latest matching line (overwrite earlier).
                found = StageUsage(
                    input_tokens=in_tok,
                    output_tokens=out_tok,
                    cost_usd=float(cost) if cost is not None else None,
                    capture_layer=2,
                    cache_read=cr,
                    cache_creation=cc,
                )
    except OSError:
        return None
    return found


def capture_stage_usage(stdout: str, *, audit_path: str, stage: str) -> StageUsage:
    """Apply the three capture layers in priority order. Never fabricates.

    Layer 1 (json usage) -> Layer 2 (audit.jsonl) -> Layer 3 (all None, layer=None).
    """
    u = capture_layer1(stdout)
    if u is not None:
        return u
    u = capture_layer2(audit_path, stage)
    if u is not None:
        return u
    # Layer 3: graceful degradation — no real data, flag partial upstream.
    # Never fabricate: cache fields degrade to None alongside tokens/cost.
    return StageUsage(
        input_tokens=None, output_tokens=None, cost_usd=None, capture_layer=None,
        cache_read=None, cache_creation=None,
    )


# ---------------------------------------------------------------------------
# Pipeline run
# ---------------------------------------------------------------------------


def _sum_opt(values: list[int | None]) -> int | None:
    """Sum, treating None as "no data". Returns None iff NO stage reported a value."""
    real = [v for v in values if v is not None]
    return sum(real) if real else None


def _read_task_text(task_path: str) -> str:
    """Read a prompts/<stage>.txt body (preamble section [5], the dynamic task
    text). Isolated helper so the assembled-prompt dispatch replaces the old
    bare-flat-prompt path (AC-1 completeness gate)."""
    with open(task_path, "r", encoding="utf-8") as fh:
        return fh.read()


def _read_state_json_text(workdir_path: str) -> str:
    """Read the workdir's .context/state.json verbatim for preamble section [3].

    Matches production Step 0 (SKILL.md:261-270): the state blob is inlined into
    the prompt as-is. Missing/unreadable -> empty string (F1 legacy fallback: the
    within-stage prefix is still [1]+[2]+[4], just with an empty [3] body).
    """
    state_path = os.path.join(workdir_path, ".context", "state.json")
    try:
        with open(state_path, "r", encoding="utf-8") as f:
            return f.read()
    except OSError:
        return ""


def run_pipeline(
    *,
    workdir_path: str,
    budget: float,
    prompts_dir: str,
    audit_path: str,
    dispatcher,
    estimate_runner=None,
    stages: tuple[str, ...] = PIPELINE_STAGES,
    worktask_id: str = "benchmark-ttt",
    plan_file: str = ".context/planning-0.md",
) -> tuple[list[tuple[str, StageUsage]], bool, int]:
    """Dispatch stages under the running-tally gate.

    Returns (per_stage_usages, live_partial, stages_dispatched), where per_stage_usages
    is a list of (stage_name, StageUsage) so build_live_record can emit per-stage
    attribution (record.stages) with the correct stage labels.
    `dispatcher(argv, prompt_text=...)` -> stdout string (injected). The stage prompt
    is ASSEMBLED (REQ-1) via `preamble.assemble_stage_prompt` from the [1][2][3][4]
    preamble + the prompts/<stage>.txt body ([5]) so the live A/B measures the real
    cache-prefix layout, not a bare flat prompt. `estimate_runner` is forwarded to the
    budget estimator (injected in tests).

    Running-tally gate (b): before each stage, if spent + next_estimate > budget,
    ABORT (do not dispatch the breaching stage) and return what completed so far,
    flagged partial.
    """
    tally = RunningTally(budget)
    usages: list[tuple[str, StageUsage]] = []
    live_partial = False
    dispatched = 0

    # Section [3] is read once per pipeline from the workdir; production re-reads
    # before each delegation, but within one benchmark run the workdir state blob
    # is the app-under-build's state.json (stable across the dispatch loop here).
    state_json_text = _read_state_json_text(workdir_path)

    for stage in stages:
        next_estimate = estimate_stage_cost(
            estimate_calc_path=ESTIMATE_CALC, runner=estimate_runner
        )
        if not tally.can_afford(next_estimate):
            # Gate (b): abort before the breaching dispatch.
            live_partial = True
            break

        prompt_path = os.path.join(prompts_dir, f"{stage.lower()}.txt")
        task_text = _read_task_text(prompt_path)  # section [5] — dynamic body only
        prompt_text = preamble.assemble_stage_prompt(
            stage,
            worktask_id=worktask_id,
            plan_file=plan_file,
            state_json_text=state_json_text,
            task_text=task_text,
        )
        argv = build_stage_argv(
            stage, workdir=workdir_path, prompt_path=prompt_path
        )
        stdout = dispatcher(argv, prompt_text=prompt_text)
        usage = capture_stage_usage(stdout, audit_path=audit_path, stage=stage)
        usages.append((stage, usage))
        dispatched += 1

        if usage.capture_layer is None:
            # Layer 3 degradation on any stage marks the whole record partial.
            live_partial = True
        tally.add(usage.cost_usd)

    return usages, live_partial, dispatched


def build_live_record(
    *,
    run_id: str,
    timestamp_utc: str,
    git_sha: str,
    budget: float,
    usages: list[tuple[str, StageUsage]],
    stages_dispatched: int,
    live_partial: bool,
) -> metrics.BenchmarkRecord:
    """Assemble the live BenchmarkRecord from captured per-stage usage.

    WITH path: real summed tokens/cost (None where unmeasured), plus summed cache_read /
    cache_creation folded onto the WITH Tokens (q5) so report.py can compute cache-hit %
    off paths.with without walking record.stages. tok_total semantics are UNCHANGED
    (= fresh in + out); cache figures are reported separately, never summed into total.
    Also emits per-stage record.stages (q1). WITHOUT path: the baseline single-shot
    (no LLM) — tokens null, cost null, stage_count 1. pass_fail is "fail" when the run is
    partial (aborted/degraded), else "pass".
    """
    stage_usages = [u for _, u in usages]
    in_total = _sum_opt([u.input_tokens for u in stage_usages])
    out_total = _sum_opt([u.output_tokens for u in stage_usages])
    if in_total is None and out_total is None:
        tok_total = None
    else:
        tok_total = (in_total or 0) + (out_total or 0)
    cost_total = _sum_opt([u.cost_usd for u in stage_usages])
    # Fold summed cache totals onto the WITH Tokens (q5). _sum_opt stays None when no
    # stage reported a value, so never-fabricate holds.
    cr_total = _sum_opt([u.cache_read for u in stage_usages])
    cc_total = _sum_opt([u.cache_creation for u in stage_usages])

    # Per-stage attribution (record.stages) — one StageAttribution per dispatched stage.
    stage_attributions = [
        metrics.StageAttribution(
            stage=name,
            fresh_in=u.input_tokens,
            cache_creation=u.cache_creation,
            cache_read=u.cache_read,
            out=u.output_tokens,
            cost_usd=u.cost_usd,
        )
        for name, u in usages
    ]

    with_pass = "fail" if live_partial else "pass"

    with_p = metrics.PathMetrics(
        tokens=metrics.Tokens(
            input=in_total,
            output=out_total,
            total=tok_total,
            cache_read=cr_total,
            cache_creation=cc_total,
        ),
        cost_usd=cost_total,
        wall_clock_s=0.0,  # populated by the harness wrapper in a full live run
        loc_produced=0,
        test_count=0,
        coverage_pct=0.0,
        estimate_complexity_score=0,
        stage_count=stages_dispatched,
        pass_fail=with_pass,
    )
    without_p = metrics.PathMetrics(
        tokens=metrics.Tokens(input=None, output=None, total=None),
        cost_usd=None,
        wall_clock_s=0.0,
        loc_produced=0,
        test_count=0,
        coverage_pct=0.0,
        estimate_complexity_score=0,
        stage_count=1,
        pass_fail="pass",
    )
    return metrics.make_record(
        run_id=run_id,
        timestamp_utc=timestamp_utc,
        mode="live",
        git_sha=git_sha,
        budget_usd=budget,
        with_p=with_p,
        without_p=without_p,
        live_partial=live_partial,
        stages=stage_attributions,
    )


def dispatch(
    *,
    workdir: str,
    budget: float,
    record_path: str,
    dispatcher=subprocess_dispatcher,
    env: dict[str, str] | None = None,
    estimate_runner=None,
    prompts_dir: str | None = None,
    stages: tuple[str, ...] = PIPELINE_STAGES,
    cli_login_runner=None,
) -> int:
    """Run the full live pipeline end-to-end and write the BenchmarkRecord.

    Returns a process exit code (0 = ok, non-zero = declined/failed). Order:
      1. credential probe (fast-exit, never logs key or CLI-login identity)
      2. pre-flight budget gate (dispatch nothing on breach)
      3. per-stage running-tally dispatch (partial record on abort/degradation)
      4. write the record JSON to record_path

    All external effects (LLM call) go through `dispatcher`, which tests replace.
    `cli_login_runner` (Batch 1c) is forwarded to the credential probe's second
    source (`claude auth status --json`); tests inject a fake so the suite never
    shells out even for that read-only status query.
    """
    workdir_path = os.path.join(_BENCH_DIR, "workdirs", workdir)
    audit_path = os.path.join(workdir_path, ".context", "logs", "audit.jsonl")
    if prompts_dir is None:
        prompts_dir = os.path.join(_THIS_DIR, "prompts")

    run_id = workdir  # the seam passes run_id as --workdir
    timestamp_utc = _now_iso()
    git_sha = _git_sha()

    # When the caller did not inject a fake, bind the real subprocess dispatcher
    # to this run's workdir (claude -p has no --cwd flag; cwd is a subprocess
    # kwarg — q4 remediation). Injected fakes are left untouched (2-arg contract).
    if dispatcher is subprocess_dispatcher:
        dispatcher = functools.partial(subprocess_dispatcher, workdir=workdir_path)

    # 1. Credential probe — before ANY dispatch. Never reveals the key or any
    #    CLI-login identity field (email/org) — only presence is ever checked.
    try:
        require_credential(env, cli_login_runner=cli_login_runner)
    except CredentialError as exc:
        print(str(exc), file=sys.stderr)
        return 3

    # 2. Pre-flight budget gate — dispatch nothing if the projection breaches.
    try:
        assert_preflight_within_budget(
            budget=budget,
            stage_count=len(stages),
            estimate_calc_path=ESTIMATE_CALC,
            runner=estimate_runner,
        )
    except BudgetExceeded as exc:
        print(str(exc), file=sys.stderr)
        return 2

    # 3. Per-stage dispatch under the running-tally gate.
    usages, live_partial, dispatched = run_pipeline(
        workdir_path=workdir_path,
        budget=budget,
        prompts_dir=prompts_dir,
        audit_path=audit_path,
        dispatcher=dispatcher,
        estimate_runner=estimate_runner,
        stages=stages,
    )

    # 4. Write the record (full schema, mode="live"). Partial runs still write.
    record = build_live_record(
        run_id=run_id,
        timestamp_utc=timestamp_utc,
        git_sha=git_sha,
        budget=budget,
        usages=usages,
        stages_dispatched=dispatched,
        live_partial=live_partial,
    )
    os.makedirs(os.path.dirname(record_path), exist_ok=True)
    metrics.write_record(record, record_path)

    if live_partial:
        print(
            f"live run partial: {dispatched}/{len(stages)} stages; "
            f"record written to {record_path}",
            file=sys.stderr,
        )
        return 4  # non-zero: aborted/degraded, but the partial record is on disk
    return 0


# ---------------------------------------------------------------------------
# Small env helpers (kept here so the module is import-light)
# ---------------------------------------------------------------------------


def _now_iso() -> str:
    import datetime

    return (
        datetime.datetime.now(datetime.timezone.utc)
        .strftime("%Y-%m-%dT%H:%M:%SZ")
    )


def _git_sha() -> str:
    try:
        out = subprocess.run(
            ["git", "-C", _PLUGIN_ROOT, "rev-parse", "--short=7", "HEAD"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()
        return out or "nogit"
    except (subprocess.SubprocessError, OSError):
        return "nogit"


def _parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(
        prog="dispatch.py",
        description="Live full-pipeline dispatch adapter (opt-in, --live only).",
    )
    p.add_argument("--workdir", required=True, help="run_id / workdir name")
    p.add_argument("--budget", required=True, type=float, help="USD budget cap")
    p.add_argument(
        "--record", required=True, help="absolute path for the BenchmarkRecord JSON"
    )
    return p.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(argv)
    return dispatch(
        workdir=args.workdir,
        budget=args.budget,
        record_path=args.record,
    )


if __name__ == "__main__":
    sys.exit(main())
