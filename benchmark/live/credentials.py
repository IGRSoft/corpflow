"""benchmark/live/credentials.py — fail-fast credential probe (DV0e).

Live mode requires an Anthropic credential before ANY stage is dispatched. This
module checks for it and fails fast with a clear, actionable message. Neither
the API key VALUE nor any CLI-login identity detail (email/org) is EVER printed,
logged, echoed into argv, or written to any record — only boolean presence is
ever observed.

Two credential SOURCES are accepted (Batch 1c — `ud2`, credential-path
evolution): the original `ANTHROPIC_API_KEY` env var, OR an existing `claude`
CLI login (subscription auth via `claude auth status`). The second source
matters because `.context/.env.local` in this repo's own dev environment holds
an OAuth-token-shaped value that 401s when exported as `ANTHROPIC_API_KEY` (and
would override a working machine login if it were sourced) — so the gate must
not treat "no usable API key env var" as "cannot run live," when a valid CLI
login is the actual credential source for that run.

Detection (cheap, non-interactive, no dispatch/spend):
  `claude auth status --json` — a read-only status query (not `agents run` /
  `-p`), returns `{"loggedIn": bool, ...}` plus identity fields (email, orgId)
  that this module NEVER surfaces past the boolean. Injectable via `runner`
  (mirrors the `dispatcher`/`estimate_runner` DI seam elsewhere in this
  package) so tests never shell out.

Contract (AC-8, mandate; extended by Batch 1c):
  - check ANTHROPIC_API_KEY OR `claude auth status --json .loggedIn` before
    stage 1.
  - if BOTH are absent -> raise CredentialError with EXACTLY:
      "live mode requires credentials; set ANTHROPIC_API_KEY or run claude login"
  - never reveal the key value or any CLI-login identity field (email/org).
"""

from __future__ import annotations

import json
import os
import subprocess

CREDENTIAL_ENV = "ANTHROPIC_API_KEY"

MISSING_CREDENTIAL_MESSAGE = (
    "live mode requires credentials; set ANTHROPIC_API_KEY or run claude login"
)


class CredentialError(RuntimeError):
    """Raised when no live-mode credential is present. Message is safe to print."""


def _default_auth_status_runner() -> str:
    """Production runner: `claude auth status --json`, read-only, no spend.

    Returns stdout (may be malformed/non-JSON on unexpected CLI builds — the
    caller is defensive). Never raises on a non-zero exit; a CLI that can't
    answer the status query is treated as "not logged in" by the caller, not
    as a hard error (the ANTHROPIC_API_KEY path remains available).
    """
    try:
        completed = subprocess.run(
            ["claude", "auth", "status", "--json"],
            capture_output=True, text=True, check=False, timeout=10,
        )
        return completed.stdout
    except (OSError, subprocess.SubprocessError):
        return ""


def has_cli_login(runner=None) -> bool:
    """Return True iff `claude auth status --json` reports `loggedIn: true`.

    `runner` is an injectable zero-arg callable -> stdout string (tests inject
    a fake; never a real subprocess in the suite). Defensive on every failure
    mode (bad JSON, missing key, non-dict) -> False, never fabricates. Only the
    boolean is ever returned — `email`/`orgId`/`authMethod` etc. are read by
    the runner's real subprocess but NEVER touch this function's return value,
    logs, or any exception message.
    """
    run = runner or _default_auth_status_runner
    try:
        stdout = run()
    except (OSError, subprocess.SubprocessError):
        return False
    try:
        obj = json.loads(stdout)
    except (json.JSONDecodeError, TypeError):
        return False
    if not isinstance(obj, dict):
        return False
    return obj.get("loggedIn") is True


def has_credential(env: dict[str, str] | None = None, *, cli_login_runner=None) -> bool:
    """Return True iff a usable Anthropic credential exists via EITHER source.

    Source 1: a non-empty ANTHROPIC_API_KEY in `env` (defaults to os.environ).
    Source 2: an active `claude` CLI login (`has_cli_login`), checked ONLY when
    source 1 is absent (cheap short-circuit; avoids an unnecessary subprocess
    when the env var already satisfies the gate). `cli_login_runner` is
    injectable for tests (mirrors `env` injectability for source 1).
    Only presence is observed for either source — no value/identity detail is
    ever returned, logged, or compared against anything.
    """
    source = os.environ if env is None else env
    value = source.get(CREDENTIAL_ENV)
    if value is not None and value.strip() != "":
        return True
    return has_cli_login(runner=cli_login_runner)


def require_credential(
    env: dict[str, str] | None = None, *, cli_login_runner=None
) -> None:
    """Raise CredentialError (with the frozen message) when no credential exists.

    Never includes the key value, CLI-login identity, or any distinguishing
    detail in the exception — the message is a static string regardless of
    which source (or neither) was checked.
    """
    if not has_credential(env, cli_login_runner=cli_login_runner):
        raise CredentialError(MISSING_CREDENTIAL_MESSAGE)


__all__ = [
    "CREDENTIAL_ENV",
    "MISSING_CREDENTIAL_MESSAGE",
    "CredentialError",
    "has_credential",
    "has_cli_login",
    "require_credential",
]
