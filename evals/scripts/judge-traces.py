#!/usr/bin/env python3
"""judge-traces — one isolated Opus task per trace, returning a pass/fail verdict.

NOT a substitute for the human labelling pass, and no longer wired to anything.
Measured against the only human labels this repo has had, this judge scored
**TNR 0%**: it caught 0 of the 26 failures the humans found, passing every one.
A grader that never says fail carries no information, so `label-align.py` dropped
its column and nothing downstream reads its output. It is kept for the isolation
technique below, not for its verdicts.

Before any verdict from it is used again it has to be validated on labels it did
not see, per `evals/README.md`. Until then treat output as unlabelled.

Each trace is judged by a fresh session that sees ONLY the request and the
response: it runs in an empty temp directory with every file and exec tool denied
and MCP stripped, so it cannot verify claims against the repo and must judge the
plan on its own terms.

Running in a temp cwd rather than the repo is deliberate. Denying tools alone did
not hold — an isolated probe still reported an exact tracked-file census, so the
only reliable isolation is having no repo to look at.

Usage: judge-traces.py [--responses DIR] [--out PATH] [--case ID]... [--limit N]
                       [--budget USD] [--concurrency N] [--model M] [--effort E]
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import subprocess
import sys
import tempfile
import threading
from concurrent import futures

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DENY = ["Read", "Glob", "Grep", "Bash", "Edit", "Write", "NotebookEdit", "NotebookRead",
        "LS", "Task", "Agent", "Skill", "SlashCommand", "WebFetch", "WebSearch"]

RUBRIC = """You are judging one response from a planning assistant.

You can see only the request and the response. You have no file access and cannot
check the repository the response refers to. Judge the response on its own terms.

The single question: **would this response move the requester forward?**

PASS when the response either:
  - gives a plan specific enough to act on: a stated goal, what is in and out of
    scope, ordered phases, and a concrete next step; or
  - declines to plan and asks a question that is genuinely necessary, because the
    request is underspecified or rests on a false premise.

FAIL when the response:
  - restates the request without adding structure or decisions;
  - is generic enough that it would fit any project (no specific surfaces, files,
    or mechanisms named);
  - asserts specifics that read as invented rather than reasoned;
  - asks a question that the request already answers;
  - or gives a plan whose phases are arbitrary rather than ordered by risk or value.

Do not reward length, formatting, or headings. A short correct question beats a
long generic plan. Do not penalise a response for admitting it lacks file access.

Reply with ONLY a fenced json block:

```json
{"verdict": "pass" | "fail", "note": "<one line: what is right or wrong, concrete>"}
```
"""


def run(argv, stdin_text=None, timeout=None, cwd=None):
    try:
        return subprocess.run(argv, cwd=cwd, input=stdin_text,
                              stdin=None if stdin_text is not None else subprocess.DEVNULL,
                              capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return subprocess.CompletedProcess(argv, 124, "", f"timed out after {timeout}s")
    except (OSError, ValueError) as exc:
        return subprocess.CompletedProcess(argv, 127, "", f"spawn failed: {exc}")


def parse_verdict(text: str):
    """Pull the fenced verdict. Returns None rather than guessing at a malformed one."""
    start = text.find("```json")
    blob = text[start + 7:] if start >= 0 else text
    end = blob.find("```")
    if end >= 0:
        blob = blob[:end]
    try:
        obj = json.loads(blob.strip())
    except (ValueError, TypeError):
        return None
    if not isinstance(obj, dict) or obj.get("verdict") not in ("pass", "fail"):
        return None
    return {"verdict": obj["verdict"], "note": str(obj.get("note", ""))[:400]}


def judge(trace, model, effort, timeout):
    prompt = (f"{RUBRIC}\n\n=== REQUEST ===\n{trace['prompt']}\n\n"
              f"=== RESPONSE ===\n{trace['response']}\n")
    argv = ["claude", "-p", "--model", model, "--effort", effort,
            "--permission-mode", "bypassPermissions", "--output-format", "json",
            "--mcp-config", '{"mcpServers":{}}', "--strict-mcp-config",
            "--disallowed-tools", *DENY]
    # Empty cwd: no repo present, so no injected project context to leak through.
    with tempfile.TemporaryDirectory(prefix="judge-") as sandbox:
        result = run(argv, stdin_text=prompt, timeout=timeout, cwd=sandbox)
    if result.returncode != 0:
        raise RuntimeError(f"case {trace['id']}: exited {result.returncode}: "
                           f"{(result.stderr or '').strip()[:200]}")
    try:
        obj = json.loads(result.stdout)
    except (ValueError, TypeError):
        raise RuntimeError(f"case {trace['id']}: unparseable CLI output")
    verdict = parse_verdict(obj.get("result") or "")
    if verdict is None:
        raise RuntimeError(f"case {trace['id']}: no usable verdict in reply")
    verdict["cost_usd"] = obj.get("total_cost_usd")
    return verdict


def main(argv_in) -> int:
    p = argparse.ArgumentParser(prog="judge-traces")
    p.add_argument("--eval-set", default=os.path.join(REPO, "skills", "request-plan", "evals", "evals.json"))
    p.add_argument("--responses", default=None)
    p.add_argument("--out", default=os.path.join(REPO, "evals", "judgements", "request-plan.jsonl"))
    p.add_argument("--case", action="append", type=int, default=None)
    p.add_argument("--limit", type=int, default=None)
    p.add_argument("--model", default="claude-opus-5-5")
    p.add_argument("--effort", default="max")
    p.add_argument("--budget", type=float, default=None)
    p.add_argument("--timeout", type=float, default=280.0)
    p.add_argument("--concurrency", type=int, default=4)
    args = p.parse_args(argv_in)

    with open(args.eval_set, encoding="utf-8") as f:
        eval_set = json.load(f)
    cases = {c["id"]: c for c in eval_set["evals"]}
    responses = args.responses or os.path.join(os.path.dirname(args.eval_set), "responses")

    traces = []
    for path in sorted(glob.glob(os.path.join(responses, "*.json")),
                       key=lambda x: int(os.path.basename(x)[:-5])):
        with open(path, encoding="utf-8") as f:
            rec = json.load(f)
        case = cases.get(rec["case_id"])
        if case is None or (args.case and rec["case_id"] not in args.case):
            continue
        traces.append({"id": rec["case_id"], "prompt": case["prompt"],
                       "response": rec["response"], "split": case.get("split"),
                       **case.get("dimensions", {})})
    if args.limit:
        traces = traces[:args.limit]
    if not traces:
        sys.stderr.write("judge-traces: no traces matched\n")
        return 64

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    done = {}
    if os.path.exists(args.out):
        with open(args.out, encoding="utf-8") as f:
            for line in f:
                try:
                    row = json.loads(line)
                    done[row["case_id"]] = row
                except (ValueError, KeyError):
                    continue
    todo = [t for t in traces if t["id"] not in done]
    print(f"{len(todo)} to judge ({len(done)} already done)")

    state = {"spent": 0.0, "breached": False}
    lock = threading.Lock()
    failures = []

    def work(trace):
        if state["breached"]:
            return
        verdict = judge(trace, args.model, args.effort, args.timeout)
        row = {"case_id": trace["id"], "verdict": verdict["verdict"], "note": verdict["note"],
               "split": trace.get("split"), "type": trace.get("type"),
               "grounding": trace.get("grounding"), "route": trace.get("route"),
               "judge_model": args.model, "judge_effort": args.effort,
               "cost_usd": verdict.get("cost_usd")}
        with lock:
            with open(args.out, "a", encoding="utf-8") as f:
                f.write(json.dumps(row, ensure_ascii=False) + "\n")
            if isinstance(verdict.get("cost_usd"), (int, float)):
                state["spent"] += float(verdict["cost_usd"])
            if args.budget is not None and state["spent"] > args.budget:
                state["breached"] = True
            print(f"  case {trace['id']:3} {verdict['verdict'].upper():4} "
                  f"(${state['spent']:.2f})", flush=True)

    with futures.ThreadPoolExecutor(max_workers=max(1, args.concurrency)) as pool:
        for trace, fut in [(t, pool.submit(work, t)) for t in todo]:
            try:
                fut.result()
            except RuntimeError as exc:
                sys.stderr.write(f"judge-traces: {exc}\n")
                failures.append(trace["id"])

    if state["breached"]:
        sys.stderr.write(f"judge-traces: budget breached (${state['spent']:.2f})\n")
        return 4
    if failures:
        sys.stderr.write(f"judge-traces: {len(failures)} failed: {failures}\n")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
