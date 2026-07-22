"""Credential probe parity (R2; port of CredentialProbeTests): absent key → frozen
message; empty/whitespace == absent; present passes; CLI-login alone satisfies;
logged-out false; defensive on malformed; identity never leaks; env-key
short-circuits before the CLI probe; dispatch rc=3 fast-exit dispatching nothing.
"""

import json
import os
import shutil
import tempfile
import unittest

from benchmarklive import credentials
from benchmarklive.dispatch import dispatch

import sys as _sys
_sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))  # _helpers under any runner
from _helpers import (
    TripwireDispatcher,
    fake_estimate_runner,
    logged_in_runner,
    logged_out_runner,
    make_live_sandbox,
    stub_git_sha,
    tripwire_runner,
)


class CredentialProbe(unittest.TestCase):
    def test_absent_key_no_login_is_false(self):
        self.assertFalse(credentials.has_credential(env={}, cli_login_runner=logged_out_runner))

    def test_empty_and_whitespace_key_equal_absent(self):
        self.assertFalse(credentials.has_credential(env={"ANTHROPIC_API_KEY": ""},
                                                    cli_login_runner=logged_out_runner))
        self.assertFalse(credentials.has_credential(env={"ANTHROPIC_API_KEY": "   "},
                                                    cli_login_runner=logged_out_runner))

    def test_present_key_passes(self):
        self.assertTrue(credentials.has_credential(env={"ANTHROPIC_API_KEY": "sk-xxx"}))

    def test_cli_login_alone_satisfies(self):
        self.assertTrue(credentials.has_credential(env={}, cli_login_runner=logged_in_runner))

    def test_logged_out_is_false(self):
        self.assertFalse(credentials.has_cli_login(runner=logged_out_runner))

    def test_defensive_on_malformed(self):
        self.assertFalse(credentials.has_cli_login(runner=lambda: "not json"))
        self.assertFalse(credentials.has_cli_login(runner=lambda: "[]"))

    def test_env_key_short_circuits_before_cli_probe(self):
        # A present key must be accepted WITHOUT invoking the CLI runner (tripwire).
        self.assertTrue(credentials.has_credential(
            env={"ANTHROPIC_API_KEY": "sk-xxx"}, cli_login_runner=tripwire_runner()))

    def test_frozen_message_and_no_key_leak(self):
        try:
            credentials.require_credential(env={}, cli_login_runner=logged_out_runner)
            self.fail("expected CredentialError")
        except credentials.CredentialError as e:
            self.assertEqual(str(e), credentials.MISSING_CREDENTIAL_MESSAGE)
            self.assertNotIn("sk-", str(e))


class DispatchCredentialGate(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="cred-")
        self.sb = make_live_sandbox(self.tmp)

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_rc3_fast_exit_dispatches_nothing(self):
        captured = []
        rc = dispatch(
            workdir=self.sb.run_id, budget=100.0, record_path=self.sb.record_path,
            benchmark_dir=self.sb.benchmark_dir, dispatcher=TripwireDispatcher(),
            env={}, cli_login_runner=logged_out_runner,
            estimate_runner=fake_estimate_runner(0.001), stages=["PL", "AR"],
            git_sha_runner=stub_git_sha, stderr=captured.append)
        self.assertEqual(rc, 3)
        self.assertFalse(os.path.exists(self.sb.record_path))  # nothing dispatched, no record
        self.assertEqual(captured, [credentials.MISSING_CREDENTIAL_MESSAGE])  # frozen stderr


if __name__ == "__main__":
    unittest.main()
