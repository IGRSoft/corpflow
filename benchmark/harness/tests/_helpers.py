"""Test doubles for the live suite — NO test here ever calls network/LLM/spend.

Fakes: TripwireDispatcher (raises if dispatched), RecordingFakeDispatcher (records
calls, returns canned stdout), ThrowAtStageDispatcher (crash at stage N),
SequencedFakeDispatcher (per-call stdout, repeats the last once exhausted).
Injectable runners for estimate / auth-status / git-sha. make_live_sandbox builds a
throwaway benchmark tree (incl. the WITHOUT prompt); single_object_usage /
stream_json build capture stdout.
"""

from __future__ import annotations

import json
import os
from types import SimpleNamespace

from benchmarklive import budget as _budget
from benchmarklive.dispatch import DispatchFailure

_STAGE_FILES = ["pl", "ar", "tl", "dv", "dr", "sr", "qa", "dc", "fn", "st"]


# ----- capture stdout builders --------------------------------------------

def single_object_usage(input_tokens=100, output_tokens=50, cost=0.01,
                        cache_read=None, cache_creation=None) -> str:
    usage = {"input_tokens": input_tokens, "output_tokens": output_tokens}
    if cache_read is not None:
        usage["cache_read_input_tokens"] = cache_read
    if cache_creation is not None:
        usage["cache_creation_input_tokens"] = cache_creation
    return json.dumps({"type": "result", "usage": usage, "total_cost_usd": cost})


def stream_json(tool_uses=None, result_usage=True, cost=0.02) -> str:
    """Build NDJSON: one assistant event with tool_use blocks + a terminal result."""
    lines = []
    content = []
    for name, inp in (tool_uses or []):
        content.append({"type": "tool_use", "name": name, "input": inp})
    if content:
        lines.append(json.dumps({"type": "assistant", "message": {"content": content}}))
    if result_usage:
        lines.append(single_object_usage(cost=cost))
    else:
        lines.append(json.dumps({"type": "assistant", "message": {"content": []}}))
    return "\n".join(lines)


# ----- injectable runners -------------------------------------------------

def fake_estimate_runner(cost: float):
    def _runner(argv):
        return json.dumps({"ai_cost": {"usd": cost}})
    return _runner


def logged_in_runner() -> str:
    return json.dumps({"loggedIn": True, "email": "REDACTED", "orgId": "REDACTED"})


def logged_out_runner() -> str:
    return json.dumps({"loggedIn": False})


def tripwire_runner():
    def _runner():
        raise AssertionError("CLI login runner must not be called (env key short-circuits)")
    return _runner


def stub_git_sha(_root: str) -> str:
    return "abc1234"


# ----- dispatchers --------------------------------------------------------

class TripwireDispatcher:
    def run(self, argv, prompt_text):
        raise AssertionError("dispatcher must not be called on this path")


class RecordingFakeDispatcher:
    def __init__(self, stdout=None):
        self.calls = []
        self._stdout = stdout if stdout is not None else single_object_usage()

    def run(self, argv, prompt_text):
        self.calls.append((list(argv), prompt_text))
        return self._stdout


class ThrowAtStageDispatcher:
    """Succeed for stages 1..N-1, raise DispatchFailure on stage N (1-based)."""

    def __init__(self, throw_at, stdout=None):
        self.throw_at = throw_at
        self.count = 0
        self._stdout = stdout if stdout is not None else single_object_usage()

    def run(self, argv, prompt_text):
        self.count += 1
        if self.count == self.throw_at:
            raise DispatchFailure(f"boom at stage {self.count}")
        return self._stdout


class SequencedFakeDispatcher:
    """Returns one stdout per call in order; repeats the last once exhausted."""

    def __init__(self, stdouts):
        self.stdouts = list(stdouts)
        self.calls = []

    def run(self, argv, prompt_text):
        self.calls.append((list(argv), prompt_text))
        idx = min(len(self.calls) - 1, len(self.stdouts) - 1)
        return self.stdouts[idx]


# ----- sandbox ------------------------------------------------------------

def make_live_sandbox(tmp: str, run_id: str = "live-test", state_json: str = "{}"):
    benchmark_dir = os.path.join(tmp, "benchmark")
    workdir_path = os.path.join(benchmark_dir, "workdirs", run_id)
    os.makedirs(os.path.join(workdir_path, ".context", "logs"), exist_ok=True)
    with open(os.path.join(workdir_path, ".context", "state.json"), "w", encoding="utf-8") as f:
        f.write(state_json)
    open(os.path.join(workdir_path, ".context", "logs", "audit.jsonl"), "w").close()
    prompts_dir = os.path.join(benchmark_dir, "live", "prompts")
    os.makedirs(prompts_dir, exist_ok=True)
    for s in _STAGE_FILES:
        with open(os.path.join(prompts_dir, f"{s}.txt"), "w", encoding="utf-8") as f:
            f.write(f"[5] task body for {s}\n")
    with open(os.path.join(prompts_dir, "without.txt"), "w", encoding="utf-8") as f:
        f.write("build the app, verbatim, no preamble\n")
    record_path = os.path.join(benchmark_dir, "results", "runs", "live", f"{run_id}.json")
    return SimpleNamespace(
        benchmark_dir=benchmark_dir, workdir_path=workdir_path,
        prompts_dir=prompts_dir, record_path=record_path, run_id=run_id)


def section(label: str) -> str:
    """Small marker helper for assembled-prompt assertions."""
    return f"<<<{label}>>>"


def load_json(path: str):
    """Read + parse a JSON file, closing the handle (no ResourceWarning)."""
    with open(path, encoding="utf-8") as f:
        return json.load(f)
