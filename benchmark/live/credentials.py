"""benchmark/live/credentials.py — fail-fast credential probe (DV0e).

Live mode requires an Anthropic credential before ANY stage is dispatched. This
module checks for it and fails fast with a clear, actionable message. The key
VALUE is NEVER printed, logged, echoed into argv, or written to any record — only
its presence/absence is ever observed.

Contract (AC-8, mandate):
  - check ANTHROPIC_API_KEY before stage 1.
  - if absent (unset or empty/whitespace) -> raise CredentialError with EXACTLY:
      "live mode requires credentials; set ANTHROPIC_API_KEY or run claude login"
  - never reveal the key value.
"""

from __future__ import annotations

import os

CREDENTIAL_ENV = "ANTHROPIC_API_KEY"

MISSING_CREDENTIAL_MESSAGE = (
    "live mode requires credentials; set ANTHROPIC_API_KEY or run claude login"
)


class CredentialError(RuntimeError):
    """Raised when no live-mode credential is present. Message is safe to print."""


def has_credential(env: dict[str, str] | None = None) -> bool:
    """Return True iff a non-empty ANTHROPIC_API_KEY is present.

    `env` defaults to os.environ; injectable for tests. Only presence is observed
    — the value is never returned, logged, or compared against anything.
    """
    source = os.environ if env is None else env
    value = source.get(CREDENTIAL_ENV)
    return value is not None and value.strip() != ""


def require_credential(env: dict[str, str] | None = None) -> None:
    """Raise CredentialError (with the frozen message) when no credential exists.

    Never includes the key value in the exception — the message is a static string.
    """
    if not has_credential(env):
        raise CredentialError(MISSING_CREDENTIAL_MESSAGE)


__all__ = [
    "CREDENTIAL_ENV",
    "MISSING_CREDENTIAL_MESSAGE",
    "CredentialError",
    "has_credential",
    "require_credential",
]
