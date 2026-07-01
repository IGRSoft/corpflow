"""benchmark/tests/live/test_credential_probe.py — AC-8 credential gate (DV0e).

With ANTHROPIC_API_KEY unset, the adapter fast-exits BEFORE any dispatch with the
frozen message and never reveals a key value. All checks use an injected env dict and
a tripwire dispatcher — no network, no spend.
"""

from __future__ import annotations

import io
import os
import tempfile
import unittest
from contextlib import redirect_stderr

from _helpers import load_dispatch, load_credentials, TripwireDispatcher

FROZEN_MESSAGE = (
    "live mode requires credentials; set ANTHROPIC_API_KEY or run claude login"
)


class TestCredentialModule(unittest.TestCase):
    def test_absent_key_raises_with_frozen_message(self):
        cred = load_credentials()
        with self.assertRaises(cred.CredentialError) as ctx:
            cred.require_credential({})  # empty env -> no key
        self.assertEqual(str(ctx.exception), FROZEN_MESSAGE)

    def test_empty_or_whitespace_key_counts_as_absent(self):
        cred = load_credentials()
        self.assertFalse(cred.has_credential({"ANTHROPIC_API_KEY": ""}))
        self.assertFalse(cred.has_credential({"ANTHROPIC_API_KEY": "   "}))

    def test_present_key_passes(self):
        cred = load_credentials()
        self.assertTrue(cred.has_credential({"ANTHROPIC_API_KEY": "sk-xxx"}))
        cred.require_credential({"ANTHROPIC_API_KEY": "sk-xxx"})  # no raise

    def test_message_never_contains_a_key_value(self):
        cred = load_credentials()
        secret = "sk-SUPERSECRET-DO-NOT-LEAK"
        # Probe with the secret present should not raise; with absent it must not
        # echo any prior value (the message is static).
        try:
            cred.require_credential({"ANTHROPIC_API_KEY": secret})
        except cred.CredentialError as exc:  # pragma: no cover
            self.assertNotIn(secret, str(exc))
        self.assertNotIn(secret, cred.MISSING_CREDENTIAL_MESSAGE)


class TestDispatchCredentialGate(unittest.TestCase):
    def test_dispatch_fast_exits_without_credential(self):
        dispatch = load_dispatch()
        tripwire = TripwireDispatcher()
        buf = io.StringIO()
        with tempfile.TemporaryDirectory() as tmp:
            record = os.path.join(tmp, "rec.json")
            with redirect_stderr(buf):
                rc = dispatch.dispatch(
                    workdir="cred-missing",
                    budget=10_000.0,
                    record_path=record,
                    dispatcher=tripwire,
                    env={},  # NO credential
                )
            self.assertNotEqual(rc, 0)            # fast non-zero exit
            self.assertFalse(tripwire.called)     # dispatched nothing
            self.assertFalse(os.path.isfile(record))  # no record on fast-exit
            self.assertIn(FROZEN_MESSAGE, buf.getvalue())

    def test_dispatch_never_prints_the_key_value(self):
        dispatch = load_dispatch()
        tripwire = TripwireDispatcher()
        buf = io.StringIO()
        secret = "sk-LEAK-CANARY-123"
        with tempfile.TemporaryDirectory() as tmp:
            record = os.path.join(tmp, "rec.json")
            with redirect_stderr(buf):
                # Present key but budget will pass and tripwire raises at dispatch;
                # we only assert the key never appears in any emitted output.
                try:
                    dispatch.dispatch(
                        workdir="cred-present",
                        budget=10_000.0,
                        record_path=record,
                        dispatcher=tripwire,
                        env={"ANTHROPIC_API_KEY": secret},
                        estimate_runner=lambda argv: '{"ai_cost": {"usd": 0.001}}',
                        stages=("PL",),
                    )
                except AssertionError:
                    pass  # tripwire fired — expected
            self.assertNotIn(secret, buf.getvalue())


if __name__ == "__main__":
    unittest.main()
