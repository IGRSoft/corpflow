"""Fail-fast credential probe.

Live mode requires an Anthropic credential before ANY stage is dispatched. Two
sources: ANTHROPIC_API_KEY (checked FIRST — cheap short-circuit) OR an active
`claude` CLI login. Neither the key value nor any CLI-login identity is EVER
printed, logged, echoed into argv, or written to a record — only boolean presence.
rc=3 semantics live in dispatch.dispatch.
"""

from __future__ import annotations

import json
import os
from typing import Callable, Optional

from benchmarkkit.genlib import Subprocess

CREDENTIAL_ENV = "ANTHROPIC_API_KEY"

# Frozen error message (byte-exact contract; ported tests assert equality).
MISSING_CREDENTIAL_MESSAGE = (
    "live mode requires credentials; set ANTHROPIC_API_KEY or run claude login"
)


class CredentialError(Exception):
    def __init__(self) -> None:
        super().__init__(MISSING_CREDENTIAL_MESSAGE)


def default_auth_status_runner() -> str:
    """Production runner: `claude auth status --json`, read-only, no spend."""
    return Subprocess.run(["claude", "auth", "status", "--json"]).stdout


def has_cli_login(runner: Optional[Callable[[], str]] = None) -> bool:
    """True iff `claude auth status --json` reports loggedIn: true. Defensive → False.

    Only the boolean is ever returned — email/orgId/authMethod never surface.
    """
    run = runner or default_auth_status_runner
    try:
        stdout = run()
    except Exception:
        return False
    try:
        parsed = json.loads(stdout)
    except (ValueError, TypeError):
        return False
    return isinstance(parsed, dict) and parsed.get("loggedIn") is True


def has_credential(env: Optional[dict] = None,
                   cli_login_runner: Optional[Callable[[], str]] = None) -> bool:
    """True iff a usable credential exists via either source. Env key short-circuits."""
    source = env if env is not None else os.environ
    value = source.get(CREDENTIAL_ENV)
    if value is not None and value.strip():
        return True
    return has_cli_login(runner=cli_login_runner)


def require_credential(env: Optional[dict] = None,
                       cli_login_runner: Optional[Callable[[], str]] = None) -> None:
    """Raise CredentialError (frozen message) when no credential exists."""
    if not has_credential(env=env, cli_login_runner=cli_login_runner):
        raise CredentialError()
