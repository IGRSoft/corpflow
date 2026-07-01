"""Shared loader for the DV0e live-gate tests.

`benchmark/live/` is loaded BY PATH (not via package import) so the tests can:
  - inject a FAKE dispatcher (no real `claude agents run`, no spend),
  - inject a FAKE estimate runner (no subprocess to estimate-calc.py),
  - and assert the default benchmark path never imports the module at all.

No test in this directory ever performs a network or LLM call.
"""

from __future__ import annotations

import importlib.util
import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))            # benchmark/tests/live/
_BENCH = os.path.dirname(os.path.dirname(_HERE))              # benchmark/
_LIVE = os.path.join(_BENCH, "live")                          # benchmark/live/
PLUGIN_ROOT = os.path.dirname(_BENCH)


def _load_by_path(mod_name: str, file_path: str):
    """Import a module from an explicit file path (hyphenated dirs aren't packages)."""
    # benchmark/live imports siblings (credentials, budget, metrics) by bare name,
    # so make benchmark/live and benchmark/lib importable while loading.
    for p in (_LIVE, os.path.join(_BENCH, "lib")):
        if p not in sys.path:
            sys.path.insert(0, p)
    spec = importlib.util.spec_from_file_location(mod_name, file_path)
    assert spec and spec.loader, f"cannot load {file_path}"
    mod = importlib.util.module_from_spec(spec)
    # Register BEFORE exec so @dataclass's _is_type() can resolve cls.__module__
    # (Python 3.14 dataclasses look the module up in sys.modules during decoration).
    sys.modules[mod_name] = mod
    spec.loader.exec_module(mod)
    return mod


def load_dispatch():
    return _load_by_path("dv0e_dispatch", os.path.join(_LIVE, "dispatch.py"))


def load_budget():
    return _load_by_path("dv0e_budget", os.path.join(_LIVE, "budget.py"))


def load_credentials():
    return _load_by_path("dv0e_credentials", os.path.join(_LIVE, "credentials.py"))


class TripwireDispatcher:
    """A dispatcher that FAILS LOUDLY if ever called.

    Used to prove the default path never dispatches and to guard tests that must
    abort BEFORE the breaching stage. Calling it is a test failure, not an LLM call.
    """

    def __init__(self) -> None:
        self.called = False

    def __call__(self, argv, *, prompt_path):  # noqa: ANN001
        self.called = True
        raise AssertionError(
            "TRIPWIRE: real dispatcher was invoked — no LLM call may happen in tests"
        )


class RecordingFakeDispatcher:
    """A fake dispatcher returning canned stdout per call. Records every argv.

    NEVER shells out. `outputs` is a list of stdout strings consumed in order; once
    exhausted it returns "{}" (Layer-1 parse yields no usage -> Layer 3 degradation).
    """

    def __init__(self, outputs=None) -> None:
        self.outputs = list(outputs or [])
        self.calls = []

    def __call__(self, argv, *, prompt_path):  # noqa: ANN001
        self.calls.append((list(argv), prompt_path))
        if self.outputs:
            return self.outputs.pop(0)
        return "{}"


def fake_estimate_runner(per_stage_usd: float):
    """Return a budget.estimate_stage_cost-compatible runner yielding a fixed cost.

    The runner returns estimate-calc.py-shaped JSON so the REAL parse path is
    exercised, but no subprocess runs.
    """
    import json

    def _runner(argv):  # noqa: ANN001
        return json.dumps({"ai_cost": {"usd": per_stage_usd}})

    return _runner
