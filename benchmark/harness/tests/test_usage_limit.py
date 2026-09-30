"""A stage killed by the account usage limit is classified, waited out and re-dispatched.

No test sleeps or spawns claude: the clock and sleep are fakes and the dispatcher is a
scripted stand-in.
"""

import json
import os
import shutil
import sys as _sys
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace

from benchmarklive import usage_limit
from benchmarklive.dispatch import DispatchFailure, dispatch

_sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _helpers import (fake_estimate_runner, load_json, make_live_sandbox,  # noqa: E402
                      single_object_usage, stub_git_sha)

BANNER = "You've hit your session limit · resets 7pm (Europe/Kiev)"
NOON_UTC = datetime(2026, 9, 30, 12, 0, tzinfo=timezone.utc)   # 15:00 in Kyiv (UTC+3)
SEVEN_PM_KYIV = datetime(2026, 9, 30, 16, 0, tzinfo=timezone.utc)


def limit_stdout(text=BANNER, status=429, extra=()):
    """Stream-json as a rejected ``claude -p`` prints it: init, synthetic message, result."""
    events = [
        {"type": "system", "subtype": "init", "plugins": []},
        *extra,
        {"type": "assistant", "error": "rate_limit",
         "message": {"model": "<synthetic>", "content": [{"type": "text", "text": text}]}},
        {"type": "result", "subtype": "success", "is_error": True, "api_error_status": status,
         "result": text, "total_cost_usd": 0, "usage": {"input_tokens": 0, "output_tokens": 0}},
    ]
    return "\n".join(json.dumps(e) for e in events) + "\n"


class ParseReset(unittest.TestCase):
    def test_hour_with_meridiem_and_named_zone(self):
        self.assertEqual(usage_limit.parse_reset("resets 7pm (Europe/Kiev)", NOON_UTC),
                         SEVEN_PM_KYIV)

    def test_a_time_already_past_today_means_tomorrow(self):
        late = datetime(2026, 9, 30, 17, 0, tzinfo=timezone.utc)   # 20:00 in Kyiv
        self.assertEqual(usage_limit.parse_reset("resets 7pm (Europe/Kiev)", late),
                         SEVEN_PM_KYIV + timedelta(days=1))

    def test_twenty_four_hour_clock_in_the_local_zone(self):
        got = usage_limit.parse_reset("resets 19:00", NOON_UTC)
        local = got.astimezone()
        self.assertEqual((local.hour, local.minute), (19, 0))
        self.assertGreater(got, NOON_UTC)
        self.assertLessEqual(got - NOON_UTC, timedelta(hours=24, minutes=1))

    def test_minutes_and_twelve_oclock(self):
        self.assertEqual(usage_limit.parse_reset("resets 7:30pm (UTC)", NOON_UTC),
                         datetime(2026, 9, 30, 19, 30, tzinfo=timezone.utc))
        self.assertEqual(usage_limit.parse_reset("resets 12am (UTC)", NOON_UTC),
                         datetime(2026, 10, 1, 0, 0, tzinfo=timezone.utc))
        self.assertEqual(usage_limit.parse_reset("resets 12pm (UTC)",
                                                 NOON_UTC - timedelta(hours=1)), NOON_UTC)

    def test_a_dated_reset(self):
        self.assertEqual(usage_limit.parse_reset("resets Oct 3, 7pm (UTC)", NOON_UTC),
                         datetime(2026, 10, 3, 19, 0, tzinfo=timezone.utc))

    def test_an_unknown_zone_falls_back_to_local_time(self):
        got = usage_limit.parse_reset("resets 7pm (Mars/Olympus)", NOON_UTC)
        self.assertEqual(got.astimezone().hour, 19)

    def test_a_missing_or_unparsable_time_is_none(self):
        for text in ("You've hit your session limit", "resets soon", "resets 5 times",
                     "resets 25:00", "resets 13pm", "resets 7:99pm"):
            self.assertIsNone(usage_limit.parse_reset(text, NOON_UTC), text)


class Detect(unittest.TestCase):
    def test_the_synthetic_banner_and_its_reset(self):
        limit = usage_limit.detect(limit_stdout(), NOON_UTC)
        self.assertEqual(limit.message, BANNER)
        self.assertEqual(limit.reset_at, SEVEN_PM_KYIV)
        self.assertEqual(limit.reset_text, "resets 7pm (Europe/Kiev)")

    def test_each_limit_kind_matches(self):
        for kind in ("session", "usage", "weekly"):
            text = f"You've hit your {kind} limit"
            self.assertIsNotNone(usage_limit.detect(limit_stdout(text, status=1), NOON_UTC), kind)

    def test_a_429_alone_is_a_limit_without_a_reset_time(self):
        stdout = json.dumps({"type": "result", "is_error": True, "api_error_status": 429,
                             "result": "Rate limited"}) + "\n"
        limit = usage_limit.detect(stdout, NOON_UTC)
        self.assertIsNotNone(limit)
        self.assertIsNone(limit.reset_at)

    def test_a_banner_without_a_time_has_no_reset(self):
        limit = usage_limit.detect(limit_stdout("You've hit your usage limit", status=1), NOON_UTC)
        self.assertEqual((limit.reset_at, limit.reset_text), (None, None))

    def test_a_resets_banner_alone_counts(self):
        limit = usage_limit.detect(limit_stdout("Limit reached · resets 19:00 (UTC)",
                                                status=1), NOON_UTC)
        self.assertEqual(limit.reset_at, datetime(2026, 9, 30, 19, 0, tzinfo=timezone.utc))

    def test_a_rejected_quota_epoch_wins_over_the_printed_time(self):
        epoch = int((NOON_UTC + timedelta(hours=1)).timestamp())
        quota = {"type": "rate_limit_event",
                 "rate_limit_info": {"status": "rejected", "resetsAt": epoch}}
        limit = usage_limit.detect(limit_stdout(extra=[quota]), NOON_UTC)
        self.assertEqual(limit.reset_at, NOON_UTC + timedelta(hours=1))

    def test_an_allowed_quota_epoch_is_ignored(self):
        quota = {"type": "rate_limit_event",
                 "rate_limit_info": {"status": "allowed", "resetsAt": 1}}
        self.assertEqual(usage_limit.detect(limit_stdout(extra=[quota]), NOON_UTC).reset_at,
                         SEVEN_PM_KYIV)

    def test_an_ordinary_failure_is_not_a_limit(self):
        for stdout in ("", "segfault\n", single_object_usage(),
                       json.dumps({"type": "result", "is_error": True, "api_error_status": 500,
                                   "result": "Internal error, cache resets 5 times"})):
            self.assertIsNone(usage_limit.detect(stdout, NOON_UTC), stdout[:30])

    def test_a_single_json_document_is_read_too(self):
        doc = json.dumps([{"type": "result", "api_error_status": 429, "result": BANNER}])
        self.assertEqual(usage_limit.detect(doc, NOON_UTC).reset_at, SEVEN_PM_KYIV)

    def test_tool_output_mentioning_the_phrase_is_not_a_limit(self):
        event = {"type": "user", "message": {"content": [
            {"type": "text", "text": "You've hit your session limit"}]}}
        self.assertIsNone(usage_limit.detect(json.dumps(event), NOON_UTC))


class Policy(unittest.TestCase):
    def setUp(self):
        self.sleeps, self.logs = [], []
        self.limit = usage_limit.UsageLimit("m", reset_at=NOON_UTC + timedelta(hours=1))

    def policy(self, **kw):
        return usage_limit.LimitPolicy(sleep=self.sleeps.append, now=lambda: NOON_UTC,
                                       log=self.logs.append, **kw)

    def test_sleeps_to_the_reset_plus_the_margin_and_says_so(self):
        self.policy().wait_out(self.limit, "with DV")
        self.assertEqual(self.sleeps, [3600 + 120])
        self.assertIn("with DV", self.logs[0])
        self.assertIn("2026-09-30T13:00:00Z", self.logs[0])

    def test_no_reset_time_polls(self):
        self.policy(poll_s=900).wait_out(usage_limit.UsageLimit("m"), "with DV")
        self.assertEqual(self.sleeps, [900])

    def test_a_reset_already_past_still_waits_the_margin(self):
        past = usage_limit.UsageLimit("m", reset_at=NOON_UTC - timedelta(hours=1))
        self.policy().wait_out(past, "with DV")
        self.assertEqual(self.sleeps, [120])

    def test_disabled_raises_without_sleeping(self):
        with self.assertRaises(usage_limit.UsageLimitHit) as ctx:
            self.policy(wait=False).wait_out(self.limit, "with DV")
        self.assertEqual(self.sleeps, [])
        self.assertIs(ctx.exception.limit, self.limit)

    def test_a_wait_over_the_cap_raises_without_sleeping(self):
        far = usage_limit.UsageLimit("m", reset_at=NOON_UTC + timedelta(hours=7))
        with self.assertRaises(usage_limit.UsageLimitHit) as ctx:
            self.policy().wait_out(far, "with DV")
        self.assertEqual(self.sleeps, [])
        self.assertIn("cap", str(ctx.exception))

    def test_the_cap_is_cumulative(self):
        policy = self.policy(cap_s=5000)
        policy.wait_out(self.limit, "with DV")
        with self.assertRaises(usage_limit.UsageLimitHit):
            policy.wait_out(self.limit, "with DV")
        self.assertEqual(self.sleeps, [3720])

    def test_describe_names_the_reset(self):
        hit = usage_limit.UsageLimitHit(usage_limit.detect(limit_stdout(), NOON_UTC), "off")
        self.assertIn("2026-09-30T16:00:00Z", usage_limit.describe(hit))
        bare = usage_limit.UsageLimitHit(usage_limit.UsageLimit("m", reset_text="resets soon"), "off")
        self.assertIn("resets soon", usage_limit.describe(bare))


class ScriptedDispatcher:
    """Answers each call from a script: a str is stdout, an Exception is raised."""

    def __init__(self, *script):
        self.script = list(script)
        self.calls = []

    def run(self, argv, prompt_text):
        self.calls.append((list(argv), prompt_text))
        step = self.script[min(len(self.calls), len(self.script)) - 1]
        if isinstance(step, Exception):
            raise step
        return step


class RecordingSeedRunner:
    def __init__(self):
        self.calls = []

    def __call__(self, argv, env, cwd):
        self.calls.append(argv)
        return SimpleNamespace(exit_code=0, stdout="", stderr="")


def limit_failure(text=BANNER):
    stdout = limit_stdout(text)
    return DispatchFailure("claude -p failed (rc=1)", stdout=stdout, returncode=1)


class DispatchRetries(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="limit-")
        self.sb = make_live_sandbox(self.tmp)
        self.warnings, self.sleeps = [], []
        self.seed = RecordingSeedRunner()

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def run_dispatch(self, dispatcher, stages, wait=True, policy=None):
        policy = policy or usage_limit.LimitPolicy(
            wait=wait, sleep=self.sleeps.append, now=lambda: NOON_UTC, log=self.warnings.append)
        return dispatch(
            workdir=self.sb.run_id, budget=100.0, record_path=self.sb.record_path,
            benchmark_dir=self.sb.benchmark_dir, workdir_root=self.sb.workdir_root,
            dispatcher=dispatcher, env={"ANTHROPIC_API_KEY": "k"},
            estimate_runner=fake_estimate_runner(0.001), stages=stages,
            git_sha_runner=stub_git_sha, without_arm="skip", stderr=self.warnings.append,
            seed_runner=self.seed, limit_policy=policy)

    def captures(self, name):
        return os.path.join(self.sb.workdir_path, "captures", name)

    def test_the_limited_stage_alone_is_redispatched_after_the_wait(self):
        ok = single_object_usage(cost=0.05)
        fake = ScriptedDispatcher(ok, limit_failure(), ok, ok)
        rc = self.run_dispatch(fake, ["PL", "AR", "TL"])
        self.assertEqual(rc, 0)
        self.assertEqual(len(fake.calls), 4)
        # PL once, AR twice with identical argv and prompt, TL once.
        self.assertEqual(fake.calls[1], fake.calls[2])
        self.assertNotEqual(fake.calls[0][1], fake.calls[1][1])
        self.assertEqual(len(self.sleeps), 1)
        self.assertGreater(self.sleeps[0], 120)
        self.assertTrue(any("usage limit at with AR" in w for w in self.warnings))

    def test_the_failed_attempt_is_not_counted_in_the_record_or_the_budget(self):
        ok = single_object_usage(cost=0.05)
        rc = self.run_dispatch(ScriptedDispatcher(ok, limit_failure(), ok), ["PL", "AR"])
        self.assertEqual(rc, 0)
        arm = load_json(self.sb.record_path)["paths"]["with"]
        self.assertEqual(arm["stage_count"], 2)
        self.assertAlmostEqual(arm["cost_usd"], 0.10)

    def test_a_spend_the_limit_interrupted_is_charged_to_the_tally_only(self):
        stdout = limit_stdout() + json.dumps({"type": "result", "total_cost_usd": 1.0,
                                              "usage": {"input_tokens": 1, "output_tokens": 1}})
        failing = DispatchFailure("x", stdout=stdout, returncode=1)
        ok = single_object_usage(cost=0.05)
        # A $1 share leaves no room for a second stage once $1 is charged.
        rc = dispatch(
            workdir=self.sb.run_id, budget=1.05, record_path=self.sb.record_path,
            benchmark_dir=self.sb.benchmark_dir, workdir_root=self.sb.workdir_root,
            dispatcher=ScriptedDispatcher(failing, ok, ok), env={"ANTHROPIC_API_KEY": "k"},
            estimate_runner=fake_estimate_runner(0.001), stages=["PL", "AR"],
            git_sha_runner=stub_git_sha, without_arm="skip", stderr=self.warnings.append,
            seed_runner=self.seed,
            limit_policy=usage_limit.LimitPolicy(sleep=self.sleeps.append, now=lambda: NOON_UTC))
        arm = load_json(self.sb.record_path)["paths"]["with"]
        self.assertEqual(rc, 4)
        self.assertEqual(arm["stage_count"], 1)
        self.assertAlmostEqual(arm["cost_usd"], 0.05)

    def test_the_arm_ledger_seeding_survives_the_retry(self):
        arm = self.sb.arm_dir("with")
        os.makedirs(os.path.join(arm, ".context"), exist_ok=True)
        with open(os.path.join(arm, ".context", "state.json"), "w", encoding="utf-8") as f:
            json.dump({"version": 2, "run_index": 0, "tasks": {"PL0": {"status": "completed"}}}, f)
        ok = single_object_usage()
        fake = ScriptedDispatcher(ok, limit_failure(), ok)
        self.run_dispatch(fake, ["PL", "QA"])
        self.assertEqual(len(fake.calls), 3)
        # One seed-state.sh call, then QA's three state-patch writes: made once, before the
        # first QA attempt, not again before the retry.
        self.assertEqual(len(self.seed.calls), 4)

    def test_every_failure_is_kept_in_full_beside_the_capture(self):
        ok = single_object_usage()
        failure = limit_failure()
        self.run_dispatch(ScriptedDispatcher(ok, failure, ok), ["PL", "AR"])
        with open(self.captures("with-AR.failed.jsonl"), encoding="utf-8") as f:
            self.assertEqual(f.read(), failure.stdout)
        self.assertTrue(os.path.exists(self.captures("with-AR.jsonl")))

    def test_a_non_limit_failure_still_propagates_and_is_kept(self):
        boom = DispatchFailure("claude -p failed (rc=1)", stdout="x" * 1000 + "\nsegfault\n")
        with self.assertRaises(DispatchFailure):
            self.run_dispatch(ScriptedDispatcher(boom), ["PL"])
        with open(self.captures("with-PL.failed.jsonl"), encoding="utf-8") as f:
            self.assertEqual(f.read(), boom.stdout)
        self.assertEqual(self.sleeps, [])

    def test_waiting_off_ends_the_run_with_rc_6_and_a_partial_record(self):
        ok = single_object_usage(cost=0.05)
        rc = self.run_dispatch(ScriptedDispatcher(ok, limit_failure(), ok), ["PL", "AR"],
                               wait=False)
        self.assertEqual(rc, 6)
        self.assertEqual(self.sleeps, [])
        record = load_json(self.sb.record_path)
        self.assertTrue(record["live_partial"])
        self.assertEqual(record["paths"]["with"]["stage_count"], 1)
        message = next(w for w in self.warnings if "usage limit" in w)
        self.assertIn("resets at", message)
        self.assertIn("hit your session limit", message)
        self.assertIn("rerun after the reset", message)

    def test_the_reset_time_is_named_when_the_cli_gave_an_epoch(self):
        quota = {"type": "rate_limit_event",
                 "rate_limit_info": {"status": "rejected",
                                     "resetsAt": int(SEVEN_PM_KYIV.timestamp())}}
        failing = DispatchFailure("x", stdout=limit_stdout(extra=[quota]), returncode=1)
        rc = self.run_dispatch(ScriptedDispatcher(failing), ["PL"], wait=False)
        self.assertEqual(rc, 6)
        self.assertTrue(any("2026-09-30T16:00:00Z" in w for w in self.warnings))

    def test_a_limit_at_the_first_stage_still_writes_the_record(self):
        rc = self.run_dispatch(ScriptedDispatcher(limit_failure()), ["PL"], wait=False)
        self.assertEqual(rc, 6)
        self.assertEqual(load_json(self.sb.record_path)["paths"]["with"]["stage_count"], 0)

    def test_a_reset_beyond_the_cap_ends_the_run_without_sleeping(self):
        far = limit_failure("You've hit your weekly limit · resets 7pm (UTC)")
        policy = usage_limit.LimitPolicy(cap_s=3600, sleep=self.sleeps.append,
                                         now=lambda: NOON_UTC, log=self.warnings.append)
        rc = self.run_dispatch(ScriptedDispatcher(far), ["PL"], policy=policy)
        self.assertEqual(rc, 6)
        self.assertEqual(self.sleeps, [])
        self.assertTrue(any("cap" in w for w in self.warnings))

    def test_a_limit_that_outlasts_the_wait_is_waited_on_again_up_to_the_cap(self):
        ok = single_object_usage()
        soon = limit_failure("You've hit your session limit \u00b7 resets 1pm (UTC)")
        fake = ScriptedDispatcher(soon, soon, ok)
        rc = self.run_dispatch(fake, ["PL"])
        self.assertEqual(rc, 0)
        self.assertEqual(len(fake.calls), 3)
        self.assertEqual(len(self.sleeps), 2)


if __name__ == "__main__":
    unittest.main()
