#!/usr/bin/env python3
"""eval-capture — dispatch eval-set prompts to a live model and store the responses.

The paid half of the eval loop: `eval-grade.py` scores what this writes. Kept
stdlib-only and free of any `benchmarklive` import so the two harnesses cannot
drift into each other; `benchmark/` measures cost and process, `evals/` measures
output quality.

Usage:
  eval-capture.py --eval-set <path> [--case ID]... [--out-dir D] [--model M]
                  [--mode command|natural] [--budget USD] [--timeout S]
                  [--settings PATH] [--split S] [--concurrency N]
                  [--no-isolate] [--probe] [--force] [--dry-run]

Exit codes: 0 ok / 1 a dispatch failed / 2 pre-flight decline / 3 no credential
/ 4 budget breach (prior cases already written) / 64 bad usage.

Dispatches run against an ISOLATED tree, not the repo. Two separate defects made
that necessary and neither is visible from the recorded output:

  * The plugin under test was never the tree under test. Without `--plugin-dir`
    the CLI resolves `/corpflow:<skill>` from the ambient install, while
    `skill_version()` below reads THIS repo's SKILL.md — so a run could exercise
    one version and stamp another on all 156 records.
  * The answer key was inside the searched tree. `evals.json` carries
    `expected_outcome`, and 7 of 114 responses in the 0.0.1 capture reached the
    corpus; at least 3 read the answer outright.

`--no-isolate` restores the old behaviour for debugging. It must never be used
for a capture whose number will be quoted.
"""

from __future__ import annotations

import argparse
import contextlib
import datetime
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
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
DEFAULT_RETRIES = 2
RETRY_BACKOFF_S = 20.0

# Removed from the capture tree before any dispatch. `evals.json` is the answer
# key proper; labels/findings/splits carry verdicts and tranche membership, and
# the generator holds every prompt beside its expected outcome.
ANSWER_KEY_PATHS = (
    "evals/labels",
    "evals/findings",
    "evals/splits",
    "evals/review",
    "evals/scripts/gen-request-plan-cases.py",
)
ANSWER_KEY_GLOBS = (
    "skills/*/evals/evals.json",
    "skills/*/evals/failure-taxonomy.md",
    "skills/*/evals/responses*",
)
# NOT stripped, deliberately: eval cases ground on evals/scripts/eval-*.py,
# judge-traces.py, build-review-page.py and label-align.py. Removing the whole
# of evals/ would make those cases unanswerable and score the strip as a skill
# failure. The exclusion is the answer key, not the directory.

# The probe that proves both fixes bound before the sweep spends anything.
#
# It asks which COMMANDS are available, not which SKILL.md version is on disk.
# The obvious version question does not work and looked like it did: the model
# answers it by reading the file out of the working directory, so it reported the
# tree's version whether or not the pin bound. Measured on the un-isolated surface
# it still said 0.2.0 while the ambient 4.0.25 was demonstrably the plugin
# answering. The command set is in the model's context rather than on its disk,
# so it cannot be answered by looking.
PROBE_PROMPT = (
    "List every slash command available to you whose name begins with `{plugin}:`. "
    "One bare name per line, no bullets and no other prose. Report what is in your "
    "available command list, not what is on the filesystem. Then, as the final line, "
    "`evals: <how many files match skills/request-plan/evals/evals.json in your "
    "working directory>`."
)

MISSING_CREDENTIAL_MESSAGE = (
    "capture requires credentials; set ANTHROPIC_API_KEY or run claude login"
)


class PreflightError(Exception):
    """Refusal raised before any spend."""


def repo_root() -> str:
    return engine.REPO


@contextlib.contextmanager
def isolated_surface(root: str, base_settings: str | None):
    """The tree a dispatch actually sees, torn down on every exit path.

    One definition for the dry run and the paid run: a dry run that built a
    different surface would print an argv nobody could act on, and the teardown is
    the only thing standing between a failed pre-flight and a stray copy of the
    repo in /tmp.
    """
    tmp_parent = capture_tree = None
    try:
        tmp_parent = tempfile.mkdtemp(prefix="eval-capture-")
        capture_tree = make_capture_tree(root, os.path.join(tmp_parent, "tree"))
        stripped = strip_answer_keys(capture_tree)
        yield capture_tree, stripped, write_capture_settings(root, tmp_parent, base_settings)
    finally:
        if capture_tree:
            remove_capture_tree(root, capture_tree)
        if tmp_parent:
            shutil.rmtree(tmp_parent, ignore_errors=True)


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


def build_argv(model: str, settings_path: str | None,
               plugin_dir: str | None = None) -> list:
    # stream-json, NOT json: `--output-format json` returns only the FINAL assistant
    # message in `result`. A turn that answers and then emits a second message — after a
    # background check returns, say — has its answer silently discarded and the follow-up
    # stored in its place. That is case 187 of the 0.3.0 capture: a plan was written, a
    # follow-up asked whether to save it, and only the follow-up reached disk, where it
    # graded as a failure to plan. Reproduced deliberately: a prompt that says one word,
    # runs a command, then says another word yields result == the second word alone.
    # `--verbose` is required for stream-json under `-p`.
    argv = ["claude", "-p", "--model", model,
            "--permission-mode", PERMISSION_MODE,
            "--output-format", "stream-json", "--verbose"]
    if settings_path:
        argv += ["--settings", settings_path]
    if plugin_dir:
        # Pins the skill to the tree under test. Without it the ambient install
        # answers, and the recorded skill_version describes a file that never ran.
        argv += ["--plugin-dir", plugin_dir]
    return argv


def build_prompt(case: dict, mode: str, skill_name: str) -> str:
    """`command` grades the skill's output; `natural` also grades whether it triggers."""
    if mode == "natural":
        return case["prompt"]
    return f'/corpflow:{skill_name} "{case["prompt"]}"'


def _usage_from(obj: dict) -> dict:
    usage = obj.get("usage") if isinstance(obj.get("usage"), dict) else {}
    return {
        "input_tokens": usage.get("input_tokens"),
        "output_tokens": usage.get("output_tokens"),
        "cache_read_input_tokens": usage.get("cache_read_input_tokens"),
        "cache_creation_input_tokens": usage.get("cache_creation_input_tokens"),
        "cost_usd": obj.get("total_cost_usd"),
    }


def extract_response(stdout: str) -> tuple[str | None, dict]:
    """Return (response_text, usage). Text is None when the CLI yielded none — a
    capture that invents an empty answer would be graded as a real failure.

    Two shapes are accepted. A bare JSON object is the legacy `--output-format json`
    envelope, kept so a stored dispatch from before the stream-json switch still parses.
    NDJSON is the current shape: EVERY assistant text block is concatenated, because the
    envelope's `result` carries only the last message and drops any answer that was
    followed by a second one (see build_argv).
    """
    stripped = stdout.strip()
    if not stripped:
        return None, {}
    try:
        obj = json.loads(stripped)
    except (ValueError, TypeError):
        obj = None
    if isinstance(obj, dict):  # legacy single-envelope form
        if obj.get("is_error") is True or obj.get("subtype") not in (None, "success"):
            return None, {}
        text = obj.get("result")
        if not isinstance(text, str) or not text.strip():
            return None, {}
        return text, _usage_from(obj)
    if obj is not None:
        return None, {}

    blocks, terminal = [], None
    for line in stripped.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            row = json.loads(line)
        except (ValueError, TypeError):
            continue  # a non-JSON line is noise, not a reason to lose the answer
        if not isinstance(row, dict):
            continue
        if row.get("type") == "assistant":
            content = row.get("message", {}).get("content")
            if isinstance(content, list):
                for block in content:
                    if (isinstance(block, dict) and block.get("type") == "text"
                            and isinstance(block.get("text"), str)
                            and block["text"].strip()):
                        blocks.append(block["text"].strip())
        elif row.get("type") == "result":
            terminal = row
    if terminal is None:
        return None, {}  # no terminal event: the dispatch did not finish cleanly
    if terminal.get("is_error") is True or terminal.get("subtype") not in (None, "success"):
        return None, {}
    if not blocks:
        return None, {}
    # Blank line between blocks: they were separate messages, and a plan whose heading
    # ran into the previous sentence would fail template-sections-present on a join.
    return "\n\n".join(blocks), _usage_from(terminal)


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


def assert_clean_tree(root: str) -> None:
    """Refuse to capture from a dirty tree.

    The capture tree is a detached worktree at HEAD, so uncommitted work is not in
    it — a dirty root means `plugin_sha` names a state that never ran. The 0.0.1
    capture recorded `9e2cda9-dirty` for exactly this reason and its provenance
    table calls that marker load-bearing. Cheaper to refuse than to footnote.
    """
    r = run(["git", "-C", root, "status", "--porcelain", "--untracked-files=no"])
    if r.returncode != 0:
        raise PreflightError(f"cannot read git status in {root}")
    if r.stdout.strip():
        raise PreflightError(
            "working tree has uncommitted changes; commit them first — a capture "
            "from a detached HEAD worktree would not contain them, and plugin_sha "
            "would describe a tree that never ran")


def make_capture_tree(root: str, dest: str) -> str:
    """A detached worktree at HEAD, with the answer key removed.

    Tracked-at-HEAD only, which drops `.context/`, `evals/review/` and any
    `responses*/` for free — the prompt-leak lint sweeps `git ls-files --others`
    and so is blind to gitignored files, which is how a per-trace failure map can
    sit in the searched tree without tripping anything.
    """
    r = run(["git", "-C", root, "worktree", "add", "--detach", "--quiet", dest, "HEAD"])
    if r.returncode != 0:
        raise PreflightError(
            f"cannot create capture worktree: {(r.stderr or '').strip()[:300]}")
    return dest


def strip_answer_keys(tree: str) -> list:
    """Delete the answer key from a capture tree. Returns what was removed."""
    removed = []
    targets = [os.path.join(tree, rel) for rel in ANSWER_KEY_PATHS]
    for pattern in ANSWER_KEY_GLOBS:
        targets += sorted(glob.glob(os.path.join(tree, pattern)))
    for path in targets:
        if not os.path.exists(path):
            continue
        if os.path.isdir(path):
            shutil.rmtree(path)
        else:
            os.remove(path)
        removed.append(os.path.relpath(path, tree))
    return sorted(removed)


def remove_capture_tree(root: str, dest: str) -> None:
    run(["git", "-C", root, "worktree", "remove", "--force", dest])
    if os.path.exists(dest):
        shutil.rmtree(dest, ignore_errors=True)
    run(["git", "-C", root, "worktree", "prune"])


def plugin_name(root: str) -> str | None:
    try:
        with open(os.path.join(root, ".claude-plugin", "plugin.json"),
                  encoding="utf-8") as f:
            return json.load(f).get("name")
    except (OSError, ValueError):
        return None


def write_capture_settings(root: str, dest: str, base_path: str | None) -> str | None:
    """Settings that disable the AMBIENT copy of the plugin under test.

    `--plugin-dir` loads the capture tree, but it loads it ALONGSIDE whatever the
    marketplace installed, and the installed copy is a published release that can
    be several versions behind the tree. Disabling it is what makes the pin
    exclusive. Returns None when there is nothing to disable and no base file.
    """
    settings = {}
    if base_path:
        try:
            with open(base_path, encoding="utf-8") as f:
                settings = json.load(f)
        except (OSError, ValueError) as exc:
            raise PreflightError(f"cannot read --settings {base_path}: {exc}")
    name = plugin_name(root)
    if name:
        enabled = dict(settings.get("enabledPlugins") or {})
        user = os.path.expanduser("~/.claude/settings.json")
        try:
            with open(user, encoding="utf-8") as f:
                for key in (json.load(f).get("enabledPlugins") or {}):
                    if key.split("@", 1)[0] == name:
                        enabled[key] = False
        except (OSError, ValueError):
            pass
        if enabled:
            settings["enabledPlugins"] = enabled
    if not settings:
        return None
    path = os.path.join(dest, "capture-settings.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(settings, f, indent=2)
    return path


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


def capture_case(eval_set, case, *, mode, model, settings_path, timeout, cwd,
                 plugin_dir=None, dispatcher=None, retries=DEFAULT_RETRIES, sleeper=None):
    """Dispatch one case. Raises RuntimeError on any outcome that is not a real answer.

    Retries first. A sustained sweep provokes transient refusals — a run at
    concurrency 4 lost 38 consecutive cases to `exited 1` with an empty stderr, and
    the first of them succeeded on a bare retry minutes later. Without this the
    capture is a coin toss against the rate limiter that costs the whole tail, and
    re-running by hand re-pays for nothing.

    Retrying does NOT weaken the never-fabricate contract: every attempt must still
    produce a real answer, and exhausting the attempts still raises rather than
    storing a blank.
    """
    sent_prompt = build_prompt(case, mode, eval_set["skill_name"])
    argv = build_argv(model, settings_path, plugin_dir)
    dispatch = dispatcher or (lambda a, p: run(a, stdin_text=p, timeout=timeout, cwd=cwd))
    pause = sleeper or time.sleep
    last = ""
    for attempt in range(retries + 1):
        if attempt:
            pause(RETRY_BACKOFF_S * (2 ** (attempt - 1)))
        result = dispatch(argv, sent_prompt)
        if result.returncode != 0:
            last = (f"claude -p exited {result.returncode}: "
                    f"{(result.stderr or '').strip()[:300]}")
            continue
        response, usage = extract_response(result.stdout)
        if response is None:
            last = "no response text in CLI output"
            continue
        return sent_prompt, response, usage
    raise RuntimeError(f"case {case['id']}: {last} (after {retries + 1} attempts)")


def probe_expectations(root: str, tree: str) -> tuple:
    """(must_offer, must_not_offer) command names for the capture tree.

    `must_not_offer` is what catches a pin that did not bind: if the installed
    release answered instead of the tree, the commands this tree DELETED are still
    on offer. Derived against the plugin cache rather than hardcoded — 4.0.26 moved
    twenty-two commands and the next release will move more.

    Skill names are subtracted from the deleted set. Both commands and skills are
    invocable as `<plugin>:<name>` and the model lists them together, so a name that
    became a skill would otherwise read as a deleted command still being served.
    """
    tree_cmds = {os.path.basename(f)[:-3]
                 for f in glob.glob(os.path.join(tree, "commands", "*.md"))}
    tree_skills = {os.path.basename(os.path.dirname(f))
                   for f in glob.glob(os.path.join(tree, "skills", "*", "SKILL.md"))}
    name = plugin_name(root)
    ambient = set()
    if name:
        ambient = {os.path.basename(f)[:-3] for f in glob.glob(os.path.expanduser(
            os.path.join("~", ".claude", "plugins", "cache", "*", name, "*",
                         "commands", "*.md")))}
    return tree_cmds, ambient - tree_cmds - tree_skills


def build_probe_prompt(plugin: str) -> str:
    return PROBE_PROMPT.format(plugin=plugin)


def parse_probe(text: str, plugin: str) -> dict:
    """{'names': set, 'evals': int|None} — None for anything unread.

    An enumeration rather than a yes/no, because yes/no does not survive contact
    with the model: asked whether one deleted command was available it answered
    `yes` while that command was demonstrably absent from the list it produced
    moments later. A set can be checked against the tree; a judgement cannot.
    """
    names = set()
    for line in text.splitlines():
        m = re.match(rf"^\s*[-*]?\s*/?{re.escape(plugin)}:([a-z0-9][a-z0-9-]*)\s*$",
                     line.strip(), re.IGNORECASE)
        if m:
            names.add(m.group(1).lower())
    m = re.search(r"^\s*`?evals:\s*`?(\d+)", text, re.MULTILINE)
    return {"names": names, "evals": int(m.group(1)) if m else None}


def probe_capture_surface(*, model, settings_path, timeout, cwd, plugin_dir,
                          prompt, dispatcher=None) -> str:
    """One cheap dispatch that reports which plugin answered and whether the answer
    key is reachable. Its whole point is that the sweep must not start on trust."""
    argv = build_argv(model, settings_path, plugin_dir)
    dispatch = dispatcher or (lambda a, pr: run(a, stdin_text=pr, timeout=timeout, cwd=cwd))
    result = dispatch(argv, prompt)
    if result.returncode != 0:
        raise PreflightError(
            f"probe dispatch exited {result.returncode}: {(result.stderr or '').strip()[:300]}")
    text, _ = extract_response(result.stdout)
    if text is None:
        raise PreflightError("probe dispatch returned no response text")
    return text


def main(argv_in: list) -> int:
    p = argparse.ArgumentParser(prog="eval-capture", add_help=True)
    p.add_argument("--eval-set", required=True)
    p.add_argument("--case", action="append", type=int, default=None)
    p.add_argument("--min-id", type=int, default=None,
                   help="capture only ids at or above this. Set it to the manifest's "
                        "held_out_from to buy a newly pinned tranche without paying "
                        "again for cases an earlier pass already read")
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
    p.add_argument("--no-isolate", action="store_true",
                   help="dispatch against the repo itself, with the eval corpus in it. "
                        "Debugging only; never for a capture whose number is quoted")
    p.add_argument("--probe", action="store_true",
                   help="run only the surface probe (~$0.01) and print what answered")
    p.add_argument("--retries", type=int, default=DEFAULT_RETRIES,
                   help="retries per case on a transient dispatch failure")
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
           if (args.split is None or c.get("split") == args.split)
           and (args.min_id is None or c["id"] >= args.min_id)]
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

    isolate = not args.no_isolate
    # settings_path survives as the validated --settings: it is the value every
    # un-isolated dispatch uses, and isolation replaces it with generated settings.
    capture_tree = None

    if args.dry_run:
        # The argv shown must be the argv that would run, so the isolated surface is
        # built here too. A dry run that prints the un-isolated command would advertise
        # the very defect this refuses to ship.
        with contextlib.ExitStack() as stack:
            if isolate:
                try:
                    capture_tree, stripped, settings_path = stack.enter_context(
                        isolated_surface(root, args.settings))
                    print(json.dumps({"capture_tree": capture_tree,
                                      "stripped": stripped,
                                      "settings": settings_path}, indent=2))
                except PreflightError as exc:
                    sys.stderr.write(f"eval-capture: {exc}\n")
                    return 2
                # Inspecting is free, so a dirty tree only warns here. The paid path
                # refuses: the capture tree is HEAD, so uncommitted work is not in it.
                try:
                    assert_clean_tree(root)
                except PreflightError as exc:
                    sys.stderr.write(f"eval-capture: note (dry run only): {exc}\n")
            for cid in selected:
                case = engine.find_case(eval_set, cid)
                print(json.dumps({
                    "case_id": cid, "mode": args.mode, "model": args.model,
                    "cwd": capture_tree or root,
                    "argv": build_argv(args.model, settings_path, capture_tree),
                    "sent_prompt": build_prompt(case, args.mode, eval_set["skill_name"]),
                    "out": os.path.join(out_dir, f"{cid}.json"),
                }, indent=2))
        return 0

    if not has_credential():
        sys.stderr.write(MISSING_CREDENTIAL_MESSAGE + "\n")
        return 3

    if isolate:
        try:
            assert_clean_tree(root)
        except PreflightError as exc:
            sys.stderr.write(f"eval-capture: {exc}\n")
            return 2

    expected_version = skill_version(root, eval_set["skill_name"])
    with contextlib.ExitStack() as stack:
        if isolate:
            capture_tree, stripped, settings_path = stack.enter_context(
                isolated_surface(root, args.settings))
            print(f"capture tree: {capture_tree}")
            print(f"answer-key paths removed: {len(stripped)} -> {stripped}")
        else:
            sys.stderr.write(
                "eval-capture: WARNING --no-isolate: dispatching against the repo, so "
                "the eval corpus is readable and the ambient plugin answers. Any number "
                "from this run is uncomparable.\n")

        cwd = capture_tree or root
        plugin = plugin_name(root) or "corpflow"
        must_offer, must_not_offer = probe_expectations(root, cwd)
        if not must_offer:
            sys.stderr.write("eval-capture: no commands/ in the capture tree\n")
            return 2
        try:
            probe_text = probe_capture_surface(
                model=args.model, settings_path=settings_path, timeout=args.timeout,
                cwd=cwd, plugin_dir=capture_tree, prompt=build_probe_prompt(plugin))
        except PreflightError as exc:
            sys.stderr.write(f"eval-capture: {exc}\n")
            return 2
        seen = parse_probe(probe_text, plugin)
        missing = sorted(must_offer - seen["names"])
        leaked = sorted(must_not_offer & seen["names"])
        print(f"probe: {len(seen['names'])} commands offered, "
              f"{len(must_offer)} expected, {len(missing)} missing, "
              f"{len(leaked)} from a release this tree deleted, "
              f"evals_files={seen['evals']}")
        if args.probe:
            print(probe_text)
            return 0

        if isolate:
            if not seen["names"] or seen["evals"] is None:
                sys.stderr.write(
                    "eval-capture: probe unreadable; refusing to spend on an "
                    f"unverified surface. Raw: {probe_text.strip()[:300]}\n")
                return 2
            if missing:
                sys.stderr.write(
                    f"eval-capture: the plugin that answered does not offer "
                    f"{missing}, which this tree ships. --plugin-dir did not bind.\n")
                return 2
            if leaked:
                sys.stderr.write(
                    f"eval-capture: the plugin that answered still offers {leaked}, which "
                    "this tree deleted — the installed release answered, not the tree. "
                    "The run would measure one version and stamp another.\n")
                return 2
            if seen["evals"] != 0:
                sys.stderr.write(
                    f"eval-capture: the answer key is still reachable ({seen['evals']} "
                    "match(es) for evals.json). Refusing.\n")
                return 2

        os.makedirs(out_dir, exist_ok=True)
        provenance = {
            "captured_at": datetime.datetime.now(datetime.timezone.utc)
                                   .replace(microsecond=0).isoformat().replace("+00:00", "Z"),
            "plugin_sha": plugin_sha(root),
            "skill_version": expected_version,
            "isolated": bool(capture_tree),
            "probe": {"commands_offered": len(seen["names"]),
                      "commands_expected": len(must_offer), "evals_files": seen["evals"]},
        }
        return _sweep(args, eval_set, selected, out_dir, provenance,
                      settings_path=settings_path, cwd=cwd, plugin_dir=capture_tree)


def _sweep(args, eval_set, selected, out_dir, provenance, *,
           settings_path, cwd, plugin_dir) -> int:
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
            settings_path=settings_path, timeout=args.timeout, cwd=cwd,
            plugin_dir=plugin_dir, retries=args.retries)
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
