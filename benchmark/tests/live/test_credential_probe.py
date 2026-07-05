"""benchmark/tests/live/test_credential_probe.py — AC-8 credential gate (DV0e).

With ANTHROPIC_API_KEY unset AND no CLI login, the adapter fast-exits BEFORE any
dispatch with the frozen message and never reveals a key value or CLI-login
identity detail. All checks use an injected env dict / fake `cli_login_runner` and
a tripwire dispatcher — no network, no spend, no real `claude auth status` shell-out
(Batch 1c adds the CLI-login credential source; every test here injects a FAKE
runner so the suite never shells out even for the read-only status probe).
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


def _logged_out_runner():
    """Fake `claude auth status --json` runner: reports not logged in."""
    return '{"loggedIn": false}'


def _logged_in_runner():
    """Fake `claude auth status --json` runner: reports logged in.

    Includes identity fields (email/orgId) exactly like the real CLI, to prove
    `has_cli_login` never surfaces them past the boolean.
    """
    return (
        '{"loggedIn": true, "authMethod": "claude.ai", '
        '"email": "canary@example.invalid", "orgId": "org-canary"}'
    )


class TestCredentialModule(unittest.TestCase):
    def test_absent_key_raises_with_frozen_message(self):
        cred = load_credentials()
        with self.assertRaises(cred.CredentialError) as ctx:
            # empty env -> no key; fake runner -> no CLI login either.
            cred.require_credential({}, cli_login_runner=_logged_out_runner)
        self.assertEqual(str(ctx.exception), FROZEN_MESSAGE)

    def test_empty_or_whitespace_key_counts_as_absent(self):
        cred = load_credentials()
        self.assertFalse(
            cred.has_credential({"ANTHROPIC_API_KEY": ""}, cli_login_runner=_logged_out_runner)
        )
        self.assertFalse(
            cred.has_credential({"ANTHROPIC_API_KEY": "   "}, cli_login_runner=_logged_out_runner)
        )

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

    def test_cli_login_alone_satisfies_the_gate(self):
        # No env var at all — CLI login (fake runner) is the ONLY credential.
        cred = load_credentials()
        self.assertTrue(cred.has_cli_login(runner=_logged_in_runner))
        self.assertTrue(
            cred.has_credential({}, cli_login_runner=_logged_in_runner)
        )
        cred.require_credential({}, cli_login_runner=_logged_in_runner)  # no raise

    def test_cli_login_false_when_logged_out(self):
        cred = load_credentials()
        self.assertFalse(cred.has_cli_login(runner=_logged_out_runner))

    def test_cli_login_defensive_on_malformed_output(self):
        cred = load_credentials()
        self.assertFalse(cred.has_cli_login(runner=lambda: "not json"))
        self.assertFalse(cred.has_cli_login(runner=lambda: ""))
        self.assertFalse(cred.has_cli_login(runner=lambda: "[]"))  # not a dict
        self.assertFalse(cred.has_cli_login(runner=lambda: '{"loggedIn": "yes"}'))  # not bool True

    def test_cli_login_status_never_leaks_identity_fields(self):
        cred = load_credentials()
        secret_email = "canary@example.invalid"
        secret_org = "org-canary"
        # has_cli_login only ever returns a bool — assert the type, not content.
        result = cred.has_cli_login(runner=_logged_in_runner)
        self.assertIsInstance(result, bool)
        # Exercise the full gate path too; no exception should ever carry identity.
        try:
            cred.require_credential({}, cli_login_runner=_logged_in_runner)
        except cred.CredentialError as exc:  # pragma: no cover
            self.assertNotIn(secret_email, str(exc))
            self.assertNotIn(secret_org, str(exc))

    def test_env_key_short_circuits_before_cli_probe(self):
        # A tripwire-style runner that raises if ever called — proves the env-var
        # path is checked FIRST and the (more expensive) CLI probe is skipped.
        cred = load_credentials()

        def _tripwire_runner():
            raise AssertionError("CLI login probe must not run when env key present")

        self.assertTrue(
            cred.has_credential({"ANTHROPIC_API_KEY": "sk-xxx"}, cli_login_runner=_tripwire_runner)
        )


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
                    cli_login_runner=_logged_out_runner,  # NO CLI login either
                )
            self.assertNotEqual(rc, 0)            # fast non-zero exit
            self.assertFalse(tripwire.called)     # dispatched nothing
            self.assertFalse(os.path.isfile(record))  # no record on fast-exit
            self.assertIn(FROZEN_MESSAGE, buf.getvalue())

    def test_dispatch_succeeds_via_cli_login_alone(self):
        # No ANTHROPIC_API_KEY at all — CLI login (fake runner) satisfies the gate
        # and the pipeline proceeds past the credential probe.
        dispatch = load_dispatch()
        from _helpers import RecordingFakeDispatcher
        fake = RecordingFakeDispatcher(outputs=['{"usage": {"input_tokens": 1}}'])
        with tempfile.TemporaryDirectory() as tmp:
            record = os.path.join(tmp, "rec.json")
            rc = dispatch.dispatch(
                workdir="cred-cli-login",
                budget=10_000.0,
                record_path=record,
                dispatcher=fake,
                env={},  # NO ANTHROPIC_API_KEY
                cli_login_runner=_logged_in_runner,
                estimate_runner=lambda argv: '{"ai_cost": {"usd": 0.001}}',
                stages=("PL",),
            )
            self.assertEqual(rc, 0)
            self.assertTrue(fake.calls)  # dispatch proceeded

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
