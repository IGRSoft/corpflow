#!/usr/bin/env python3
"""gen-request-plan-cases — emit the request-plan eval set from a dimension table.

Cases are data here rather than hand-written JSON so the 72-cell space stays
auditable and regenerable. Three dimensions, chosen from observed failures:
request type, repo grounding, and routing pressure.

Grounding drives what each case can prove:
  obvious  — the prompt names the surface, so discovery targets a RELATED file
  buried   — the prompt describes the need only; discovery targets the surface
             itself, the strongest test in the set
  adjacent — the near-miss surface exists; the plan must name it
  absent   — nothing to ground on, so the case expects a clarification instead

Two derived assertions per planning case (routing + discovery) hold every case at
25% case-specific. Generation fails closed on an unresolvable path or a discovery
token echoed from its own prompt, so a bad case can never reach a paid capture.

Usage: gen-request-plan-cases.py [--out PATH] [--check]
"""

from __future__ import annotations

import argparse
import collections
import json
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DEFAULT_OUT = os.path.join(REPO, "skills", "request-plan", "evals", "evals.json")

ROUTE_ASSERTION = {
    # Two-sided on purpose. Removing the escalation half let four over-routed plans
    # through; the labels call every one of them a failure.
    "std": ("routes-to-standard-tier",
            "Ordinary work takes the plain trigger; escalating it burns the security "
            "pipeline on work with no credential, auth or secret surface",
            [r"/worktask\s+\""]),
    "secure": ("routes-to-secure-tier",
               "Security-sensitive work routes to --secure regardless of size "
               "(skills/request-plan/references/handoff.md)",
               [r"/worktask\s+--secure"]),
    "emerg": ("routes-to-emergency-tier",
              "A live incident takes the incident pipeline, not the planning tiers",
              [r"/worktask\s+--emergency"]),
}

# Retired cases — the premise was never true, so no answer to them could be right and
# measuring one costs a paid capture for nothing. The slot stays in CASES as `None`
# instead of being deleted: ids here are POSITIONAL, and the grading rubric, the split
# manifest and a dozen comments in this file all key on them, so closing a gap would
# silently renumber every later case and re-point all of it at the wrong prompt.
# id -> why the premise never held.
RETIRED = {
    6: "megatask --dry-run shipped 2026-06-22; init-worktree.sh takes it and writes nothing",
    8: "branch-name.sh:464 already no-ops on a tracked upstream, so the rename never happens",
    9: "cost-report was removed with the whole cost-observability feature; there is no command "
       "left to add a machine-readable summary to",
    10: "analysis.py has carried a module docstring since f03065f",
    46: "attachments-preseed.sh makes no temp file outside its selftest, which traps its own cleanup",
    52: "rotation.py opens with a module docstring giving the retention and atomicity rationale",
    57: "qa-engineer.md:99 already states QA is the sole holder of full-suite authority",
    62: "hook-install.sh backs up on overwrite, and writes no settings file at all",
    74: "context-status was removed; nothing in the repo reports remaining context to plan against",
    98: "status-view.sh was removed with /worktask-status; no live-status table remains to plan",
    114: "worktask-status was removed; its only grounding surface no longer exists",
}

# (type, grounding, route, prompt, grounding_paths, discovery_values)
#
# discovery_values is DEAD: unpacked in build_case and used by nothing. Do not wire it
# up. 73 cases fill it with vocabulary — `budget`, `atomic`, `release`, `scan` — and
# `finds-the-real-surface` accepting those would pass any plan that happened to use the
# word, which is the leak `surface_tokens` exists to close. The assertion is derived
# from grounding_paths on purpose; repoint the path when a case grades the wrong file.
CASES = [
    # ---- exists-obvious: prompt names the surface; discovery targets a relative ----
    ("bug", "obvious", "std", "state-merge.sh is dropping keys when two stages patch at once. plan a fix.",
     ["hooks/state-merge.sh"], ["state-patch", "atomic", "ledger"]),
    ("refactor", "obvious", "std", "dispatch.py has grown past 30KB. how would you break it up?",
     ["benchmark/harness/benchmarklive/dispatch.py"], ["preamble", "baseline", "budget"]),
    ("refactor", "obvious", "std", "fn-preflight.sh is 24KB in one file. plan an extraction.",
     ["skills/worktask/scripts/fn-preflight.sh"], ["pr-body-lint", "branch-lib", "section-lint"]),
    # The figure has now gone stale three times (183 -> 123 -> 145) and each drift silently
    # changes what the case tests. If the corpus is ever re-cut, prefer a premise that does
    # not embed a number the repo keeps moving; changing it here invalidates the human label,
    # which is why it is corrected rather than removed.
    ("docs", "obvious", "std", "CHANGELOG.md is 145KB and unreadable. what's the plan to split it?",
     ["CHANGELOG.md"], ["release", "version", "semver"]),
    ("bug", "obvious", "std", "the comment density gate rejects DocC that looks fine to me. plan a fix.",
     ["hooks/dv-comment-density-gate.sh"], ["comment-standard", "code-comment", "DocC ratio"]),
    None,  # 6 — retired; see RETIRED
    ("refactor", "obvious", "std", "genlib.py mixes a subprocess wrapper with tree copying. plan a split.",
     ["benchmark/harness/benchmarkkit/genlib.py"], ["oracle", "deterministic", "generators"]),
    None,  # 8 — retired; see RETIRED
    None,  # 9 — retired; see RETIRED
    None,  # 10 — retired; see RETIRED
    ("migration", "obvious", "secure", "credentials.py still accepts an env key. plan dropping that path.",
     ["benchmark/harness/benchmarklive/credentials.py"], ["login", "probe", "boolean"]),
    ("feature", "obvious", "secure", "add secret scanning to fn-preflight.sh before it opens a PR.",
     ["skills/worktask/scripts/fn-preflight.sh"], ["gitleaks", "trufflehog", "scan"]),
    ("bug", "obvious", "secure", "audit-tooluse.sh may be logging tool inputs verbatim. plan a fix.",
     ["hooks/audit-tooluse.sh"], ["redact", "sanitis", "sanitiz"]),
    ("incident", "obvious", "emerg", "megatask-monitor.sh is hanging mid-batch right now. plan the response.",
     ["hooks/megatask-monitor.sh"], ["timeout", "watchdog", "stall"]),
    ("incident", "obvious", "emerg", "precompact-checkpoint.sh is failing and we're losing context. plan it.",
     ["hooks/precompact-checkpoint.sh"], ["resume", "transcript", "ledger"]),

    # ---- exists-buried: prompt never names the surface; discovery must find it ----
    ("feature", "buried", "std", "i want the cost numbers exportable into a spreadsheet. what's the plan?",
     ["skills/csv-export-templates/SKILL.md"], ["csv-export-templates", "13[- ]CSV"]),
    # Two grounds, same repair as cases 31 and 84: state-merge.sh performs the union, but
    # `state-patch.sh --facts` is the layer that drives it and the one a fix plan lands in.
    ("bug", "buried", "std", "our stage handoffs silently lose facts between stages. plan a fix.",
     ["hooks/state-merge.sh", "skills/worktask/scripts/state-patch.sh"],
     ["state-merge", "state-patch", "ledger"]),
    ("feature", "buried", "std", "i want screenshots attached to the PR automatically. plan it.",
     ["skills/worktask/scripts/attach-visual-evidence.sh"], ["attach-visual-evidence", "dv-screenshot"]),
    ("bug", "buried", "std", "PR descriptions keep leaking absolute paths from my machine. plan a fix.",
     ["skills/worktask/scripts/pr-body-lint.sh"], ["pr-body-lint", "body.lint"]),
    ("feature", "buried", "std", "i want the plugin to learn from my edits after a task ships. plan it.",
     ["skills/self-improvement/SKILL.md"], ["self-improvement", "failure-labels"]),
    ("bug", "buried", "std", "branches come out with inconsistent names across runs. plan a fix.",
     ["skills/worktask/scripts/branch-lib.sh"], ["branch-lib", "derive_type", "conventional"]),
    ("feature", "buried", "std", "i need to know which agents actually ran during a task. plan it.",
     ["hooks/audit-subagent.sh"], ["audit-subagent", "coverage", "manifest"]),
    # Ground was section-lint.sh, which caps SECTION LENGTH and has nothing to do with
    # anchors. anchor-preflight.sh is the anchor lint — it runs cache-lint --anchor-lint
    # on stage artifacts so a bad H2 surfaces at the producing stage, which is the
    # reported drift exactly. The 0.2.0 capture reached it and was scored a miss.
    ("bug", "buried", "std", "the doc anchors in stage artifacts drift from the templates. plan a fix.",
     ["hooks/anchor-preflight.sh"], ["section-lint", "anchor-preflight"]),
    ("feature", "buried", "std", "i want an estimate broken down by phase and budget. plan it.",
     ["skills/estimation-methodology/SKILL.md"], ["estimation-methodology", "complexity"]),
    ("refactor", "buried", "std", "the prompt cache keeps missing between stages. plan an investigation.",
     ["skills/worktask/scripts/cache-lint.sh"], ["cache-lint", "prefix", "preamble"]),
    ("bug", "buried", "std", "we keep opening duplicate tickets for the same piece of work. plan a fix.",
     ["skills/gh-issue-dedup/SKILL.md"], ["gh-issue-dedup", "anchor"]),
    ("feature", "buried", "std", "i want to compare two runs of the same task for cost. plan it.",
     ["benchmark/harness/benchmarkkit/pairing.py"], ["pairing", "paired", "arm"]),
    ("docs", "buried", "std", "new contributors can't tell which agent owns which stage. plan the docs.",
     ["skills/agent-coordination/SKILL.md"], ["agent-coordination", "nesting"]),
    ("migration", "buried", "secure", "the labels we write about user edits might contain their code. plan a fix.",
     ["skills/self-improvement/SKILL.md"], ["redact", "no diff bodies", "summary only"]),
    ("incident", "buried", "emerg", "a task is wedged in_progress and nothing will pick it up. plan the response.",
     ["skills/worktask/scripts/state-patch.sh"], ["state-patch", "ledger", "stuck"]),

    # ---- adjacent-only: the near-miss surface exists and must be named ----
    # Two grounds: the protocol doc states the matrix, but the unbounded loop is the
    # retry_count reset at workflow-engineer.md:118 / agent-coordination SKILL.md:85 --
    # nothing counts round-trips on the same edge. A plan that names either has found it.
    ("bug", "adjacent", "std", "the retry matrix loops forever when a stage keeps failing. plan a fix.",
     ["skills/worktask/references/handoff-protocol.md", "skills/agent-coordination/SKILL.md"],
     ["handoff-protocol", "escalate"]),
    ("feature", "adjacent", "std", "put a spend ceiling on a task so it can't run away. plan it.",
     ["skills/cost-optimization/SKILL.md"], ["cost-optimization", "budget"]),
    ("feature", "adjacent", "std", "i want a per-stage timeout so nothing hangs forever. plan it.",
     ["hooks/megatask-monitor.sh"], ["megatask-monitor", "monitor"]),
    ("migration", "adjacent", "secure", "move the audit trail into something encrypted at rest. plan it.",
     ["hooks/audit-tooluse.sh"], ["audit", "jsonl"]),
    ("refactor", "adjacent", "std", "the three planning tiers should be data, not prose. plan it.",
     ["skills/shared/three-stage-planning.md"], ["three-stage-planning", "P0"]),

    # ---- absent: nothing to ground on; the correct answer is a question ----
    ("feature", "absent", "std", "add a Slack notifier that posts when each stage completes. plan it.", [], []),
    ("bug", "absent", "std", "the iOS build keeps failing on the signing step. help me plan a fix.", [], []),
    ("feature", "absent", "std", "add dark mode to the settings screen. what's the plan?", [], []),
    ("migration", "absent", "std", "plan migrating our Postgres schema off the legacy user table.", [], []),
    ("incident", "absent", "emerg", "the production API is returning 503s right now. plan the response.", [], []),
    ("bug", "absent", "std", "the checkout flow drops the cart on refresh. plan a fix.", [], []),
    ("feature", "absent", "std", "add push notifications to the mobile app. what's the plan?", [], []),
    ("refactor", "absent", "std", "our React components are a mess of prop drilling. plan a refactor.", [], []),

    # ---- batch 2: obvious ----
    ("refactor", "obvious", "std", "state-patch.sh is 79KB. plan how to break it apart.",
     ["skills/worktask/scripts/state-patch.sh"], ["state-merge", "ledger", "atomic"]),
    ("refactor", "obvious", "std", "publish-pl-issue.sh is 63KB even after an earlier split. plan a further extraction.",
     ["skills/worktask/scripts/publish-pl-issue.sh"], ["gh-issue-dedup", "milestone", "anchor"]),
    None,  # 46 — retired; see RETIRED
    ("feature", "obvious", "std", "add a JSON output mode to desc-lint.sh. what's the plan?",
     ["skills/worktask/scripts/desc-lint.sh"], ["section-lint", "structured", "machine"]),
    ("bug", "obvious", "std", "detect-ui-change.sh misses SwiftUI-only diffs. plan a fix.",
     ["skills/worktask/scripts/detect-ui-change.sh"], ["screenshot", "visual", "evidence"]),
    ("refactor", "obvious", "std", "metrics.py has grown to 14KB of mixed concerns. plan a split.",
     ["benchmark/harness/benchmarkkit/metrics.py"], ["coverage", "usage", "report"]),
    # Ground is analysis.py, not report.py: report.py imports format_cost, while
    # analysis.py _outliers() builds its detail with a raw .4f, so one cost renders two ways.
    ("bug", "obvious", "std", "report.py rounds costs inconsistently. plan a fix.",
     ["benchmark/harness/benchmarkkit/analysis.py", "benchmark/harness/benchmarkkit/report.py"], ["metrics", "analysis", "precision"]),
    ("feature", "obvious", "std", "add a resume flag to deterministic_run.py. plan it.",
     ["benchmark/harness/benchmarkkit/deterministic_run.py"], ["oracle", "rotation", "seed"]),
    None,  # 52 — retired; see RETIRED
    ("bug", "obvious", "std", "baseline.py picks the wrong arm on a subset run. plan a fix.",
     ["benchmark/harness/benchmarklive/baseline.py"], ["resolve_arm", "selection", "policy"]),
    ("feature", "obvious", "std", "let budget.py warn before the cap rather than after. plan it.",
     ["benchmark/harness/benchmarklive/budget.py"], ["threshold", "running tally", "breach"]),
    ("refactor", "obvious", "std", "the developer agent file is 48KB. plan how to shrink it.",
     ["agents/developer.md"], ["routing", "platform", "delegate"]),
    ("refactor", "obvious", "std", "the product-manager agent is 52KB of prose. plan a trim.",
     ["agents/product-manager.md"], ["requirements", "planning", "template"]),
    None,  # 57 — retired; see RETIRED
    ("feature", "obvious", "std", "add a machine-readable verdict to the technical-lead agent. plan it.",
     ["agents/technical-lead.md"], ["frontmatter", "handoff", "structured"]),
    ("bug", "obvious", "std", "the release-engineer agent emits the wrong version bump. plan a fix.",
     ["agents/release-engineer.md"], ["semver", "changelog", "release-engineering"]),
    ("feature", "obvious", "secure", "add a threat-model section to the security-reviewer agent. plan it.",
     ["agents/security-reviewer.md"], ["OWASP", "security-review-process", "auditor"]),
    ("bug", "obvious", "secure", "anchor-preflight.sh may execute untrusted anchor text. plan a fix.",
     ["hooks/anchor-preflight.sh"], ["injection", "quote", "eval"]),
    None,  # 62 — retired; see RETIRED
    ("incident", "obvious", "emerg", "agent-stop.sh is killing live stages. plan the response.",
     ["hooks/agent-stop.sh"], ["subagent", "stop", "signal"]),
    ("incident", "obvious", "emerg", "the dv screenshot gate is blocking every task right now. plan it.",
     ["hooks/dv-screenshot-gate.sh"], ["visual", "evidence", "requires_screenshots"]),

    # ---- batch 2: buried ----
    ("feature", "buried", "std", "i want to know why one run cost triple another. plan it.",
     ["benchmark/harness/benchmarkkit/analysis.py"], ["analysis", "era", "comparab"]),
    ("bug", "buried", "std", "the generated app passes its own tests but is still wrong. plan a fix.",
     ["benchmark/harness/benchmarkkit/oracle.py"], ["oracle", "golden", "conformance"]),
    # Ground was rotation.py, which rotates history.json and never compares anything.
    # "compared fairly" is pairing.py: the comparability gate that refuses to join two
    # arm records taken under different conditions. The 0.2.0 capture grounded on it.
    ("feature", "buried", "std", "i want the same task run twice and compared fairly. plan it.",
     ["benchmark/harness/benchmarkkit/pairing.py"], ["rotation", "order", "arm"]),
    ("bug", "buried", "std", "our headless runs can reach the network when they shouldn't. plan a fix.",
     ["benchmark/live/settings/benchmark-settings.json"], ["deny", "settings", "permission"]),
    ("feature", "buried", "std", "i want a written record of every architectural choice. plan it.",
     ["commands/arch-decision.md"], ["arch-decision", "ADR", "TDR"]),
    ("feature", "buried", "std", "i need to rank a backlog objectively. plan it.",
     ["agents/product-manager.md"], ["product-manager", "RICE"]),
    ("bug", "buried", "std", "our docs drift out of sync with the code. plan a fix.",
     ["commands/docs-audit.md"], ["docs-audit", "gap", "outdated"]),
    ("feature", "buried", "std", "i want release notes written from what actually shipped. plan it.",
     ["commands/docs-release-notes.md"], ["release-notes", "changelog"]),
    ("feature", "buried", "std", "i want to check a screen works for people using a reader. plan it.",
     ["commands/design-accessibility.md"], ["accessibility", "audit", "WCAG"]),
    None,  # 74 — retired; see RETIRED
    ("feature", "buried", "std", "i want an outside opinion on whether a feature is worth building. plan it.",
     ["agents/stakeholder.md"], ["stakeholder", "business case", "ROI"]),
    ("refactor", "buried", "std", "our agent definitions have drifted apart in structure. plan a cleanup.",
     ["commands/prompt-audit.md"], ["prompt-audit", "consistency"]),
    ("bug", "buried", "std", "test coverage numbers look fine but bugs still ship. plan a fix.",
     ["commands/test-coverage.md"], ["test-coverage", "gap", "quality"]),
    ("feature", "buried", "std", "i want to catch ethical problems before a feature ships. plan it.",
     ["commands/ethics-review.md"], ["ethics-review", "constitutional", "harm"]),
    ("docs", "buried", "std", "there's no written rule for how comments should be written. plan the docs.",
     ["skills/code-comment-standard/SKILL.md"], ["code-comment-standard", "WHY", "contract"]),
    ("feature", "buried", "secure", "i want dependency risk checked before we ship. plan it.",
     ["skills/security-review-process/SKILL.md"], ["security-review-process", "supply-chain", "OWASP"]),
    ("migration", "buried", "secure", "our task descriptions end up in public branch names. plan a fix.",
     ["skills/shared/git-conventions.md"], ["git-conventions", "credential", "durable"]),
    ("incident", "buried", "emerg", "everything is failing and we need someone coordinating. plan it.",
     ["skills/incident-response/SKILL.md"], ["incident-response", "triage", "post-mortem"]),
    ("incident", "buried", "emerg", "a hotfix needs to ship now and skip the usual gates. plan it.",
     ["agents/incident-responder.md"], ["incident-responder", "emergency", "triage"]),

    # ---- batch 2: adjacent ----
    # Once /worktask-status and status-view.sh were removed, megatask-monitor.sh is the
    # only live-status surface left, so it is the whole ground rather than one of three.
    # Its siblings 98 and 114 grounded ONLY on the removed surfaces and are retired.
    ("feature", "adjacent", "std", "i want a dashboard showing every task's live status. plan it.",
     ["hooks/megatask-monitor.sh"], ["megatask-monitor", "monitor"]),
    ("feature", "adjacent", "std", "let me replay a failed stage without rerunning the whole task. plan it.",
     ["skills/worktask/scripts/state-patch.sh"], ["state-patch", "ledger"]),
    ("migration", "adjacent", "std", "move our estimates into a real database. plan it.",
     ["skills/estimation-methodology/SKILL.md"], ["estimation-methodology", "complexity"]),
    ("bug", "adjacent", "std", "the nesting depth limit silently drops a specialist. plan a fix.",
     ["skills/agent-coordination/SKILL.md"], ["agent-coordination", "depth", "ceiling"]),
    ("feature", "adjacent", "secure", "i want every credential the harness touches rotated. plan it.",
     ["benchmark/harness/benchmarklive/credentials.py"], ["auth status", "login", "probe"]),
    ("refactor", "adjacent", "std", "the plan template and the PRD template overlap. plan a merge.",
     ["commands/product-requirements.md"], ["product-requirements", "PRD"]),
    ("incident", "adjacent", "emerg", "a batch run is burning budget with no way to stop it. plan it.",
     ["benchmark/harness/benchmarklive/budget.py"], ["running tally", "breach", "ceiling"]),

    # ---- batch 2: absent ----
    ("feature", "absent", "std", "add SSO with Okta to the admin console. what's the plan?", [], []),
    ("bug", "absent", "std", "our Kubernetes pods keep OOMing under load. plan a fix.", [], []),
    ("migration", "absent", "secure", "plan moving customer PII out of the analytics warehouse.", [], []),
    ("incident", "absent", "emerg", "the payment processor is rejecting every charge. plan the response.", [], []),
    ("docs", "absent", "std", "our public API reference is out of date. plan the documentation.", [], []),
    ("feature", "absent", "std", "add an offline mode to the desktop client. what's the plan?", [], []),

    # ---- batch 3 (ids 97+): the replacement held-out tranche ----
    # The v0.1.0 test tranche held 9 failures and the taxonomy open-coded all 9, so
    # demoting them to dev left it with no failure signal at all. These replace it and
    # are pinned to `test` in the manifest BEFORE any capture, so nothing here has been
    # read. Weighted to `buried` (the 50%-failure cluster v0.3.0 § 2 claims to close)
    # and to `docs`/`incident`, whose v0.1.0 rates rested on 7- and 10-case denominators.

    # buried: the prompt names no surface, so the search has to reach it
    ("feature", "buried", "std", "there's no way to tell which of my running tasks are still alive. plan it.",
     ["skills/worktask/scripts/stale-check.sh"], []),
    None,  # 98 — retired; see RETIRED
    ("bug", "buried", "std", "the remote branch name stops matching the plan title once planning finishes. plan a fix.",
     ["skills/worktask/scripts/refine-branch-target.sh"], []),
    ("bug", "buried", "std", "an agent edited files in a stale checkout instead of the one it was assigned. plan a fix.",
     ["skills/worktask/scripts/dv-tree-preflight.sh"], []),
    ("feature", "buried", "std", "before work starts i want to know if someone already filed the same request. plan it.",
     ["skills/worktask/scripts/preflight-issue-scan.sh"], []),
    ("bug", "buried", "std", "agents re-run the whole suite when nothing changed since the last run. plan a fix.",
     ["hooks/test-execution-gate.sh"], []),
    ("feature", "buried", "std", "developers stop following our comment rules partway through an edit session. plan it.",
     ["hooks/comment-standard-context.sh"], []),
    ("docs", "buried", "std", "stage handoffs blow the window and nothing explains how to shrink them. plan the documentation.",
     ["skills/context-compression/SKILL.md"], []),
    ("feature", "buried", "std", "i want guidance on choosing a cheaper model per stage. plan it.",
     ["skills/cost-optimization/SKILL.md"], []),
    ("bug", "buried", "std", "background build output lands in a different place every run. plan a fix.",
     ["skills/logging-conventions/SKILL.md"], []),
    ("refactor", "buried", "std", "artifact paths under the task directory drift between stages. plan a cleanup.",
     ["skills/task-folder-organization/SKILL.md"], []),
    ("incident", "buried", "emerg", "a stage handoff is failing schema validation and the run is stuck. plan the response.",
     ["skills/worktask/scripts/handoff-harness.sh"], []),

    # obvious: the prompt names the surface; only fabrication is being tested
    ("docs", "obvious", "std", "cross-plugin-handoff has no worked example for adding a new plugin. plan the documentation.",
     ["skills/cross-plugin-handoff/SKILL.md"], []),
    ("incident", "obvious", "emerg", "fn-preflight-cmds.sh is failing on every PR open. plan the response.",
     ["skills/worktask/scripts/fn-preflight-cmds.sh"], []),
    ("bug", "obvious", "secure", "judge-traces.py feeds untrusted response text into a bypassPermissions session. plan a fix.",
     ["evals/scripts/judge-traces.py"], []),
    ("feature", "obvious", "secure", "eval-capture.py stores raw model responses that may contain a password. plan a fix.",
     ["evals/scripts/eval-capture.py"], []),

    # adjacent: the near-miss surface exists and the plan must name it
    ("docs", "adjacent", "std", "we have no written policy for what makes a release deployable. plan the documentation.",
     ["skills/release-engineering/SKILL.md"], []),
    None,  # 114 — retired; see RETIRED
    ("incident", "adjacent", "emerg", "the trace review page is failing to load any captures. plan the response.",
     ["evals/scripts/build-review-page.py"], []),
    ("refactor", "adjacent", "std", "the issue publishing helper duplicates logic with its selftest. plan a split.",
     ["skills/worktask/scripts/publish-pl-issue-lib.sh"], []),
    ("docs", "adjacent", "std", "reviewers don't know what a senior-level estimate review must cover. plan the documentation.",
     ["skills/estimation-methodology/references/estimate-review.md"], []),
    ("incident", "obvious", "emerg", "publish-pl-issue-selftest.sh is failing and blocking every plan publish. plan the response.",
     ["skills/worktask/scripts/publish-pl-issue-selftest.sh"], []),

    # absent: nothing to ground on, so the case expects a clarification
    ("docs", "absent", "std", "the onboarding guide in our Notion workspace is out of date. plan the documentation.", [], []),
    ("incident", "absent", "emerg", "our Redis cluster is down and user sessions are dropping. plan the response.", [], []),
    ("bug", "absent", "std", "the mobile app crashes on cold start for Android 14 users. plan a fix.", [], []),

    # ---- batch 4 (ids 122+): rebuilding the search signal the registry spent ----
    # capability-registry.sh now enumerates hooks, skill scripts and harness modules, which
    # converts 42 of the 44 standing `buried` cases from a search into a lookup. From 0.2.0
    # forward the `buried` rate on those cases measures reading a list, not searching a tree.
    # These replace the lost denominator and ground ONLY on classes the registry deliberately
    # does not list: skills/*/references/, skills/shared/, and evals/scripts/. That exclusion
    # is pinned by capability-registry.bats, so widening the registry's globs breaks a test
    # before it silently answers these.
    #
    # Held out by construction: written after the frozen manifest, so whatever the generator
    # assigns to `test` is the first genuinely unseen tranche this corpus has had. Do not read
    # it before a capture, and do not pass --restratify, which would move already-read cases in.

    # buried: shared canon — behaviour that lives in a doc no registry line points at
    ("refactor", "buried", "std", "every agent picks its own model name and they have drifted apart. plan a cleanup.",
     ["skills/shared/model-selection.md"], []),
    ("docs", "buried", "std", "the two-letter abbreviations for pipeline steps mean different things in different files. plan the documentation.",
     ["skills/shared/stage-codes.md"], []),
    ("docs", "buried", "std", "nobody can tell what one step of the pipeline owes the next. plan the documentation.",
     ["skills/shared/stage-contracts.md"], []),
    ("docs", "buried", "std", "there is no written schema for the run record every step reads and writes. plan the documentation.",
     ["skills/shared/state-ledger.md"], []),
    ("docs", "buried", "std", "we have no agreed split between unit, integration and end-to-end coverage. plan the documentation.",
     ["skills/shared/testing-strategy.md"], []),
    ("bug", "buried", "std", "developers mark which tests to run in source comments and no two files agree on the format. plan a fix.",
     ["skills/shared/test-selection-syntax.md"], []),
    ("bug", "buried", "std", "a request for a niche platform falls through to the generic implementer. plan a fix.",
     ["skills/shared/platform-detection.md"], []),
    ("bug", "buried", "std", "the same role name resolves to a different specialist depending on which file you read. plan a fix.",
     ["skills/shared/routing-matrix.md"], []),
    ("feature", "buried", "std", "i want a single record of which external plugins we support and from which version. plan it.",
     ["skills/shared/compatible-plugins.md"], []),
    ("bug", "buried", "std", "our scripts break when the plugin is installed somewhere other than where we develop it. plan a fix.",
     ["skills/shared/plugin-root-resolution.md"], []),
    ("bug", "buried", "std", "people start a task by pasting a phrase instead of running the entry point, and it half-works. plan a fix.",
     ["skills/shared/worktask-invocation.md"], []),
    ("refactor", "buried", "std", "each agent restates the whole pipeline in its own words and the copies have drifted. plan a cleanup.",
     ["skills/shared/worktask-stage-context.md"], []),
    ("bug", "buried", "std", "our post-mortems stop at the first plausible cause and never reach the systemic one. plan a fix.",
     ["skills/shared/five-whys.md"], []),
    ("feature", "buried", "std", "i want to hand the planner a Word document and have it read as text. plan it.",
     ["skills/shared/pandoc-ingestion.md"], []),
    ("bug", "buried", "std", "a design link pasted into a request is ignored unless someone also says the word design. plan a fix.",
     ["skills/shared/figma-capture.md"], []),

    # buried: a skill's references/ — the half of a skill the registry line does not describe
    ("feature", "buried", "std", "i want to launch one pipeline step from a CI runner with no interactive session. plan it.",
     ["skills/agent-coordination/references/headless-dispatch.md"], []),
    ("docs", "buried", "std", "there is no written procedure for weighing a change that could hurt someone. plan the documentation.",
     ["skills/claude-constitution/references/harm-framework.md"], []),
    ("feature", "buried", "std", "nobody knows what a normal per-step spend looks like, so nothing can be called excessive. plan it.",
     ["skills/cost-optimization/references/token-baselines.md"], []),
    ("docs", "buried", "std", "we have nothing written down about which agent inside each external plugin serves each step. plan the documentation.",
     ["skills/cross-plugin-handoff/references/plugin-protocols.md"], []),
    ("feature", "buried", "std", "we cannot get UI evidence for a target that has no runnable simulator. plan it.",
     ["skills/dv-screenshot-capture/references/apple-canvas.md"], []),
    ("incident", "buried", "emerg", "every run is failing to attach any visual evidence because the capture tooling is missing. plan the response.",
     ["skills/dv-screenshot-capture/references/cli-fallback.md"], []),
    ("bug", "buried", "std", "two people sizing the same work get different numbers because they do the steps in a different order. plan a fix.",
     ["skills/estimation-methodology/references/estimation-run.md"], []),
    ("feature", "buried", "std", "i want the issues in a batch to run as one coordinated team rather than isolated sessions. plan it.",
     ["skills/megatask/references/agent-teams.md"], []),
    ("bug", "buried", "std", "batch issues start before the ones they are waiting on have finished. plan a fix.",
     ["skills/megatask/references/dependency-graph.md"], []),
    ("docs", "buried", "std", "the file that drives a batch run has no written schema. plan the documentation.",
     ["skills/megatask/references/schemas.md"], []),
    ("bug", "buried", "std", "designers keep hardcoding hex values instead of reusing the variable system. plan a fix.",
     ["skills/pencil-design-worktask/references/design-tokens.md"], []),
    ("bug", "buried", "std", "generated previews fail to compile because nothing knows what arguments the view needs. plan a fix.",
     ["skills/preview-ensurer/references/mock-data-strategy.md"], []),
    ("bug", "buried", "std", "we cannot reliably tell which types in a Swift file are actually renderable screens. plan a fix.",
     ["skills/preview-ensurer/references/view-detection.md"], []),
    ("incident", "buried", "emerg", "the release we shipped an hour ago is failing in production and we have no written way back. plan the response.",
     ["skills/release-engineering/references/rollback-template.md"], []),
    ("bug", "buried", "secure", "every reviewer checks a different subset of the standard vulnerability classes. plan a fix.",
     ["skills/security-review-process/references/owasp-checklist.md"], []),
    # Two surfaces genuinely own this and neither subsumes the other: review-template.md
    # is the standalone-review shape but only for SECURITY reviews, while
    # tech-code-review.md owns the code-review output format. The request says "our
    # code", so a plan that reaches either has found the surface. Both listed rather
    # than one picked — the 0.0.1 doc set that precedent for case 3.
    ("docs", "buried", "std", "a one-off review of our code comes out in a different shape every time, with no fixed sections. plan the documentation.",
     ["commands/tech-code-review.md",
      "skills/security-review-process/references/review-template.md"], []),
    ("bug", "buried", "std", "we record what the user changed but nothing says how to classify each change. plan a fix.",
     ["skills/self-improvement/references/change-categories.md"], []),
    ("docs", "buried", "std", "the learnings file a run leaves behind comes out differently every time. plan the documentation.",
     ["skills/self-improvement/references/retrospective-template.md"], []),
    ("bug", "buried", "std", "we know the user rewrote something but not which agent should have gotten it right. plan a fix.",
     ["skills/self-improvement/references/target-mapping.md"], []),
    ("refactor", "buried", "std", "the test-strategy block in a plan is written from scratch every run. plan a cleanup.",
     ["skills/worktask-testing-strategy/references/stage-templates.md"], []),
    ("feature", "buried", "std", "the two files our review tool expects are hand-written on every run. plan it.",
     ["skills/worktask/references/conductor-attachments.md"], []),
    ("docs", "buried", "std", "there is no written checklist for the human approval that happens before a PR opens. plan the documentation.",
     ["skills/worktask/references/fn-gate.md"], []),
    ("docs", "buried", "std", "the planning step has no written procedure and every run improvises it. plan the documentation.",
     ["skills/worktask/references/pl0-procedure.md"], []),
    ("feature", "buried", "std", "when a long run is interrupted there is no way to reattach and carry on. plan it.",
     ["skills/worktask/references/resume.md"], []),
    ("feature", "buried", "std", "nobody compares the screen we built against the design it came from. plan it.",
     ["skills/worktask/references/visual-qa.md"], []),

    # buried: eval infrastructure — real behaviour, and the registry lists none of evals/
    ("feature", "buried", "std", "our graded checks are applied by eye and nobody can reproduce a score. plan it.",
     ["evals/scripts/eval-engine.py"], []),
    ("feature", "buried", "std", "we have captured responses sitting on disk and nothing turns them into a pass rate. plan it.",
     ["evals/scripts/eval-grade.py"], []),
    ("bug", "buried", "std", "human judgements and machine scores disagree and nobody reconciles the two. plan a fix.",
     ["evals/scripts/label-align.py"], []),

    # obvious: the three 4.0.26 behaviours that shipped with no case at all. Framed as
    # coverage requests because each behaviour already ships as specified — asking to BUILD
    # one would be a refute case, and asking to VERIFY one is the plan SKILL.md § 4 owes.
    ("feature", "obvious", "std", "/appstore has no test proving it stops instead of guessing when a repo carries markers for both stores. plan it.",
     ["commands/appstore.md"], []),
    ("feature", "obvious", "std", "nothing checks that /estimate --detailed bases its budget on the post-review story points. plan a test.",
     ["commands/estimate.md"], []),
    ("feature", "obvious", "std", "nothing verifies the release-engineer agent hands off instead of working inline when its platform plugin is absent. plan it.",
     ["agents/release-engineer.md"], []),
]


def surface_tokens(paths: list) -> list:
    """Name the ground file, not the vocabulary around it.

    Hand-written values leaked: three plans passed on `era`, `breach` and a
    neighbouring hook's name while never touching the declared file. These accept
    only forms that identify the file itself — including how a plan naturally
    refers to it, which for a command is `/name`, not `commands/name.md`.

    A bare stem counts only when hyphenated. `state-patch` is unique in this repo;
    `analysis` and `budget` are words any plan might use, and admitting them is
    what let the leaks through.
    """
    tokens = []
    for rel in paths:
        base = os.path.basename(rel)
        stem, _, _ = base.rpartition(".")
        tokens.append(rel)
        if base == "SKILL.md":
            # NOT the bare basename. "SKILL.md" matches any response naming any skill
            # file, so it grades nothing; the owning directory is what identifies this one.
            tokens.append(os.path.basename(os.path.dirname(rel)))
            continue
        tokens.append(base)
        if rel.startswith("commands/"):
            tokens.append("/" + stem)
        if "-" in stem:
            tokens.append(stem)
    return sorted(set(tokens))


# Cases whose prompt states something this repo has since made false — the work
# shipped, or the file no longer looks the way the prompt describes. The correct answer
# disputes the premise with evidence, which the plan template cannot score.
#
# Registered by hand after a reviewer checked the premise against the repo, and it goes
# STALE the same way: a prompt that becomes true again must come off this list. Never
# infer refutation from the response -- an inferred hatch is one any answer can take.
# id -> (kind, why). `kind` matters: the rule differs by what remains to be done.
#   "shipped"         — the capability exists, nothing remains, so the answer refutes and
#                       STOPS: no template, no trigger.
#   "disputed-defect" — the reported bug is misdiagnosed or unreproducible, but triage IS
#                       work, so SKILL.md § 4 still owes the trigger.
# Every current member is "shipped". The flag exists so the first disputed-defect case added
# here is not auto-generated with assertions that fail it for obeying the rule.
REFUTED_PREMISE = {
    # (kind, prompt anchor, why). The anchor is not decoration: ids are positional, so a
    # future edit to CASES that shifts one would re-point every entry below at a different
    # prompt with no error. validate() checks each anchor against the case it lands on.
    2: ("shipped", "dispatch.py has grown",
        "dispatch.py was split in 18ba0c2; it is now a 352-line orchestration shim"),
    3: ("shipped", "fn-preflight.sh is 24KB",
        "c51ffa7 extracted the command bodies into a sourced library; 24,961 -> 8,763 B"),
    # NOT here, deliberately: case 4 ("CHANGELOG.md is <N>KB"). d32c8b3 split the release
    # history, but the file has since regrown past the size the premise names, so what went
    # stale was the NUMBER, not the request — it belongs with the correct-the-figure cases,
    # not the shipped-work conversions. 5 and 53 were re-audited against the same test and
    # stay: both cite shipped behaviour, and a shipped capability is not a stale measurement.
    5: ("shipped", "the comment density gate rejects DocC",
        "913d786 scores comment blocks rather than the raw ratio"),
    7: ("shipped", "genlib.py mixes a subprocess wrapper",
        "genlib.py was split in 8fe5aec; treecopy.py owns materialization"),
    13: ("shipped", "audit-tooluse.sh may be logging tool inputs",
         "e755c7e pinned the contract that only task_id and status derive from tool_input, "
         "guarded by audit-tooluse.bats"),
    # Evidence repointed 2026-08-26: the original cited /cost-report --export, which 4.0.26
    # deleted along with the rest of cost observability. The capability still ships, and now
    # through the case's own grounding surface rather than a neighbouring command.
    16: ("shipped", "cost numbers exportable into a spreadsheet",
         "/estimate --export csv emits the 13-file pack defined by "
         "skills/csv-export-templates/SKILL.md, whose 07_budget_estimate.csv is the cost "
         "breakdown; the schema is pinned by validate-export.sh and validate-export.bats"),
    17: ("shipped", "stage handoffs silently lose facts",
         "8718972 added the facts.* union op the handoff channel lacked"),
    19: ("shipped", "leaking absolute paths from my machine",
         "fe795df strips absolute paths from every mount and route"),
    21: ("shipped", "branches come out with inconsistent names",
         "4196f2d unified batch branch naming with the worktask convention"),
    # Evidence repointed 2026-08-26: /agent-report was removed in 4.0.26. Only the packaged
    # reader went — the recording hook and the canonical read path both survive it.
    22: ("shipped", "which agents actually ran during a task",
         "hooks/audit-subagent.sh writes one subagent_stopped row per agent, and "
         "skills/agent-coordination/scripts/audit-dedup.sh is the canonical reader over it"),
    26: ("shipped", "duplicate tickets for the same piece of work",
         "107fc00 added the preflight issue scan that catches duplicates before the context exists"),
    30: ("shipped", "wedged in_progress and nothing will pick it up",
         "6db5984 added stale-check.sh, which detects stages wedged in_progress with no live agent"),
    53: ("shipped", "baseline.py picks the wrong arm",
         "46a1870 treats a full --stages list as a full run, not a subset"),
    56: ("shipped", "the product-manager agent is 52KB",
         "ed60cd9 extracted the PL0 procedure to a reference file; 53,902 -> 8,143 B"),
    58: ("shipped", "add a machine-readable verdict to the technical-lead",
         "488cd7a added tc_verdict for TC consults"),
    59: ("shipped", "the release-engineer agent emits the wrong version bump",
         "8c3d3ef added deterministic version-bump determination"),
    60: ("shipped", "add a threat-model section to the security-reviewer",
         "73765a1 added the STRIDE threat model to SR0"),
    85: ("shipped", "replay a failed stage without rerunning",
         "bde89d5 added explicit single-stage replay for failed stages"),
    # NOT converted, deliberately: case 87 ("the nesting depth limit silently drops a
    # specialist"). 400bb90 shipped the dispatch_flattened self-report, but
    # agent-coordination SKILL.md:292 says of it "It closes the silence; it does not
    # guarantee capture" — the mechanism is advisory, with no hook behind it. A plan for
    # the enforcing hook is therefore still a correct answer, so both outcomes are
    # defensible and the case cannot serve as ground truth for either. It stays a plan.
}


def build_case(index: int, spec) -> dict:
    kind, grounding, _declared_route, prompt, paths, discovery = spec
    route = derive_route(prompt)
    case = {"id": index, "prompt": prompt,
            "dimensions": {"type": kind, "grounding": grounding, "route": route}}
    if index in REFUTED_PREMISE:
        refute_kind, _anchor, refute_why = REFUTED_PREMISE[index]
        case["expected_outcome"] = "refute"
        case["refute_kind"] = refute_kind
        case["premise_refuted_by"] = refute_why
        case["assertions"] = [
            {"id": "disputes-the-premise",
             "why": "The answer must say the premise does not hold. Scoring these against "
                    "the plan template failed case 2 on six assertions while it was right",
             "type": "regex_any",
             # Tense-agnostic on purpose. The first cut listed past participles only and
             # missed case 22's "already **ships** in this plugin" — the same overfit that
             # got cites-measured-evidence withdrawn, still live in the criterion kept.
             #
             # The 0.0.1 capture widened it again, and the misses were not exotic: case 13
             # opened "Already fixed — no plan needed" and case 22 "already does exactly
             # this". Both are textbook refutations the verb list simply did not carry.
             # Any verb that can follow "already" and mean the work is done belongs here.
             # (?i) on every pattern: eval-engine matches with re.MULTILINE and NOT
             # re.IGNORECASE, so a lowercase pattern cannot see a refutation that opens the
             # response — which is exactly where a refutation belongs. Case 13 led with
             # "Already fixed — no plan needed" and was scored as never disputing anything.
             "values": [r"(?i)already\s+\w*\s*(ship|ships|shipped|land|landed|split|exist|"
                        r"exists|done|does|did|implemented|happened|in place|fixed|closed|"
                        r"solved|resolved|addressed|handled|covered|supported|works|working)",
                        r"(?i)(already|has been|have been|was|were)\s+"
                        r"(fixed|shipped|closed|resolved|addressed|split|extracted|added)",
                        r"(?i)no longer", r"(?i)does not exist", r"(?i)is not (present|there)",
                        r"(?i)(premise|claim) (is|was) "
                        r"(stale|false|wrong|outdated|no longer true)",
                        r"(?i)not\s+\d+(\.\d+)?\s*KB"]},
            # Replaces no-build-plan-for-work-that-exists, withdrawn at 0.1.0. That criterion
            # forbade the plan template on any refute case. The 0.0.1 capture measured it:
            # it fired on 12 cases, ALL 12 of which a human passed, and did NOT fire on case
            # 22, the one refute case a human failed — TNR 0%, the same pathology that
            # retired the LLM judge. It also now contradicts SKILL.md § 4, which since 0.1.0
            # requires a plan for a live remainder behind a shipped headline. A refutation
            # that goes on to plan the real remaining gap is the BEST answer, not a failure.
            #
            # What survives is the other half of "say so, cite where": a refutation has to
            # name a path that resolves. paths_resolve, not a token match on the ground file
            # — the prompt already supplies that filename, so matching it grades an echo.
            # paths_resolve was tried here first and withdrawn the same day: it failed
            # case 7, a textbook refutation that cites commit 8fe5aec and names genlib.py /
            # treecopy.py by basename, because a bare filename is deliberately not a cited
            # path (it would echo the prompt, which supplied the name). A refutation's
            # evidence is a SHA as often as a path, so accept either shape.
            {"id": "cites-evidence",
             "why": "A refutation is a claim about this repo, so it owes something checkable "
                    "— a path or the commit that closed the premise. Without one, 'that "
                    "already ships' is indistinguishable from a guess, and a guess that "
                    "happens to be right still teaches the skill to assert instead of check. "
                    "A FLOOR, not a score: all 20 refute responses in the 0.0.1 capture "
                    "cleared it, so it catches regression, not quality",
             "type": "regex_any",
             "values": [r"[\w.-]+/[\w.-]+\.(py|sh|md|json|bats)",
                        r"`[0-9a-f]{7,40}`",
                        r"\bcommit\s+`?[0-9a-f]{7,40}`?"]},
        ]
        case["grounding"] = paths
        case["deferred"] = [
            "Whether the evidence cited actually proves the premise false — needs a "
            "validated judge with repo access.",
            # Tried and withdrawn: a regex over commit SHAs, line counts and byte sizes.
            # Four refute cases produced four evidence shapes (SHA+size, SHA alone, a
            # .bats file plus a spec section), so each pattern fixed one case and broke
            # another. Naming the file instead only echoes the prompt, which supplied it.
            # Graded badly it is worse than ungraded; this is a judge criterion.
            "Whether the refutation cites evidence it actually read, in whatever form.",
            # Withdrawn from grading at 0.1.0 with its measurement attached, per the same
            # rule that retired the judge: a criterion with no true positives is worse than
            # no criterion, because it reads as coverage.
            "Whether a refutation that also renders the plan template is planning the work "
            "it just refuted (wrong) or the live remainder behind it (right) — 0/12 "
            "precision as a regex in the 0.0.1 capture; needs a judge that can tell the "
            "two apart by what the plan is ABOUT.",
        ]
        return case
    if grounding == "absent":
        case["expected_outcome"] = "clarify"
        case["assertions"] = []
        case["grounding"] = []
        case["deferred"] = ["Whether the question it asks is the most useful one — needs a validated judge."]
        return case

    route_id, route_why, route_values = ROUTE_ASSERTION[route]
    route_kind = "regex_all"
    case["expected_outcome"] = "plan"
    # An `obvious` prompt already names the file, so any discovery target would be a
    # guess at which OTHER file the plan should touch — and a guess fails correct
    # plans that decomposed differently. paths_resolve keeps that restraint: it names
    # no target, and only requires that what the plan cites is real.
    discovery_assertion = (
        {"id": "cites-a-repo-path",
         "why": "A plan that located the file cites at least one path that resolves. Matching "
                "a path's shape passed 36 of 36, including one plan citing three invented "
                "files beside the one it was handed. Two was tried and rejected: it failed 8 "
                "plans a human passed, because a plan that cites the handed file by full path "
                "and its neighbours by bare name resolves exactly one. Resolving-path count "
                "barely tracks quality (56% human-pass at zero, 71% at three), so this is a "
                "fabrication floor, not a grounding score",
         "type": "paths_resolve", "values": [1]}
        if grounding == "obvious" else
        {"id": "finds-the-real-surface",
         "why": "The plan must reach the surface this repo actually has. Relaxing this to "
                "'any real path' let seven plans past that named a plausible neighbour and "
                "never touched the ground file",
         "type": "regex_any", "values": surface_tokens(paths)})
    case["assertions"] = [
        {"id": route_id, "why": route_why, "type": route_kind, "values": route_values},
        discovery_assertion,
    ]
    case["grounding"] = paths
    case["deferred"] = ["Whether the phases are sequenced by risk rather than chopped in thirds — needs a validated judge."]
    return case


# Routing ground truth must follow from the REQUEST, never from what investigation
# later reveals. Hand-assigned tiers failed correct plans: a prompt was labelled
# secure on a suspicion the code turned out not to have.
# Names a protected asset or attacker-controlled input. Deliberately excludes words
# that only make a request ABOUT security ("threat-model the reviewer agent"), which
# is a documentation task carrying no sensitive surface of its own.
SECURE_MARKERS = ("credential", "secret", "token", "api key", "password", "pii",
                  "personal data", "encrypt", "auth", "sensitive",
                  "untrusted", "injection", "exploit", "vulnerab")
# Live breakage only — present-tense incident markers, not any present participle,
# which would sweep in ordinary bug reports.
EMERGENCY_MARKERS = ("right now", "is down", "outage", "503", "is failing",
                     "is rejecting", "is hanging", "is killing", "is blocking")


def derive_route(prompt: str) -> str:
    text = prompt.lower()
    if any(m in text for m in SECURE_MARKERS):
        return "secure"
    if any(m in text for m in EMERGENCY_MARKERS):
        return "emerg"
    return "std"


SPLIT_CYCLE = ("dev", "test", "dev", "test", "train")  # ~40/40/20


SPLIT_MANIFEST = os.path.join(REPO, "evals", "splits", "request-plan.json")

# Written into the manifest by --restratify. It has to say what a re-stratified tranche
# is and is not, because the word "test" otherwise implies held-out and this one is not.
RESTRATIFY_NOTE = (
    "Frozen split assignment. A case NEVER changes tranche: membership that moves after a "
    "tranche has been read silently contaminates the held-out set.\n\n"
    "2026-08-23: re-stratified from scratch for the 0.0.1 baseline reset, discarding the "
    "prior manifest. This is the one deliberate breach of the rule above and it is behind "
    "gen-request-plan-cases.py --restratify.\n\n"
    "READ THIS BEFORE QUOTING A TEST NUMBER: re-stratifying does not make the cases unread. "
    "Every case in 0.0.1 predates the reset and most were examined under the versions whose "
    "results the reset deleted, so `test` here is NOMINAL, not held-out. It buys stratified "
    "balance across grounding, nothing more. A genuinely unseen tranche needs genuinely new "
    "cases, written after this manifest and pinned to test before any capture reads them -- "
    "which is what the 97-121 tranche did, and what its successor must do again.\n\n"
    "Retired ids leave gaps here. Ids are positional in gen-request-plan-cases.py, so the "
    "retired slots stay open rather than renumbering every later case."
)


def assign_splits(cases: list, restratify: bool = False) -> list:
    """Read tranche membership from the frozen manifest; stratify only what is new.

    Membership must never move. Stratifying on a dimension that later gets
    re-derived reshuffled dev and test after dev had been read, which silently
    put examined cases into the held-out set.

    An unreadable manifest used to fall through to `frozen = {}`, which reshuffles
    every tranche and reports success — the loudest possible breach of the rule
    above, delivered silently. It now returns an error unless `--restratify` says a
    full reshuffle is what was asked for. Returns the error list, not None.
    """
    try:
        with open(SPLIT_MANIFEST, encoding="utf-8") as f:
            frozen = json.load(f)["splits"]
    except (OSError, ValueError, KeyError) as exc:
        if not restratify:
            return [f"split manifest unreadable ({exc}); every case would be "
                    f"re-stratified. Pass --restratify if that is deliberate"]
        frozen = {}
    if restratify:
        frozen = {}

    unseen: dict = {}
    for case in cases:
        pinned = frozen.get(str(case["id"]))
        if pinned:
            case["split"] = pinned
        else:
            unseen.setdefault(case["dimensions"]["grounding"], []).append(case)
    for members in unseen.values():
        for position, case in enumerate(members):
            case["split"] = SPLIT_CYCLE[position % len(SPLIT_CYCLE)]
    return []


def validate_tables() -> list:
    """Check the id-keyed side tables against CASES before a single case is built.

    Ids are positions in CASES, and three tables key on them. Nothing else would
    notice a slot moving: a shifted RETIRED entry silently un-retires one case and
    deletes another, and a shifted REFUTED_PREMISE entry hands a live prompt the
    wrong commit as its evidence — both produce a well-formed set that measures the
    wrong thing, which is the one failure a paid capture cannot recover from.
    """
    errors = []
    tombstones = {i for i, spec in enumerate(CASES, start=1) if spec is None}
    for cid in sorted(tombstones - set(RETIRED)):
        errors.append(f"case {cid}: retired slot with no RETIRED entry saying why")
    for cid in sorted(set(RETIRED) - tombstones):
        errors.append(f"case {cid}: RETIRED entry but the slot still holds a case")
    for cid, (_kind, anchor, _why) in sorted(REFUTED_PREMISE.items()):
        if not 1 <= cid <= len(CASES) or CASES[cid - 1] is None:
            errors.append(f"case {cid}: REFUTED_PREMISE points at no case")
        elif anchor.lower() not in CASES[cid - 1][3].lower():
            errors.append(f"case {cid}: REFUTED_PREMISE anchor {anchor!r} is not in that "
                          f"case's prompt — the ids have shifted under this table")
    errors += validate_named_surfaces()
    return errors


# Claude Code ships these; they resolve to no file in commands/ and never will.
BUILTIN_COMMANDS = {"/clear", "/compact", "/config", "/context", "/cost", "/help",
                    "/init", "/model", "/plugins", "/agents"}
_SLASH = re.compile(r"(?<![A-Za-z0-9/._*!-])/([a-z][a-z0-9-]{2,})\b")


def validate_named_surfaces() -> list:
    """Fail closed on a prompt or a refutation that names a deleted command.

    `premise_refuted_by` is the EVIDENCE a refute case is graded against, so a command
    removed from the tree turns it into a citation of nothing while the case keeps
    passing. 4.0.26 deleted eight commands and this table kept naming two of them for
    three days; only a hand grep found it. A prompt naming one is worse — the case has
    no correct answer at all, and belongs in RETIRED rather than here.
    """
    errors = []
    live = {p[:-3] for p in os.listdir(os.path.join(REPO, "commands")) if p.endswith(".md")}
    for cid, spec in enumerate(CASES, start=1):
        if spec is None:
            continue
        fields = [("prompt", spec[3])]
        if cid in REFUTED_PREMISE:
            fields.append(("premise_refuted_by", REFUTED_PREMISE[cid][2]))
        for field, text in fields:
            for name in {m.group(1) for m in _SLASH.finditer(text)}:
                if name in live or f"/{name}" in BUILTIN_COMMANDS:
                    continue
                errors.append(f"case {cid}: {field} names /{name}, which is not a command "
                              f"in this tree")
    return errors


def validate(cases: list) -> list:
    """Fail closed before any case can reach a paid capture."""
    errors = []
    for case in cases:
        cid, prompt = case["id"], case["prompt"].lower()
        for rel in case["grounding"]:
            if not os.path.exists(os.path.join(REPO, rel)):
                errors.append(f"case {cid}: grounding path missing: {rel}")
        if case["expected_outcome"] == "plan" and not case["grounding"]:
            errors.append(f"case {cid}: expects a plan but declares no grounding")
        for assertion in case["assertions"]:
            if not assertion["values"]:
                errors.append(f"case {cid}: {assertion['id']} has no values")
            for value in assertion["values"]:
                if not isinstance(value, str):
                    continue  # paths_resolve carries a count, not a pattern
                for token in (t for t in value.lower().split() if len(t) > 5):
                    if token.strip("\\s+*?[]()") in prompt:
                        errors.append(f"case {cid}: {assertion['id']} echoes '{token}'")
    return errors


def main(argv) -> int:
    p = argparse.ArgumentParser(prog="gen-request-plan-cases")
    p.add_argument("--out", default=DEFAULT_OUT)
    p.add_argument("--check", action="store_true", help="validate only, write nothing")
    p.add_argument("--restratify", action="store_true",
                   help="discard the frozen split manifest and re-stratify every case. "
                        "Moves cases between tranches, so a case already read can land in "
                        "test; only correct when the whole corpus is being reset")
    args = p.parse_args(argv)

    errors = validate_tables()
    cases = [build_case(i, spec) for i, spec in enumerate(CASES, start=1)
             if spec is not None] if not errors else []
    errors += assign_splits(cases, restratify=args.restratify)
    errors += validate(cases)
    if errors:
        for e in errors:
            sys.stderr.write(f"gen-request-plan-cases: {e}\n")
        return 1

    with open(args.out, encoding="utf-8") as f:
        existing = json.load(f)
    existing["evals"] = cases
    existing["dimensions"] = {
        "type": sorted({c["dimensions"]["type"] for c in cases}),
        "grounding": sorted({c["dimensions"]["grounding"] for c in cases}),
        "route": sorted({c["dimensions"]["route"] for c in cases}),
    }
    if not args.check:
        with open(args.out, "w", encoding="utf-8") as f:
            json.dump(existing, f, indent=2, ensure_ascii=False)
            f.write("\n")

    if args.restratify and not args.check:
        # Written here or not at all: the manifest is what freezes the tranches, so a
        # re-stratification that only lands in evals.json is undone by the next plain run.
        with open(SPLIT_MANIFEST, "w", encoding="utf-8") as f:
            json.dump({"note": RESTRATIFY_NOTE,
                       "splits": {str(c["id"]): c["split"] for c in cases}},
                      f, indent=2, ensure_ascii=False)
            f.write("\n")
        print(f"re-stratified -> {SPLIT_MANIFEST}")

    counts = collections.Counter(c["expected_outcome"] for c in cases)
    shape = " / ".join(f"{counts[k]} {k}" for k in ("plan", "clarify", "refute") if counts[k])
    print(f"{len(cases)} cases ({shape}) -> {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
