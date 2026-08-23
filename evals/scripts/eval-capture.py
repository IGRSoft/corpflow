#!/usr/bin/env python3
"""eval-capture — dispatch eval-set prompts to a live model and store the responses.

The paid half of the eval loop: `eval-grade.py` scores what this writes. Kept
stdlib-only and free of any `benchmarklive` import so the two harnesses cannot
drift into each other; `benchmark/` measures cost and process, `evals/` measures
output quality.

Usage:
  eval-capture.py --eval-set <path> [--case ID]... [--out-dir D] [--model M]
                  [--mode command|natural] [--budget USD] [--timeout S]
                  [--settings PATH] [--force] [--dry-run]

Exit codes: 0 ok / 1 a dispatch failed / 2 pre-flight decline / 3 no credential
/ 4 budget breach (prior cases already written) / 64 bad usage.
"""

from __future__ import annotations

import argparse
import datetime
import json
import os
import subprocess
import sys
import threading
from concurrent import futures

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import importlib.util

_ENGINE_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "eval-engine.py")
_spec = importlib.util.spec_from_file_location("eval_engine", _ENGINE_PATH)
engine = importlib.util.module_from_spec(_spec)
sys.modules["eval_engine"] = engine
_spec.loader.exec_module(engine)

CAPTURE_CONTRACT = "skill-eval-capture-v1"
PERMISSION_MODE = "bypassPermissions"
CREDENTIAL_ENV = "ANTHROPIC_API_KEY"

# Matches commands/request-plan.md frontmatter; capturing off-model measures a
# configuration nobody ships.
DEFAULT_MODEL = "claude-sonnet-5"
DEFAULT_TIMEOUT = 300.0

MISSING_CREDENTIAL_MESSAGE = (
    "capture requires credentials; set ANTHROPIC_API_KEY or run claude login"
)


class PreflightError(Exception):
    """Refusal raised before any spend."""


def repo_root() -> str:
    return os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def run(argv: list, stdin_text: str | None = None, timeout: float | None = None,
        cwd: str | None = None):
    try:
        return subprocess.run(
            argv, cwd=cwd, input=stdin_text,
            stdin=None if stdin_text is not None else subprocess.DEVNULL,
            capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return subprocess.CompletedProcess(argv, 124, "", f"timed out after {timeout}s")
    except (OSError, ValueError) as exc:
        return subprocess.CompletedProcess(argv, 127, "", f"spawn failed: {exc}")


def has_credential(env: dict | None = None, auth_runner=None) -> bool:
    """Env key short-circuits the CLI probe. Only the boolean ever leaves this function."""
    source = env if env is not None else os.environ
    value = source.get(CREDENTIAL_ENV)
    if value is not None and value.strip():
        return True
    probe = auth_runner or (lambda: run(["claude", "auth", "status", "--json"]).stdout)
    try:
        parsed = json.loads(probe())
    except Exception:
        return False
    return isinstance(parsed, dict) and parsed.get("loggedIn") is True


def build_argv(model: str, settings_path: str | None) -> list:
    argv = ["claude", "-p", "--model", model,
            "--permission-mode", PERMISSION_MODE, "--output-format", "json"]
    if settings_path:
        argv += ["--settings", settings_path]
    return argv


def build_prompt(case: dict, mode: str, skill_name: str) -> str:
    """`command` grades the skill's output; `natural` also grades whether it triggers."""
    if mode == "natural":
        return case["prompt"]
    return f'/corpflow:{skill_name} "{case["prompt"]}"'


def extract_response(stdout: str) -> tuple[str | None, dict]:
    """Return (response_text, usage). Text is None when the CLI yielded none — a
    capture that invents an empty answer would be graded as a real failure."""
    try:
        obj = json.loads(stdout)
    except (ValueError, TypeError):
        return None, {}
    if not isinstance(obj, dict):
        return None, {}
    if obj.get("is_error") is True or obj.get("subtype") not in (None, "success"):
        return None, {}
    text = obj.get("result")
    if not isinstance(text, str) or not text.strip():
        return None, {}
    usage = obj.get("usage") if isinstance(obj.get("usage"), dict) else {}
    return text, {
        "input_tokens": usage.get("input_tokens"),
        "output_tokens": usage.get("output_tokens"),
        "cache_read_input_tokens": usage.get("cache_read_input_tokens"),
        "cache_creation_input_tokens": usage.get("cache_creation_input_tokens"),
        "cost_usd": obj.get("total_cost_usd"),
    }


def plugin_sha(root: str) -> str | None:
    """HEAD, suffixed `-dirty` when the tree carries uncommitted changes.

    Both the v0.4.0 and v0.5.0 captures recorded a bare `9e2cda9` because the skill edit
    under test was never committed — two different skills, one provenance string. Only the
    frontmatter version bump distinguished them, and that is a convention, not a guarantee.
    """
    r = run(["git", "-C", root, "rev-parse", "--short=7", "HEAD"])
    if r.returncode != 0 or not r.stdout.strip():
        return None
    sha = r.stdout.strip()
    d = run(["git", "-C", root, "status", "--porcelain", "--untracked-files=no"])
    return f"{sha}-dirty" if d.returncode == 0 and d.stdout.strip() else sha


def skill_version(root: str, skill_name: str) -> str | None:
    """Reads `version:` from SKILL.md frontmatter only, so a body mention cannot spoof it."""
    path = os.path.join(root, "skills", skill_name, "SKILL.md")
    try:
        with open(path, encoding="utf-8") as f:
            lines = f.read().split("\n")
    except OSError:
        return None
    if not lines or lines[0].strip() != "---":
        return None
    for line in lines[1:]:
        if line.strip() == "---":
            return None
        if line.startswith("version:"):
            return line.split(":", 1)[1].strip() or None
    return None


def record_for(eval_set, case, mode, model, sent_prompt, response, usage, provenance) -> dict:
    return {
        "capture_contract": CAPTURE_CONTRACT,
        "case_id": case["id"],
        "skill": eval_set["skill_name"],
        "mode": mode,
        "model": model,
        "permission_mode": PERMISSION_MODE,
        "prompt_digest": engine.prompt_digest(eval_set, case["id"]),
        "assertions_digest": engine.assertions_digest(eval_set, case["id"]),
        "sent_prompt": sent_prompt,
        "response": response,
        "usage": usage,
        **provenance,
    }


def capture_case(eval_set, case, *, mode, model, settings_path, timeout, cwd, dispatcher=None):
    """Dispatch one case. Raises RuntimeError on any outcome that is not a real answer."""
    sent_prompt = build_prompt(case, mode, eval_set["skill_name"])
    argv = build_argv(model, settings_path)
    dispatch = dispatcher or (lambda a, p: run(a, stdin_text=p, timeout=timeout, cwd=cwd))
    result = dispatch(argv, sent_prompt)
    if result.returncode != 0:
        raise RuntimeError(
            f"case {case['id']}: claude -p exited {result.returncode}: "
            f"{(result.stderr or '').strip()[:300]}")
    response, usage = extract_response(result.stdout)
    if response is None:
        raise RuntimeError(f"case {case['id']}: no response text in CLI output")
    return sent_prompt, response, usage


def main(argv_in: list) -> int:
    p = argparse.ArgumentParser(prog="eval-capture", add_help=True)
    p.add_argument("--eval-set", required=True)
    p.add_argument("--case", action="append", type=int, default=None)
    p.add_argument("--out-dir", default=None)
    p.add_argument("--model", default=DEFAULT_MODEL)
    p.add_argument("--mode", choices=("command", "natural"), default="command")
    p.add_argument("--budget", type=float, default=None)
    p.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT)
    p.add_argument("--settings", default=None)
    p.add_argument("--force", action="store_true")
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--split", choices=("train", "dev", "test"), default=None,
                   help="capture only this tranche")
    p.add_argument("--concurrency", type=int, default=1,
                   help="parallel dispatches; the budget check trails by up to this many cases")
    try:
        args = p.parse_args(argv_in)
    except SystemExit:
        return 64

    root = repo_root()
    try:
        with open(args.eval_set, encoding="utf-8") as f:
            eval_set = json.load(f)
    except (OSError, ValueError) as exc:
        sys.stderr.write(f"eval-capture: cannot read eval set: {exc}\n")
        return 64

    ids = [c["id"] for c in eval_set["evals"]
           if args.split is None or c.get("split") == args.split]
    selected = ids if not args.case else [i for i in ids if i in args.case]
    unknown = sorted(set(args.case or []) - set(ids))
    if unknown:
        sys.stderr.write(f"eval-capture: unknown case id(s): {unknown}\n")
        return 64

    out_dir = args.out_dir or os.path.join(os.path.dirname(os.path.abspath(args.eval_set)),
                                           "responses")
    settings_path = args.settings
    if settings_path and not os.path.exists(settings_path):
        sys.stderr.write(f"eval-capture: --settings not found: {settings_path}\n")
        return 2

    if args.dry_run:
        for cid in selected:
            case = engine.find_case(eval_set, cid)
            print(json.dumps({
                "case_id": cid, "mode": args.mode, "model": args.model,
                "argv": build_argv(args.model, settings_path),
                "sent_prompt": build_prompt(case, args.mode, eval_set["skill_name"]),
                "out": os.path.join(out_dir, f"{cid}.json"),
            }, indent=2))
        return 0

    if not has_credential():
        sys.stderr.write(MISSING_CREDENTIAL_MESSAGE + "\n")
        return 3

    os.makedirs(out_dir, exist_ok=True)
    provenance = {
        "captured_at": datetime.datetime.now(datetime.timezone.utc)
                               .replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "plugin_sha": plugin_sha(root),
        "skill_version": skill_version(root, eval_set["skill_name"]),
    }

    pending = []
    for cid in selected:
        dest = os.path.join(out_dir, f"{cid}.json")
        if os.path.exists(dest) and not args.force:
            print(f"skip case {cid}: exists (use --force to re-capture)")
            continue
        pending.append(cid)

    state = {"spent": 0.0, "breached": False}
    failures = []
    lock = threading.Lock()

    def work(cid):
        if state["breached"]:
            return None
        case = engine.find_case(eval_set, cid)
        sent, response, usage = capture_case(
            eval_set, case, mode=args.mode, model=args.model,
            settings_path=settings_path, timeout=args.timeout, cwd=root)
        rec = record_for(eval_set, case, args.mode, args.model, sent, response, usage, provenance)
        with open(os.path.join(out_dir, f"{cid}.json"), "w", encoding="utf-8") as f:
            json.dump(rec, f, indent=2, ensure_ascii=False)
            f.write("\n")
        cost = usage.get("cost_usd")
        with lock:
            if isinstance(cost, (int, float)):
                state["spent"] += float(cost)
            if args.budget is not None and state["spent"] > args.budget:
                state["breached"] = True
            print(f"captured case {cid}  (${state['spent']:.2f} spent)", flush=True)
        return cid

    with futures.ThreadPoolExecutor(max_workers=max(1, args.concurrency)) as pool:
        for cid, future in [(c, pool.submit(work, c)) for c in pending]:
            try:
                future.result()
            except RuntimeError as exc:
                sys.stderr.write(f"eval-capture: {exc}\n")
                failures.append(cid)

    if state["breached"]:
        sys.stderr.write(
            f"eval-capture: budget breached (${state['spent']:.4f} > ${args.budget:.4f})\n")
        return 4
    if failures:
        sys.stderr.write(f"eval-capture: {len(failures)} case(s) failed: {failures}\n")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
