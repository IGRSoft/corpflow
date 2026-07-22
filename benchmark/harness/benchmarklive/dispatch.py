"""Live full-pipeline dispatch adapter.

Reached ONLY via bench-live (AC-8). Runs PL→AR→TL→DV→DR→SR→QA→DC→FN→ST (SR IS in
the live pipeline, AR delta D3), one stage per headless `claude -p`, summing REAL
tokens/cost, budget-gated, credential-gated. The real dispatch is behind the
Dispatching protocol; tests inject fakes/tripwires so NO real LLM call / spend ever
happens. Exit codes: 0 ok / 2 pre-flight decline / 3 no credential / 4 running-tally
breach or degradation (partial record written FIRST, D6). D6/OI-2: after each stage a
partial record is flushed atomically so a crash loses at most the in-flight stage.

WITHOUT arm (D1-D7): an optional single-shot baseline dispatched FIRST (before any
WITH stage) so a later budget breach still leaves a real comparison point on disk;
mechanism default ``without_arm="skip"`` keeps every pre-existing caller byte-stable.
"""

from __future__ import annotations

import json
import os
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Callable, Optional, Protocol

from benchmarkkit.genlib import Subprocess, Timer
from benchmarkkit.metrics import (
    BenchmarkRecord,
    PathMetrics,
    StageAttribution,
    StageCoverage,
    Tokens,
    make_record,
    write_record,
)

from . import baseline as baseline_mod
from . import budget as budget_mod
from . import capture, preamble

# Per-stage dispatch table: stage -> (agent, model_id, effort).
STAGE_TABLE = {
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

CAPTURE_JSON = "json"
CAPTURE_STREAM_JSON = "stream-json"

# Production dispatcher per-stage ceiling (D5); a hung child never blocks a run forever.
STAGE_TIMEOUT_S = 3600.0


@dataclass
class StageUsage:
    input_tokens: Optional[int] = None
    output_tokens: Optional[int] = None
    cost_usd: Optional[float] = None
    capture_layer: Optional[int] = None  # 1, 2, or None (Layer 3 = degraded)
    cache_read: Optional[int] = None
    cache_creation: Optional[int] = None
    coverage: Optional[StageCoverage] = None
    duration_s: float = 0.0  # wall-clock of this dispatch; not part of the on-disk schema


class Dispatching(Protocol):
    def run(self, argv: list, prompt_text: str) -> str:
        ...


class DispatchFailure(Exception):
    pass


class SubprocessDispatcher:
    """Production dispatcher: shell out to headless `claude -p`, prompt on stdin."""

    def __init__(self, workdir: Optional[str] = None, timeout: Optional[float] = STAGE_TIMEOUT_S) -> None:
        self.workdir = workdir
        self.timeout = timeout

    def run(self, argv: list, prompt_text: str) -> str:
        r = Subprocess.run(argv, cwd=self.workdir, input=prompt_text, timeout=self.timeout)
        if r.exit_code != 0:
            snippet = r.stderr.strip()[:400]
            raise DispatchFailure(
                f"claude -p failed (rc={r.exit_code}) for argv {argv[:6]}…"
                + (f" stderr: {snippet}" if snippet else "")
            )
        return r.stdout


def build_stage_argv(stage: str, capture_mode: str = CAPTURE_JSON) -> list:
    """Frozen headless `claude -p` argv (AR ad2). stream-json appends --verbose."""
    entry = STAGE_TABLE.get(stage)
    if entry is None:
        return []
    agent, model, effort = entry
    argv = ["claude", "-p", "--model", model, "--effort", effort,
            "--permission-mode", "default", "--output-format", capture_mode,
            "--agent", agent]
    if capture_mode == CAPTURE_STREAM_JSON:
        argv.append("--verbose")
    return argv


def capture_layer2(audit_path: str, stage: str) -> Optional[StageUsage]:
    """Layer 2: scan audit.jsonl for this stage's last external_dispatch usage."""
    try:
        with open(audit_path, encoding="utf-8") as f:
            text = f.read()
    except OSError:
        return None
    found = None
    for line in text.split("\n"):
        if not line.strip():
            continue
        try:
            rec = json.loads(line)
        except (ValueError, TypeError):
            continue
        if not isinstance(rec, dict) or rec.get("action") != "external_dispatch":
            continue
        meta = rec.get("metadata")
        if not isinstance(meta, dict) or meta.get("stage") != stage:
            continue
        usage = meta.get("usage") or {}
        in_tok = usage.get("input_tokens")
        out_tok = usage.get("output_tokens")
        cr = usage.get("cache_read_input_tokens")
        cc = usage.get("cache_creation_input_tokens")
        cost = usage.get("cost_usd")
        if cost is None:
            cost = usage.get("total_cost_usd")
        if in_tok is None and out_tok is None and cost is None and cr is None and cc is None:
            continue
        found = StageUsage(input_tokens=in_tok, output_tokens=out_tok, cost_usd=cost,
                           capture_layer=2, cache_read=cr, cache_creation=cc)
    return found


def capture_stage_usage(stdout: str, audit_path: str, stage: str) -> StageUsage:
    """Layer 1 (stdout) → Layer 2 (audit.jsonl) → Layer 3 (all None). Never fabricates."""
    parsed = capture.parse(stdout)
    if parsed is not None and parsed.has_usage:
        return StageUsage(input_tokens=parsed.input_tokens, output_tokens=parsed.output_tokens,
                          cost_usd=parsed.cost_usd, capture_layer=1,
                          cache_read=parsed.cache_read, cache_creation=parsed.cache_creation,
                          coverage=parsed.coverage)
    layer2 = capture_layer2(audit_path, stage)
    if layer2 is not None:
        layer2.coverage = parsed.coverage if parsed else None
        return layer2
    return StageUsage(capture_layer=None, coverage=parsed.coverage if parsed else None)


def _sum_opt(values: list):
    real = [v for v in values if v is not None]
    return sum(real) if real else None


def _tok_total(input_tokens: Optional[int], output_tokens: Optional[int]) -> Optional[int]:
    if input_tokens is None and output_tokens is None:
        return None
    return (input_tokens or 0) + (output_tokens or 0)


def read_state_json_text(workdir_path: str) -> str:
    try:
        with open(os.path.join(workdir_path, ".context", "state.json"), encoding="utf-8") as f:
            return f.read()
    except OSError:
        return ""


@dataclass
class PipelineResult:
    usages: list
    live_partial: bool
    dispatched: int


@dataclass
class BaselineResult:
    mode: str
    usage: Optional[StageUsage] = None
    duration_s: float = 0.0
    dispatched: bool = False
    partial: bool = False


def run_baseline(prompts_dir: str, dispatcher: Dispatching, tally: "budget_mod.RunningTally",
                 mode: str, audit_path: str, estimate_calc_path: str,
                 estimate_runner: Optional[Callable[[list], str]] = None,
                 capture_mode: str = CAPTURE_JSON) -> BaselineResult:
    """Dispatch the single-shot WITHOUT baseline (D1/D3). A policy skip (``mode`` is
    not ``ARM_REAL``) never touches the dispatcher or the tally. The running-tally
    gate mirrors the per-stage check in ``run_pipeline``; only ``DispatchFailure`` is
    tolerated here — the WITH pipeline still runs even when the baseline fails.
    """
    if mode != baseline_mod.ARM_REAL:
        return BaselineResult(mode=mode)

    next_estimate = budget_mod.estimate_stage_cost(estimate_calc_path, runner=estimate_runner)
    if not tally.can_afford(next_estimate):
        return BaselineResult(mode=mode, partial=True)

    argv = baseline_mod.build_without_argv(capture_mode)
    prompt_text = baseline_mod.load_without_prompt(prompts_dir)
    timer = Timer()
    timer.start()
    try:
        stdout = dispatcher.run(argv, prompt_text)
    except DispatchFailure:
        return BaselineResult(mode=mode, dispatched=True, duration_s=timer.elapsed, partial=True)

    duration = timer.elapsed
    usage = capture_stage_usage(stdout, audit_path, "WITHOUT")
    usage.duration_s = duration
    degraded = usage.capture_layer is None
    tally.add(usage.cost_usd)
    return BaselineResult(mode=mode, usage=usage, duration_s=duration, dispatched=True, partial=degraded)


def run_pipeline(workdir_path: str, budget: float, prompts_dir: str, audit_path: str,
                 dispatcher: Dispatching, estimate_calc_path: str,
                 estimate_runner: Optional[Callable[[list], str]] = None,
                 stages: Optional[list] = None, worktask_id: str = "benchmark-ttt",
                 plan_file: str = ".context/planning-0.md", capture_mode: str = CAPTURE_JSON,
                 persist_partial: Optional[Callable[[list, int], None]] = None,
                 tally: Optional["budget_mod.RunningTally"] = None) -> PipelineResult:
    """Dispatch stages under the running-tally gate. Gate (b): abort before the
    breaching dispatch. OI-2: flush a partial after each completed stage. ``tally``
    may be shared with a preceding WITHOUT-arm dispatch so its spend counts too.
    """
    stages = stages if stages is not None else budget_mod.PIPELINE_STAGES
    tally = tally if tally is not None else budget_mod.RunningTally(budget)
    usages: list = []
    live_partial = False
    dispatched = 0
    state_json_text = read_state_json_text(workdir_path)

    for stage in stages:
        next_estimate = budget_mod.estimate_stage_cost(estimate_calc_path, runner=estimate_runner)
        if not tally.can_afford(next_estimate):
            live_partial = True
            break

        # Missing prompt file is a hard error (never silently dispatch an empty [5]).
        prompt_path = os.path.join(prompts_dir, f"{stage.lower()}.txt")
        with open(prompt_path, encoding="utf-8") as f:
            task_text = f.read()
        prompt_text = preamble.assemble_stage_prompt(
            stage, worktask_id=worktask_id, plan_file=plan_file,
            state_json_text=state_json_text, task_text=task_text)
        argv = build_stage_argv(stage, capture_mode=capture_mode)
        timer = Timer()
        timer.start()
        # A throw here propagates with the prior stages' partial ALREADY on disk (OI-2).
        stdout = dispatcher.run(argv, prompt_text)
        usage = capture_stage_usage(stdout, audit_path, stage)
        usage.duration_s = timer.elapsed
        usages.append((stage, usage))
        dispatched += 1
        if usage.capture_layer is None:
            live_partial = True
        tally.add(usage.cost_usd)

        if persist_partial is not None:
            persist_partial(usages, dispatched)

    return PipelineResult(usages=usages, live_partial=live_partial, dispatched=dispatched)


def build_live_record(run_id: str, timestamp_utc: str, git_sha: str, budget: float,
                      usages: list, stages_dispatched: int, live_partial: bool,
                      baseline: Optional[BaselineResult] = None,
                      with_app: Optional[baseline_mod.AppMeasure] = None,
                      without_app: Optional[baseline_mod.AppMeasure] = None) -> BenchmarkRecord:
    stage_usages = [u for _, u in usages]
    in_total = _sum_opt([u.input_tokens for u in stage_usages])
    out_total = _sum_opt([u.output_tokens for u in stage_usages])
    tok_total = None if (in_total is None and out_total is None) else (in_total or 0) + (out_total or 0)
    cost_total = _sum_opt([u.cost_usd for u in stage_usages])
    cr_total = _sum_opt([u.cache_read for u in stage_usages])
    cc_total = _sum_opt([u.cache_creation for u in stage_usages])
    with_wall = round(sum(u.duration_s for u in stage_usages) * 10000) / 10000

    stage_attributions = [
        StageAttribution(stage=name, fresh_in=u.input_tokens, cache_creation=u.cache_creation,
                         cache_read=u.cache_read, out=u.output_tokens, cost_usd=u.cost_usd,
                         coverage=u.coverage)
        for name, u in usages
    ]

    # D4: an app measurement (only attempted on the real WITHOUT-arm path) overrides
    # the legacy no-app placeholder; absence of with_app/without_app preserves it
    # byte-for-byte for every pre-existing caller (mechanism default without_arm="skip").
    with_pass = "fail" if live_partial else "pass"
    with_loc = with_test = 0
    with_app_path = None
    if with_app is not None:
        with_pass = with_app.pass_fail
        with_loc = with_app.loc_produced
        with_test = with_app.test_count
        with_app_path = with_app.app_path

    with_p = PathMetrics(
        tokens=Tokens(input=in_total, output=out_total, total=tok_total,
                      cache_read=cr_total, cache_creation=cc_total),
        cost_usd=cost_total, wall_clock_s=with_wall, loc_produced=with_loc, test_count=with_test,
        coverage_pct=0.0, estimate_complexity_score=0, stage_count=stages_dispatched,
        pass_fail=with_pass, app_path=with_app_path)

    without_tokens = Tokens(input=None, output=None, total=None)
    without_cost: Optional[float] = None
    without_wall = 0.0
    without_pass = "pass"
    without_loc = without_test = 0
    without_app_path = None
    if baseline is not None:
        without_wall = round(baseline.duration_s * 10000) / 10000
        if baseline.usage is not None:
            without_tokens = Tokens(
                input=baseline.usage.input_tokens, output=baseline.usage.output_tokens,
                total=_tok_total(baseline.usage.input_tokens, baseline.usage.output_tokens),
                cache_read=baseline.usage.cache_read, cache_creation=baseline.usage.cache_creation)
            without_cost = baseline.usage.cost_usd
        if without_app is not None:
            without_pass = without_app.pass_fail
            without_loc = without_app.loc_produced
            without_test = without_app.test_count
            without_app_path = without_app.app_path

    without_p = PathMetrics(
        tokens=without_tokens, cost_usd=without_cost, wall_clock_s=without_wall,
        loc_produced=without_loc, test_count=without_test, coverage_pct=0.0,
        estimate_complexity_score=0, stage_count=1, pass_fail=without_pass,
        app_path=without_app_path)

    return make_record(run_id=run_id, timestamp_utc=timestamp_utc, mode="live",
                       git_sha=git_sha, budget_usd=budget, with_pm=with_p,
                       without_pm=without_p, live_partial=live_partial,
                       stages=stage_attributions)


def now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def git_sha7(repo_root: str) -> str:
    r = Subprocess.run(["git", "-C", repo_root, "rev-parse", "--short=7", "HEAD"])
    sha = r.stdout.strip()
    return sha if (r.exit_code == 0 and sha) else "nogit"


def dispatch(workdir: str, budget: float, record_path: str, benchmark_dir: str,
             dispatcher: Optional[Dispatching] = None, env: Optional[dict] = None,
             estimate_runner: Optional[Callable[[list], str]] = None,
             prompts_dir: Optional[str] = None, stages: Optional[list] = None,
             cli_login_runner: Optional[Callable[[], str]] = None,
             capture_mode: str = CAPTURE_JSON,
             stderr: Optional[Callable[[str], None]] = None,
             git_sha_runner: Optional[Callable[[str], str]] = None,
             without_arm: str = baseline_mod.ARM_SKIP) -> int:
    """Run the full live pipeline end-to-end and write the BenchmarkRecord.

    Exit codes: 0 ok / 2 pre-flight decline / 3 no credential / 4 partial (record
    written first, D6). Dispatcher errors from a WITH stage propagate (tests assert
    the tripwire); a WITHOUT-arm ``DispatchFailure`` is tolerated (see run_baseline).
    ``without_arm="real"`` dispatches the WITHOUT baseline FIRST (D1) and fills app
    metrics for both arms post-run (D4); the "skip" mechanism default reproduces the
    pre-existing WITH-only behavior byte-for-byte.
    """
    from . import credentials  # local import keeps credentials optional at import time

    stages = stages if stages is not None else budget_mod.PIPELINE_STAGES
    warn = stderr or (lambda s: sys.stderr.write(s + "\n"))
    workdir_path = os.path.join(benchmark_dir, "workdirs", workdir)
    audit_path = os.path.join(workdir_path, ".context", "logs", "audit.jsonl")
    prompts = prompts_dir or os.path.join(benchmark_dir, "live", "prompts")
    plugin_root = os.path.dirname(benchmark_dir)
    estimate_calc = os.path.join(plugin_root, "skills", "estimation-methodology",
                                 "scripts", "estimate-calc.py")
    real_arm = without_arm == baseline_mod.ARM_REAL

    run_id = workdir
    timestamp_utc = now_iso()
    git_sha = git_sha_runner(plugin_root) if git_sha_runner else git_sha7(plugin_root)
    effective_dispatcher = dispatcher or SubprocessDispatcher(workdir=workdir_path)

    # 1. Credential probe — before ANY dispatch.
    try:
        credentials.require_credential(env=env, cli_login_runner=cli_login_runner)
    except credentials.CredentialError as e:
        warn(str(e))
        return 3

    # 2. Pre-flight budget gate — dispatch nothing if projection breaches. The
    # WITHOUT arm counts as one extra dispatch when real (D1 preflight).
    preflight_stage_count = len(stages) + (1 if real_arm else 0)
    try:
        budget_mod.assert_preflight_within_budget(
            budget, preflight_stage_count, estimate_calc, runner=estimate_runner)
    except budget_mod.BudgetExceeded as e:
        warn(str(e))
        return 2

    record_dir = os.path.dirname(record_path)
    if record_dir:
        os.makedirs(record_dir, exist_ok=True)

    shared_tally = budget_mod.RunningTally(budget)
    baseline_result: Optional[BaselineResult] = None
    if real_arm:
        baseline_result = run_baseline(
            prompts, effective_dispatcher, shared_tally, without_arm, audit_path,
            estimate_calc, estimate_runner=estimate_runner, capture_mode=capture_mode)
        # Flush right after the arm (D1): a later WITH-stage breach still leaves a
        # real baseline on disk.
        write_record(
            build_live_record(run_id, timestamp_utc, git_sha, budget, [], 0,
                              live_partial=True, baseline=baseline_result),
            record_path)

    def _persist_partial(partial_usages, partial_dispatched):
        partial = build_live_record(run_id, timestamp_utc, git_sha, budget,
                                    partial_usages, partial_dispatched, live_partial=True,
                                    baseline=baseline_result)
        write_record(partial, record_path)

    result = run_pipeline(
        workdir_path=workdir_path, budget=budget, prompts_dir=prompts,
        audit_path=audit_path, dispatcher=effective_dispatcher,
        estimate_calc_path=estimate_calc, estimate_runner=estimate_runner,
        stages=stages, capture_mode=capture_mode, persist_partial=_persist_partial,
        tally=shared_tally)

    with_app: Optional[baseline_mod.AppMeasure] = None
    without_app: Optional[baseline_mod.AppMeasure] = None
    if real_arm:
        try:
            with_app = baseline_mod.measure_app(workdir_path, plugin_root, exclude_dirs={"without"})
            if with_app is None and result.dispatched > 0:
                with_app = baseline_mod.AppMeasure(loc_produced=0, test_count=0,
                                                   pass_fail="fail", app_path=None)
            if baseline_result is not None and baseline_result.dispatched:
                without_root = os.path.join(workdir_path, "without")
                without_app = baseline_mod.measure_app(without_root, plugin_root)
                if without_app is None:
                    without_app = baseline_mod.AppMeasure(loc_produced=0, test_count=0,
                                                          pass_fail="fail", app_path=None)
        except Exception as exc:  # noqa: BLE001 — measurement never loses the record write
            warn(f"app metrics fill failed: {exc}")

    arm_partial = baseline_result.partial if baseline_result is not None else False
    final_partial = result.live_partial or arm_partial

    record = build_live_record(run_id, timestamp_utc, git_sha, budget,
                               result.usages, result.dispatched, final_partial,
                               baseline_result, with_app, without_app)
    write_record(record, record_path)

    if final_partial:
        warn(f"live run partial: {result.dispatched}/{len(stages)} stages; "
             f"record written to {record_path}")
        return 4
    return 0
