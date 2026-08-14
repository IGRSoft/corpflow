"""Live paired-arm dispatch adapter.

Runs PL→AR→TL→DV→DR→SR→QA→DC→FN→ST one stage per headless ``claude -p``, summing
REAL tokens/cost, budget-gated, credential-gated. Real dispatch hides behind the
Dispatching protocol; tests inject fakes so NO real LLM call / spend happens. Exit
codes: 0 ok / 2 pre-flight decline / 3 no credential / 4 running-tally breach or
degradation (partial record written FIRST, D6).

Paired arms (U3/U4): the WITHOUT arm no longer runs a single-shot baseline — both
arms execute the SAME ordered 10-stage prompt sequence over the SAME shared prompt
bytes, differing ONLY by ``--agent`` binding (WITH) vs bare (WITHOUT) and by cwd
(``workdirs/<id>/{with,without}/``). ``without_arm="skip"`` (the mechanism default
and every ``--stages`` subset) runs the WITH arm alone and keeps the WITHOUT
placeholder byte-stable for every pre-existing caller.
"""

from __future__ import annotations

import json
import os
import sys
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Callable, Optional, Protocol

from benchmarkkit import oracle
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
    "PL": ("corpflow:product-manager", "claude-opus-5", "high"),
    "AR": ("corpflow:software-architector", "claude-opus-5", "high"),
    "TL": ("corpflow:team-lead", "claude-sonnet-5", "medium"),
    "DV": ("corpflow:developer", "claude-opus-5", "high"),
    "DR": ("corpflow:technical-lead", "claude-opus-5", "high"),
    "SR": ("corpflow:security-reviewer", "claude-opus-5", "xhigh"),
    "QA": ("corpflow:qa-engineer", "claude-sonnet-5", "medium"),
    "DC": ("corpflow:technical-writer", "claude-haiku-4-5", "low"),
    "FN": ("corpflow:project-manager", "claude-sonnet-5", "medium"),
    "ST": ("corpflow:stakeholder", "claude-sonnet-5", "low"),
}

CAPTURE_JSON = "json"
CAPTURE_STREAM_JSON = "stream-json"

# Bumped by hand whenever the graded task text changes; a workload change makes
# token and quality figures incomparable just as surely as a model repin does.
PROMPT_CONTRACT = "scripted-cli-v3"
HARNESS_GENERATION = "python-1"


def build_era() -> dict:
    """Stamp what this run's numbers are comparable against.

    Model pins are the axis that silently invalidated the stored baselines at
    v3.37.1, so they travel with every record rather than living only in a README.
    """
    return {
        "harness": HARNESS_GENERATION,
        "prompt_contract": PROMPT_CONTRACT,
        "model_pins": {stage: model for stage, (_agent, model, _effort) in STAGE_TABLE.items()},
    }


# Headless has no interactive prompt, so safety rides on the deny-list settings file,
# not the mode. Mirrored verbatim in baseline.py (parity asserted by test, no import).
PERMISSION_MODE = "bypassPermissions"

SETTINGS_RELPATH = ("live", "settings", "benchmark-settings.json")

# Raw stage stdout over this size is persisted truncated with a marker (A3).
CAPTURE_TRUNCATE_BYTES = 25 * 1024 * 1024

# *.swift under these dir names never counts as DV output (A5 tripwire, U2 measure).
NON_APP_DIRS = {".build", ".swiftpm", ".context"}


def settings_path_for(benchmark_dir: str) -> str:
    """Absolute path to the deny-list settings file for this benchmark tree."""
    return os.path.join(benchmark_dir, *SETTINGS_RELPATH)


def _settings_argv(settings_path: Optional[str]) -> list:
    # Low-level argv builder: byte-stable, no I/O policy. Fail-closed enforcement
    # lives in require_settings() at the dispatch entry, NOT here, so the argv
    # shape stays pure/injectable for tests that don't care about the deny-list.
    if settings_path and os.path.exists(settings_path):
        return ["--settings", settings_path]
    return []


class BenchmarkSettingsMissing(Exception):
    """Raised when a bypassPermissions dispatch would otherwise run with no deny-list.

    Headless ``claude -p`` has no interactive prompt, so under ``bypassPermissions``
    the ONLY guardrail is the deny-list settings file. If it is absent we fail closed
    rather than dispatch fail-open; the message names the expected path.
    """


def require_settings(settings_path: str, permission_mode: str = PERMISSION_MODE) -> None:
    """Fail closed BEFORE any dispatch when the deny-list settings file is missing.

    Enforced only under ``bypassPermissions`` (the sole headless mode); any other
    mode carries its own interactive guardrail and is left untouched. Pure and
    injectable — raises :class:`BenchmarkSettingsMissing` or returns ``None``.
    """
    if permission_mode == "bypassPermissions" and not os.path.exists(settings_path):
        raise BenchmarkSettingsMissing(
            "deny-list settings file is required under bypassPermissions but is "
            f"missing: {settings_path} — create it (see benchmark/live/settings/) "
            "before dispatching; refusing to run fail-open with no deny-list."
        )


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


@dataclass
class ArmSpec:
    """The sole legitimate A/B difference: ``bind_agent`` (→ --agent) and ``cwd``.
    Everything else (prompts, budget, capture shape) is shared by construction."""

    name: str            # "with" | "without"
    bind_agent: bool
    cwd: str
    audit_path: str


@dataclass
class ArmResult:
    name: str
    usages: list = field(default_factory=list)   # [(stage, StageUsage)]
    dispatched: int = 0
    partial: bool = False
    dv_gated: bool = False
    app: Optional[baseline_mod.AppMeasure] = None


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
            # Under --output-format json the CLI reports API failures on stdout, not
            # stderr; without this the diagnostic is recoverable only from CLI transcripts.
            out_snippet = r.stdout.strip()[:400]
            raise DispatchFailure(
                f"claude -p failed (rc={r.exit_code}) for argv {argv[:6]}…"
                + (f" stderr: {snippet}" if snippet else "")
                + (f" stdout: {out_snippet}" if out_snippet else "")
            )
        return r.stdout


def build_arm_stage_argv(stage: str, bind_agent: bool = True, capture_mode: str = CAPTURE_JSON,
                         settings_path: Optional[str] = None) -> list:
    """Frozen headless argv for one arm's stage. Bound and bare argvs are identical
    except the trailing ``--agent`` (AC-8 parity target); stream-json adds --verbose."""
    entry = STAGE_TABLE.get(stage)
    if entry is None:
        return []
    agent, model, effort = entry
    argv = ["claude", "-p", "--model", model, "--effort", effort,
            "--permission-mode", PERMISSION_MODE, "--output-format", capture_mode]
    argv += _settings_argv(settings_path)
    if bind_agent:
        argv += ["--agent", agent]
    if capture_mode == CAPTURE_STREAM_JSON:
        argv.append("--verbose")
    return argv


def build_stage_argv(stage: str, capture_mode: str = CAPTURE_JSON,
                     settings_path: Optional[str] = None) -> list:
    """WITH-arm (agent-bound) argv — thin wrapper over the shared arm builder."""
    return build_arm_stage_argv(stage, bind_agent=True, capture_mode=capture_mode,
                                settings_path=settings_path)


def persist_capture(captures_dir: Optional[str], arm: str, stage: str, stdout: str) -> None:
    """Persist raw stage stdout BEFORE parsing (A3). ``captures_dir=None`` is a no-op,
    keeping existing callers byte-stable; any failure is swallowed — persistence never
    kills a run. Over-cap payloads are written truncated with a marker."""
    if captures_dir is None:
        return
    try:
        os.makedirs(captures_dir, exist_ok=True)
        path = os.path.join(captures_dir, f"{arm}-{stage}.jsonl")
        raw = stdout.encode("utf-8")
        truncated = len(raw) > CAPTURE_TRUNCATE_BYTES
        body = raw[:CAPTURE_TRUNCATE_BYTES].decode("utf-8", "ignore") if truncated else stdout
        with open(path, "w", encoding="utf-8") as f:
            f.write(body)
            if truncated:
                f.write(f"\n<<<TRUNCATED at {CAPTURE_TRUNCATE_BYTES} bytes>>>\n")
    except OSError:
        pass


def dv_produced_swift(arm_cwd: str) -> bool:
    """True when at least one *.swift landed outside {.build,.swiftpm,.context} (A5)."""
    for root, dirs, files in os.walk(arm_cwd):
        dirs[:] = [d for d in dirs if d not in NON_APP_DIRS]
        if any(f.endswith(".swift") for f in files):
            return True
    return False


def _audit_subagent_spawns(audit_path: str, stage: str,
                           now_fn: Optional[Callable[[], float]] = None) -> int:
    """Count canonical nested ``subagent_stopped`` rows attributed to ``stage`` (A4).

    Canonical only: rows with ``metadata.advisory`` truthy are mirror duplicates and
    skipped; identical ``dedupe_key`` values collapse to one. ``now_fn`` is accepted
    for symmetry with time-window callers but attribution here keys off the row's own
    ``metadata.stage`` (per-arm audit path already scopes the window structurally).
    """
    try:
        with open(audit_path, encoding="utf-8") as f:
            text = f.read()
    except OSError:
        return 0
    seen: set = set()
    count = 0
    for line in text.split("\n"):
        if not line.strip():
            continue
        try:
            rec = json.loads(line)
        except (ValueError, TypeError):
            continue
        if not isinstance(rec, dict) or rec.get("action") != "subagent_stopped":
            continue
        meta = rec.get("metadata")
        if not isinstance(meta, dict) or meta.get("stage") != stage:
            continue
        if meta.get("advisory"):
            continue
        key = meta.get("dedupe_key")
        if key is not None:
            if key in seen:
                continue
            seen.add(key)
        count += 1
    return count


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


def capture_stage_usage(stdout: str, audit_path: str, stage: str,
                        now_fn: Optional[Callable[[], float]] = None) -> StageUsage:
    """Layer 1 (stdout) → Layer 2 (audit.jsonl) → Layer 3 (all None). Never fabricates.

    A4: coverage from stdout is augmented with nested background spawns read from the
    per-arm audit (emitted only when >0, preserving the 4-key StageCoverage shape)."""
    parsed = capture.parse(stdout)
    coverage = parsed.coverage if parsed else None
    nested = _audit_subagent_spawns(audit_path, stage, now_fn=now_fn)
    if nested and coverage is None:
        coverage = StageCoverage(agents=[], skills=[], commands=[], tool_calls=0)
    if nested and coverage is not None:
        coverage.nested_background = nested

    if parsed is not None and parsed.has_usage:
        return StageUsage(input_tokens=parsed.input_tokens, output_tokens=parsed.output_tokens,
                          cost_usd=parsed.cost_usd, capture_layer=1,
                          cache_read=parsed.cache_read, cache_creation=parsed.cache_creation,
                          coverage=coverage)
    layer2 = capture_layer2(audit_path, stage)
    if layer2 is not None:
        layer2.coverage = coverage
        return layer2
    return StageUsage(capture_layer=None, coverage=coverage)


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


def assemble_prompts(prompts_dir: str, stages: list, state_json_text: str,
                     worktask_id: str, plan_file: str) -> dict:
    """Assemble each stage's stdin prompt ONCE from shared inputs so both arms consume
    byte-identical prompts (AC-16). Missing prompt file is a hard error."""
    out = {}
    for stage in stages:
        prompt_path = os.path.join(prompts_dir, f"{stage.lower()}.txt")
        with open(prompt_path, encoding="utf-8") as f:
            task_text = f.read()
        out[stage] = preamble.assemble_stage_prompt(
            stage, worktask_id=worktask_id, plan_file=plan_file,
            state_json_text=state_json_text, task_text=task_text)
    return out


@dataclass
class PipelineResult:
    usages: list
    live_partial: bool
    dispatched: int


def run_arm(arm: ArmSpec, prompts_by_stage: dict, dispatcher: Dispatching,
            tally: "budget_mod.RunningTally", estimate_calc_path: str,
            stages: list, estimate_runner: Optional[Callable[[list], str]] = None,
            capture_mode: str = CAPTURE_JSON, settings_path: Optional[str] = None,
            captures_dir: Optional[str] = None,
            persist_partial: Optional[Callable[["ArmResult"], None]] = None,
            now_fn: Optional[Callable[[], float]] = None) -> ArmResult:
    """Dispatch one arm's ordered stage sequence under its own running-tally gate.

    Both arms call this with identical ``prompts_by_stage``; only ``arm.bind_agent``
    and ``arm.cwd`` differ. Gate (b) aborts before a breaching dispatch; A3 persists
    each raw stdout before parsing; A5 stops the arm if the DV stage lands no Swift.
    """
    result = ArmResult(name=arm.name)
    for stage in stages:
        estimate = budget_mod.estimate_stage_cost(estimate_calc_path, stage=stage,
                                                  runner=estimate_runner)
        if not tally.can_afford(estimate):
            result.partial = True
            break
        prompt_text = prompts_by_stage[stage]
        argv = build_arm_stage_argv(stage, bind_agent=arm.bind_agent,
                                    capture_mode=capture_mode, settings_path=settings_path)
        timer = Timer()
        timer.start()
        # A throw here propagates with prior stages' partial ALREADY on disk (OI-2).
        stdout = dispatcher.run(argv, prompt_text)
        persist_capture(captures_dir, arm.name, stage, stdout)
        usage = capture_stage_usage(stdout, arm.audit_path, stage, now_fn=now_fn)
        usage.duration_s = timer.elapsed
        result.usages.append((stage, usage))
        result.dispatched += 1
        if usage.capture_layer is None:
            result.partial = True
        tally.add(usage.cost_usd)
        if persist_partial is not None:
            persist_partial(result)
        if stage == "DV" and not dv_produced_swift(arm.cwd):
            result.dv_gated = True
            result.partial = True
            break
    return result


def _arm_tokens(usages: list) -> tuple:
    su = [u for _, u in usages]
    in_total = _sum_opt([u.input_tokens for u in su])
    out_total = _sum_opt([u.output_tokens for u in su])
    tok_total = None if (in_total is None and out_total is None) else (in_total or 0) + (out_total or 0)
    cost_total = _sum_opt([u.cost_usd for u in su])
    cr_total = _sum_opt([u.cache_read for u in su])
    cc_total = _sum_opt([u.cache_creation for u in su])
    wall = round(sum(u.duration_s for u in su) * 10000) / 10000
    return in_total, out_total, tok_total, cost_total, cr_total, cc_total, wall


def _stage_attributions(usages: list, arm: Optional[str]) -> list:
    return [
        StageAttribution(stage=name, fresh_in=u.input_tokens, cache_creation=u.cache_creation,
                         cache_read=u.cache_read, out=u.output_tokens, cost_usd=u.cost_usd,
                         coverage=u.coverage, arm=arm)
        for name, u in usages
    ]


def _arm_verdict(app: Optional[baseline_mod.AppMeasure], partial: bool) -> tuple:
    """Collapse one arm's measurement into ``(pass_fail, loc, tests, app_path, oracle)``.

    Fail-closed on two counts: an unmeasured or degraded arm is never green, and
    where the held-out oracle ran it — not the arm's self-written suite — decides
    the verdict. The verdict reads the `specified` tier alone, which is the contract
    the arm was actually handed; the `implied` tier is a quality signal reported
    beside it, not something to fail an arm over. Full conformance is required to
    pass; a partial score is a fail that still carries its rate for comparison.
    """
    if app is None:
        return "fail", 0, 0, None, None

    verdict = "fail"
    if not partial:
        if app.oracle is not None:
            verdict = "pass" if _oracle_conforms(app.oracle) else "fail"
        else:
            verdict = app.pass_fail
    return verdict, app.loc_produced, app.test_count, app.app_path, app.oracle


def _oracle_conforms(oracle: dict) -> bool:
    """True when the arm cleared every case it was told about."""
    specified = (oracle.get("tiers") or {}).get("specified")
    if specified is not None:
        return specified.get("pass_rate") == 1.0
    return oracle.get("pass_rate") == 1.0


def build_live_record(run_id: str, timestamp_utc: str, git_sha: str, budget: float,
                      usages: list, stages_dispatched: int, live_partial: bool,
                      with_app: Optional[baseline_mod.AppMeasure] = None,
                      without_app: Optional[baseline_mod.AppMeasure] = None,
                      without_usages: Optional[list] = None,
                      without_dispatched: int = 0,
                      without_partial: bool = False,
                      with_partial: Optional[bool] = None) -> BenchmarkRecord:
    """Build the record. Skip mode (``without_usages=None``) reproduces the WITH-only
    byte shape exactly; paired mode aggregates the WITHOUT arm's own 10-stage tokens
    and tags every stage row with its arm (both additive/emit-only)."""
    paired = without_usages is not None
    # Live coverage is never measured; None marks it absent so renderers tell it apart
    # from a real 0.0. Skip mode keeps the byte-stable 0.0 placeholder (asserted by test).
    with_coverage = None if paired else 0.0

    in_total, out_total, tok_total, cost_total, cr_total, cc_total, with_wall = _arm_tokens(usages)

    # Verdicts read per-arm degradation: record-level live_partial ORs both arms,
    # and judging one arm by it would fail a complete arm for the other's breach.
    if with_partial is None:
        with_partial = live_partial
    with_pass, with_loc, with_test, with_app_path, with_oracle = _arm_verdict(with_app, with_partial)

    with_p = PathMetrics(
        tokens=Tokens(input=in_total, output=out_total, total=tok_total,
                      cache_read=cr_total, cache_creation=cc_total),
        cost_usd=cost_total, wall_clock_s=with_wall, loc_produced=with_loc, test_count=with_test,
        coverage_pct=with_coverage, estimate_complexity_score=0, stage_count=stages_dispatched,
        pass_fail=with_pass, app_path=with_app_path, oracle=with_oracle)

    if not paired:
        without_p = PathMetrics(
            tokens=Tokens(input=None, output=None, total=None),
            cost_usd=None, wall_clock_s=0.0, loc_produced=0, test_count=0, coverage_pct=0.0,
            estimate_complexity_score=0, stage_count=1, pass_fail="pass", app_path=None)
        return make_record(run_id=run_id, timestamp_utc=timestamp_utc, mode="live",
                           git_sha=git_sha, budget_usd=budget, with_pm=with_p,
                           without_pm=without_p, live_partial=live_partial,
                           stages=_stage_attributions(usages, arm=None), era=build_era())

    (o_in, o_out, o_tok, o_cost, o_cr, o_cc, o_wall) = _arm_tokens(without_usages)
    (without_pass, without_loc, without_test,
     without_app_path, without_oracle) = _arm_verdict(without_app, without_partial)

    without_p = PathMetrics(
        tokens=Tokens(input=o_in, output=o_out, total=o_tok, cache_read=o_cr, cache_creation=o_cc),
        cost_usd=o_cost, wall_clock_s=o_wall, loc_produced=without_loc, test_count=without_test,
        coverage_pct=None, estimate_complexity_score=0, stage_count=without_dispatched,
        pass_fail=without_pass, app_path=without_app_path, oracle=without_oracle)

    stages_all = (_stage_attributions(usages, arm="with")
                  + _stage_attributions(without_usages, arm="without"))
    return make_record(run_id=run_id, timestamp_utc=timestamp_utc, mode="live",
                       git_sha=git_sha, budget_usd=budget, with_pm=with_p,
                       without_pm=without_p, live_partial=live_partial, stages=stages_all,
                       era=build_era())


def now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def git_sha7(repo_root: str) -> str:
    r = Subprocess.run(["git", "-C", repo_root, "rev-parse", "--short=7", "HEAD"])
    sha = r.stdout.strip()
    return sha if (r.exit_code == 0 and sha) else "nogit"


def _measure_arm(arm_cwd: str, plugin_root: str, dispatched: int,
                 warn: Callable[[str], None],
                 grader: Optional[Callable] = None) -> Optional[baseline_mod.AppMeasure]:
    """Measure one arm, then grade it against the held-out oracle.

    Runs after dispatch, so oracle build time never lands in ``wall_clock_s``.
    """
    def unmeasured() -> baseline_mod.AppMeasure:
        return baseline_mod.AppMeasure(loc_produced=0, test_count=0, pass_fail="fail",
                                       app_path=baseline_mod.genlib.relative_path(arm_cwd, plugin_root))

    try:
        app = baseline_mod.measure_app(arm_cwd, plugin_root)
        if app is None and dispatched > 0:
            app = unmeasured()
    except Exception as exc:  # noqa: BLE001 — measurement never loses the record write
        warn(f"app metrics fill failed for {arm_cwd}: {exc}")
        app = unmeasured() if dispatched > 0 else None

    if app is None:
        return None

    grade = grader if grader is not None else oracle.grade
    try:
        app.oracle = grade(arm_cwd, warn=warn).to_dict()
    except Exception as exc:  # noqa: BLE001 — an ungradeable arm stays unscored, not unrecorded
        warn(f"oracle grading failed for {arm_cwd}: {exc}")
    return app


def dispatch(workdir: str, budget: float, record_path: str, benchmark_dir: str,
             dispatcher: Optional[Dispatching] = None, env: Optional[dict] = None,
             estimate_runner: Optional[Callable[[list], str]] = None,
             prompts_dir: Optional[str] = None, stages: Optional[list] = None,
             cli_login_runner: Optional[Callable[[], str]] = None,
             capture_mode: str = CAPTURE_JSON,
             stderr: Optional[Callable[[str], None]] = None,
             git_sha_runner: Optional[Callable[[str], str]] = None,
             without_arm: str = baseline_mod.ARM_SKIP,
             now_fn: Optional[Callable[[], float]] = None) -> int:
    """Run the live pipeline end-to-end and write the BenchmarkRecord.

    ``without_arm="real"`` runs the paired arms (WITHOUT arm FIRST so a later WITH
    breach still leaves a real comparison on disk); ``"skip"`` (default / any
    ``--stages`` subset) runs the WITH arm alone and reproduces the pre-existing
    WITH-only record byte-for-byte.
    """
    from . import credentials  # local import keeps credentials optional at import time

    stages = stages if stages is not None else budget_mod.PIPELINE_STAGES
    warn = stderr or (lambda s: sys.stderr.write(s + "\n"))
    workdir_path = os.path.join(benchmark_dir, "workdirs", workdir)
    prompts = prompts_dir or os.path.join(benchmark_dir, "live", "prompts")
    plugin_root = os.path.dirname(benchmark_dir)
    estimate_calc = os.path.join(plugin_root, "skills", "estimation-methodology",
                                 "scripts", "estimate-calc.py")
    settings_path = settings_path_for(benchmark_dir)
    # Fail closed: headless dispatch runs under bypassPermissions, so a missing
    # deny-list would run fail-open. Refuse BEFORE any dispatch (SR-M1).
    require_settings(settings_path)
    captures_dir = os.path.join(workdir_path, "captures")
    real_arm = without_arm == baseline_mod.ARM_REAL

    with_spec = ArmSpec(name="with", bind_agent=True,
                        cwd=os.path.join(workdir_path, "with"),
                        audit_path=os.path.join(workdir_path, "with", ".context", "logs", "audit.jsonl"))
    without_spec = ArmSpec(name="without", bind_agent=False,
                           cwd=os.path.join(workdir_path, "without"),
                           audit_path=os.path.join(workdir_path, "without", ".context", "logs", "audit.jsonl"))
    for spec in (with_spec, without_spec):
        os.makedirs(os.path.join(spec.cwd, ".context", "logs"), exist_ok=True)

    run_id = workdir
    timestamp_utc = now_iso()
    git_sha = git_sha_runner(plugin_root) if git_sha_runner else git_sha7(plugin_root)
    with_dispatcher = dispatcher or SubprocessDispatcher(workdir=with_spec.cwd)
    without_dispatcher = dispatcher or SubprocessDispatcher(workdir=without_spec.cwd)

    # 1. Credential probe — before ANY dispatch.
    try:
        credentials.require_credential(env=env, cli_login_runner=cli_login_runner)
    except credentials.CredentialError as e:
        warn(str(e))
        return 3

    # 2. Pre-flight budget gate. The WITHOUT arm runs the same stage list when real.
    arms = 2 if real_arm else 1
    try:
        budget_mod.assert_preflight_within_budget(
            budget, stages, estimate_calc, arms=arms, runner=estimate_runner)
    except budget_mod.BudgetExceeded as e:
        warn(str(e))
        return 2

    record_dir = os.path.dirname(record_path)
    if record_dir:
        os.makedirs(record_dir, exist_ok=True)

    state_json_text = read_state_json_text(workdir_path)
    prompts_by_stage = assemble_prompts(prompts, stages, state_json_text, run_id,
                                        ".context/planning-0.md")
    # An equal share per arm, not one shared purse: the arm dispatched first would
    # otherwise spend the run and leave the second truncated, and a comparison
    # between a complete arm and a starved one measures the budget, not the agent.
    per_arm_budget = budget / arms

    without_result: Optional[ArmResult] = None

    def _flush(with_res: ArmResult, partial: bool) -> None:
        wo_usages = without_result.usages if without_result is not None else None
        wo_dispatched = without_result.dispatched if without_result is not None else 0
        wo_partial = without_result.partial if without_result is not None else False
        write_record(build_live_record(
            run_id, timestamp_utc, git_sha, budget, with_res.usages, with_res.dispatched,
            live_partial=partial, without_usages=wo_usages,
            without_dispatched=wo_dispatched, without_partial=wo_partial), record_path)

    def _persist_without(wo_res: ArmResult) -> None:
        # OI-2 for the WITHOUT arm: a budget breach returns an ArmResult, but a throw
        # mid-arm returns nothing, so completed stages only survive if flushed here.
        nonlocal without_result
        without_result = wo_res
        _flush(ArmResult(name="with"), partial=True)

    if real_arm:
        without_result = run_arm(
            without_spec, prompts_by_stage, without_dispatcher,
            budget_mod.RunningTally(per_arm_budget), estimate_calc,
            stages, estimate_runner=estimate_runner, capture_mode=capture_mode,
            settings_path=settings_path, captures_dir=captures_dir,
            persist_partial=_persist_without, now_fn=now_fn)
        # Flush right after the WITHOUT arm so a later WITH breach still keeps it.
        _flush(ArmResult(name="with"), partial=True)

    def _persist_partial(with_res: ArmResult) -> None:
        _flush(with_res, partial=True)

    with_result = run_arm(
        with_spec, prompts_by_stage, with_dispatcher,
        budget_mod.RunningTally(per_arm_budget), estimate_calc, stages,
        estimate_runner=estimate_runner, capture_mode=capture_mode, settings_path=settings_path,
        captures_dir=captures_dir, persist_partial=_persist_partial, now_fn=now_fn)

    with_app = without_app = None
    if real_arm:
        with_app = _measure_arm(with_spec.cwd, plugin_root, with_result.dispatched, warn)
        without_app = _measure_arm(without_spec.cwd, plugin_root,
                                   without_result.dispatched if without_result else 0, warn)

    final_partial = with_result.partial or (without_result.partial if without_result else False)

    if real_arm:
        record = build_live_record(
            run_id, timestamp_utc, git_sha, budget, with_result.usages, with_result.dispatched,
            live_partial=final_partial, with_app=with_app, without_app=without_app,
            without_usages=without_result.usages, without_dispatched=without_result.dispatched,
            without_partial=without_result.partial, with_partial=with_result.partial)
    else:
        record = build_live_record(
            run_id, timestamp_utc, git_sha, budget, with_result.usages, with_result.dispatched,
            live_partial=final_partial, with_partial=with_result.partial)
    write_record(record, record_path)

    if final_partial:
        warn(f"live run partial: {with_result.dispatched}/{len(stages)} WITH stages; "
             f"record written to {record_path}")
        return 4
    return 0
