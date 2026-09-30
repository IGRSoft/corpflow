"""Where the arms run: outside the corpflow repo, each in a git repo of its own.

A workdir nested in the repo lets a stage read the harness, the held-out oracle and
the DV prompt, and makes ``git rev-parse --show-toplevel`` resolve to corpflow instead
of the arm. Arms therefore live under a scratch root; the run's captures stay under
``benchmark/workdirs/<run_id>/`` and each arm is symlinked there, so every path the
analyzer and the report already read keeps resolving.
"""

from __future__ import annotations

import os
from typing import Callable, Optional

from benchmarkkit.genlib import Subprocess

WORKDIR_ROOT_ENV = "BENCH_WORKDIR_ROOT"
DEFAULT_ROOT_NAME = "corpflow-bench"

# The integration branch ledger_seed stamps as ``base_ref`` when PL stamped none.
_BASE_BRANCH = "master"

# (argv, cwd) -> object with .exit_code / .stderr. Injected by tests.
GitRunner = Callable[[list, str], object]


def resolve_workdir_root(explicit: Optional[str] = None, env: Optional[dict] = None) -> str:
    """Absolute, symlink-resolved scratch root: ``--workdir-root``, else
    ``BENCH_WORKDIR_ROOT``, else ``${TMPDIR:-/tmp}/corpflow-bench``.

    Resolved so the path a stage sees from ``git rev-parse`` is the one the harness holds
    (macOS ``/var`` is a symlink to ``/private/var``).
    """
    source = env if env is not None else os.environ
    chosen = explicit or source.get(WORKDIR_ROOT_ENV)
    if not chosen:
        tmp = source.get("TMPDIR") or os.environ.get("TMPDIR") or "/tmp"
        chosen = os.path.join(tmp, DEFAULT_ROOT_NAME)
    return os.path.realpath(os.path.abspath(os.path.expanduser(chosen)))


def _git(argv: list, cwd: str) -> object:
    return Subprocess.run(["git"] + argv, cwd=cwd)


def init_arm_repo(path: str, runner: Optional[GitRunner] = None) -> Optional[str]:
    """Make ``path`` its own git repo with one empty commit; None on success, else why not.

    The commit is empty so a stage sees a clean tree and a resolvable ``HEAD``. Identity
    and signing are passed per call, never read from the operator's config. Idempotent:
    an existing repo is left alone.
    """
    run = runner or _git
    os.makedirs(path, exist_ok=True)
    if os.path.exists(os.path.join(path, ".git")):
        return None
    steps = (
        ["init", "-q", "-b", _BASE_BRANCH],
        ["-c", "user.name=corpflow-bench", "-c", "user.email=bench@localhost",
         "-c", "commit.gpgsign=false", "commit", "-q", "--allow-empty",
         "-m", "bench: arm baseline"],
    )
    for argv in steps:
        result = run(argv, path)
        if result.exit_code != 0:
            step = "commit" if "commit" in argv else argv[0]
            return f"git {step} rc={result.exit_code} {(result.stderr or '').strip()[:200]}"
    return None


def link_persisted(persist_dir: str, arm: str, arm_dir: str) -> Optional[str]:
    """Point ``<persist_dir>/<arm>`` at the arm's scratch dir; None on success, else why not.

    An existing entry is never replaced: it may be a real arm dir from an earlier run.
    """
    link = os.path.join(persist_dir, arm)
    try:
        os.makedirs(persist_dir, exist_ok=True)
        if os.path.lexists(link):
            return None if os.path.realpath(link) == os.path.realpath(arm_dir) \
                else f"{link} already exists and is not {arm_dir}"
        os.symlink(arm_dir, link)
    except OSError as exc:
        return f"cannot link {link} -> {arm_dir}: {exc}"
    return None
