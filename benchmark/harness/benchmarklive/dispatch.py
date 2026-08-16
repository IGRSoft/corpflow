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

Orchestration only: the stage contract lives in stage_table, argv in settings_argv,
telemetry in stage_usage, arm types and the dispatch seam in arm_exec, and record
shapes in records. Every one of their names stays reachable as ``dispatch.<name>``.
"""

from __future__ import annotations

import os
import sys
from datetime import datetime, timezone
from typing import Callable, Optional

from benchmarkkit import oracle
from benchmarkkit.genlib import Subprocess, Timer
from benchmarkkit.metrics import BenchmarkRecord, write_record

from . import baseline as baseline_mod
from . import budget as budget_mod
from . import preamble

# Re-export shim: callers and tests address these as ``dispatch.<name>``.
from .arm_exec import (  # noqa: F401
    STAGE_TIMEOUT_S,
    ArmResult,
    ArmSpec,
    DispatchFailure,
    Dispatching,
    SubprocessDispatcher,
    _arm_tokens,
    _sum_opt,
    _tok_total,
)
from .records import (  # noqa: F401
    PipelineResult,
    _arm_verdict,
    _oracle_conforms,
    _stage_attributions,
    build_arm_record,
    build_live_record,
)
from .settings_argv import (  # noqa: F401
    PERMISSION_MODE,
    SETTINGS_RELPATH,
    BenchmarkSettingsMissing,
    _settings_argv,
    build_arm_stage_argv,
    build_stage_argv,
    require_settings,
    settings_path_for,
)
from .stage_table import (  # noqa: F401
    CAPTURE_JSON,
    CAPTURE_STREAM_JSON,
    HARNESS_GENERATION,
    PROMPT_CONTRACT,
    STAGE_TABLE,
    build_era,
)
from .stage_usage import (  # noqa: F401
    NON_APP_DIRS,
    StageUsage,
    _audit_subagent_spawns,
    capture_layer2,
    capture_stage_usage,
    dv_produced_swift,
)

# Raw stage stdout over this size is persisted truncated with a marker (A3). Read
# through this module's globals so a caller can lower the cap by rebinding it here.
CAPTURE_TRUNCATE_BYTES = 25 * 1024 * 1024


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
             selection: Optional[baseline_mod.ArmSelection] = None,
             now_fn: Optional[Callable[[], float]] = None) -> int:
    """Run the live pipeline end-to-end and write the BenchmarkRecord.

    ``selection`` drives which arms dispatch and what shape is recorded; when omitted
    it is derived from ``without_arm`` so every pre-existing caller keeps its exact
    behaviour. A single-arm selection records only its own arm and gets the whole
    budget — there is no second arm to reserve half for.
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
    if selection is None:
        selection = baseline_mod.resolve_arm_selection(
            None, without_arm,
            baseline_mod.stages_subset(stages, budget_mod.PIPELINE_STAGES))

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

    # 2. Pre-flight budget gate. Every selected arm runs the same stage list.
    arms = len(selection.dispatch)
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
    # An equal share per selected arm, not one shared purse: the arm dispatched first
    # would otherwise spend the run and leave the second truncated, and a comparison
    # between a complete arm and a starved one measures the budget, not the agent.
    per_arm_budget = budget / arms

    specs = {"with": with_spec, "without": without_spec}
    dispatchers = {"with": with_dispatcher, "without": without_dispatcher}
    results: dict = {}
    apps: dict = {}

    def _compose(partial: bool) -> BenchmarkRecord:
        if selection.record_shape == baseline_mod.SHAPE_ARM:
            arm = selection.arm
            res = results.get(arm) or ArmResult(name=arm)
            return build_arm_record(run_id, timestamp_utc, git_sha, budget, arm,
                                    res.usages, res.dispatched, arm_partial=partial,
                                    app=apps.get(arm))
        with_res = results.get("with") or ArmResult(name="with")
        wo_res = results.get("without")
        return build_live_record(
            run_id, timestamp_utc, git_sha, budget, with_res.usages, with_res.dispatched,
            live_partial=partial, with_app=apps.get("with"), without_app=apps.get("without"),
            without_usages=wo_res.usages if wo_res is not None else None,
            without_dispatched=wo_res.dispatched if wo_res is not None else 0,
            without_partial=wo_res.partial if wo_res is not None else False,
            with_partial=with_res.partial)

    def _flush(partial: bool) -> None:
        write_record(_compose(partial), record_path)

    for name in selection.dispatch:
        def _persist(res: ArmResult, _name: str = name) -> None:
            # OI-2: a budget breach returns an ArmResult, but a throw mid-arm returns
            # nothing, so completed stages only survive if flushed here.
            results[_name] = res
            _flush(partial=True)

        results[name] = run_arm(
            specs[name], prompts_by_stage, dispatchers[name],
            budget_mod.RunningTally(per_arm_budget), estimate_calc, stages,
            estimate_runner=estimate_runner, capture_mode=capture_mode,
            settings_path=settings_path, captures_dir=captures_dir,
            persist_partial=_persist, now_fn=now_fn)
        # Flush as each arm completes so a later arm's breach cannot lose it.
        _flush(partial=True)

    # Every dispatched arm is measured and graded, including a single-arm run: an arm
    # with no oracle payload carries no quality signal to compare against.
    for name in selection.dispatch:
        apps[name] = _measure_arm(specs[name].cwd, plugin_root, results[name].dispatched, warn)

    # Scoped to the arms that actually dispatched, so an arm that never ran cannot
    # raise the flag on the arm that did.
    final_partial = any(results[name].partial for name in selection.dispatch)

    write_record(_compose(final_partial), record_path)

    if final_partial:
        dispatched = sum(results[name].dispatched for name in selection.dispatch)
        warn(f"live run partial: {dispatched}/{len(stages) * arms} stages across "
             f"{'+'.join(selection.dispatch)}; record written to {record_path}")
        return 4
    return 0
