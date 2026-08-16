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
import json
import os
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

# (type, grounding, route, prompt, grounding_paths, discovery_values)
# discovery_values must NOT appear in the prompt — enforced below.
CASES = [
    # ---- exists-obvious: prompt names the surface; discovery targets a relative ----
    ("bug", "obvious", "std", "state-merge.sh is dropping keys when two stages patch at once. plan a fix.",
     ["hooks/state-merge.sh"], ["state-patch", "atomic", "ledger"]),
    ("refactor", "obvious", "std", "dispatch.py has grown past 30KB. how would you break it up?",
     ["benchmark/harness/benchmarklive/dispatch.py"], ["preamble", "baseline", "budget"]),
    ("refactor", "obvious", "std", "fn-preflight.sh is 24KB in one file. plan an extraction.",
     ["skills/worktask/scripts/fn-preflight.sh"], ["pr-body-lint", "branch-lib", "section-lint"]),
    ("docs", "obvious", "std", "CHANGELOG.md is 183KB and unreadable. what's the plan to split it?",
     ["CHANGELOG.md"], ["release", "version", "semver"]),
    ("bug", "obvious", "std", "the comment density gate rejects DocC that looks fine to me. plan a fix.",
     ["hooks/dv-comment-density-gate.sh"], ["comment-standard", "code-comment", "DocC ratio"]),
    ("feature", "obvious", "std", "add a --dry-run mode to the megatask skill. what's the plan?",
     ["skills/megatask/SKILL.md"], ["milestone", "dependency", "issue"]),
    ("refactor", "obvious", "std", "genlib.py mixes a subprocess wrapper with tree copying. plan a split.",
     ["benchmark/harness/benchmarkkit/genlib.py"], ["oracle", "deterministic", "generators"]),
    ("bug", "obvious", "std", "branch-name.sh renames a branch that already tracks a remote. plan the fix.",
     ["skills/worktask/scripts/branch-name.sh"], ["branch-lib", "conventional", "guard"]),
    ("feature", "obvious", "std", "add a machine-readable summary to cost-report. plan it.",
     ["commands/cost-report.md"], ["csv-export", "token", "usage"]),
    ("docs", "obvious", "std", "the analysis.py module has no module docs. plan the documentation.",
     ["benchmark/harness/benchmarkkit/analysis.py"], ["era", "comparab", "report"]),
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
    ("bug", "buried", "std", "our stage handoffs silently lose facts between stages. plan a fix.",
     ["hooks/state-merge.sh"], ["state-merge", "state-patch", "ledger"]),
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
    ("bug", "buried", "std", "the doc anchors in stage artifacts drift from the templates. plan a fix.",
     ["skills/worktask/scripts/section-lint.sh"], ["section-lint", "anchor-preflight"]),
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
    ("bug", "adjacent", "std", "the retry matrix loops forever when a stage keeps failing. plan a fix.",
     ["skills/worktask/references/handoff-protocol.md"], ["handoff-protocol", "escalate"]),
    ("feature", "adjacent", "std", "put a spend ceiling on a task so it can't run away. plan it.",
     ["commands/cost-report.md"], ["cost-report", "budget"]),
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
    ("refactor", "obvious", "std", "state-patch.sh is 55KB. plan how to break it apart.",
     ["skills/worktask/scripts/state-patch.sh"], ["state-merge", "ledger", "atomic"]),
    ("refactor", "obvious", "std", "publish-pl-issue.sh is enormous. plan an extraction.",
     ["skills/worktask/scripts/publish-pl-issue.sh"], ["gh-issue-dedup", "milestone", "anchor"]),
    ("bug", "obvious", "std", "attachments-preseed.sh leaves temp files behind. plan a fix.",
     ["skills/worktask/scripts/attachments-preseed.sh"], ["cleanup", "trap", "mktemp"]),
    ("feature", "obvious", "std", "add a JSON output mode to desc-lint.sh. what's the plan?",
     ["skills/worktask/scripts/desc-lint.sh"], ["section-lint", "structured", "machine"]),
    ("bug", "obvious", "std", "detect-ui-change.sh misses SwiftUI-only diffs. plan a fix.",
     ["skills/worktask/scripts/detect-ui-change.sh"], ["screenshot", "visual", "evidence"]),
    ("refactor", "obvious", "std", "metrics.py has grown to 14KB of mixed concerns. plan a split.",
     ["benchmark/harness/benchmarkkit/metrics.py"], ["coverage", "usage", "report"]),
    ("bug", "obvious", "std", "report.py rounds costs inconsistently. plan a fix.",
     ["benchmark/harness/benchmarkkit/report.py"], ["metrics", "analysis", "precision"]),
    ("feature", "obvious", "std", "add a resume flag to deterministic_run.py. plan it.",
     ["benchmark/harness/benchmarkkit/deterministic_run.py"], ["oracle", "rotation", "seed"]),
    ("docs", "obvious", "std", "rotation.py has no explanation of why it exists. plan the docs.",
     ["benchmark/harness/benchmarkkit/rotation.py"], ["order", "bias", "arm"]),
    ("bug", "obvious", "std", "baseline.py picks the wrong arm on a subset run. plan a fix.",
     ["benchmark/harness/benchmarklive/baseline.py"], ["resolve_arm", "selection", "policy"]),
    ("feature", "obvious", "std", "let budget.py warn before the cap rather than after. plan it.",
     ["benchmark/harness/benchmarklive/budget.py"], ["threshold", "running tally", "breach"]),
    ("refactor", "obvious", "std", "the developer agent file is 55KB. plan how to shrink it.",
     ["agents/developer.md"], ["routing", "platform", "delegate"]),
    ("refactor", "obvious", "std", "the product-manager agent is 52KB of prose. plan a trim.",
     ["agents/product-manager.md"], ["requirements", "planning", "template"]),
    ("docs", "obvious", "std", "the qa-engineer agent doesn't say who owns full suites. plan the docs.",
     ["agents/qa-engineer.md"], ["testing-strategy", "authority", "scoped"]),
    ("feature", "obvious", "std", "add a machine-readable verdict to the technical-lead agent. plan it.",
     ["agents/technical-lead.md"], ["frontmatter", "handoff", "structured"]),
    ("bug", "obvious", "std", "the release-engineer agent emits the wrong version bump. plan a fix.",
     ["agents/release-engineer.md"], ["semver", "changelog", "release-engineering"]),
    ("feature", "obvious", "secure", "add a threat-model section to the security-reviewer agent. plan it.",
     ["agents/security-reviewer.md"], ["OWASP", "security-review-process", "auditor"]),
    ("bug", "obvious", "secure", "anchor-preflight.sh may execute untrusted anchor text. plan a fix.",
     ["hooks/anchor-preflight.sh"], ["injection", "quote", "eval"]),
    ("migration", "obvious", "secure", "hook-install.sh writes settings without a backup. plan a safer path.",
     ["skills/worktask/scripts/hook-install.sh"], ["idempot", "rollback", "restore"]),
    ("incident", "obvious", "emerg", "agent-stop.sh is killing live stages. plan the response.",
     ["hooks/agent-stop.sh"], ["subagent", "stop", "signal"]),
    ("incident", "obvious", "emerg", "the dv screenshot gate is blocking every task right now. plan it.",
     ["hooks/dv-screenshot-gate.sh"], ["visual", "evidence", "requires_screenshots"]),

    # ---- batch 2: buried ----
    ("feature", "buried", "std", "i want to know why one run cost triple another. plan it.",
     ["benchmark/harness/benchmarkkit/analysis.py"], ["analysis", "era", "comparab"]),
    ("bug", "buried", "std", "the generated app passes its own tests but is still wrong. plan a fix.",
     ["benchmark/harness/benchmarkkit/oracle.py"], ["oracle", "golden", "conformance"]),
    ("feature", "buried", "std", "i want the same task run twice and compared fairly. plan it.",
     ["benchmark/harness/benchmarkkit/rotation.py"], ["rotation", "order", "arm"]),
    ("bug", "buried", "std", "our headless runs can reach the network when they shouldn't. plan a fix.",
     ["benchmark/live/settings/benchmark-settings.json"], ["deny", "settings", "permission"]),
    ("feature", "buried", "std", "i want a written record of every architectural choice. plan it.",
     ["commands/arch-decision.md"], ["arch-decision", "ADR", "TDR"]),
    ("feature", "buried", "std", "i need to rank a backlog objectively. plan it.",
     ["commands/pm-prioritize.md"], ["pm-prioritize", "RICE", "WSJF"]),
    ("bug", "buried", "std", "our docs drift out of sync with the code. plan a fix.",
     ["commands/docs-audit.md"], ["docs-audit", "gap", "outdated"]),
    ("feature", "buried", "std", "i want release notes written from what actually shipped. plan it.",
     ["commands/docs-release-notes.md"], ["release-notes", "changelog"]),
    ("feature", "buried", "std", "i want to check a screen works for people using a reader. plan it.",
     ["commands/design-accessibility.md"], ["accessibility", "audit", "WCAG"]),
    ("bug", "buried", "std", "nobody can tell how much context is left before a compaction. plan a fix.",
     ["commands/context-status.md"], ["context-status", "compression", "utilization"]),
    ("feature", "buried", "std", "i want an outside opinion on whether a feature is worth building. plan it.",
     ["commands/business-report.md"], ["business-report", "ROI", "case"]),
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
     ["commands/pm-requirements.md"], ["pm-requirements", "PRD"]),
    ("incident", "adjacent", "emerg", "a batch run is burning budget with no way to stop it. plan it.",
     ["benchmark/harness/benchmarklive/budget.py"], ["running tally", "breach", "ceiling"]),

    # ---- batch 2: absent ----
    ("feature", "absent", "std", "add SSO with Okta to the admin console. what's the plan?", [], []),
    ("bug", "absent", "std", "our Kubernetes pods keep OOMing under load. plan a fix.", [], []),
    ("migration", "absent", "secure", "plan moving customer PII out of the analytics warehouse.", [], []),
    ("incident", "absent", "emerg", "the payment processor is rejecting every charge. plan the response.", [], []),
    ("docs", "absent", "std", "our public API reference is out of date. plan the documentation.", [], []),
    ("feature", "absent", "std", "add an offline mode to the desktop client. what's the plan?", [], []),
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
        tokens.append(base)
        if base == "SKILL.md":
            tokens.append(os.path.basename(os.path.dirname(rel)))
            continue
        if rel.startswith("commands/"):
            tokens.append("/" + stem)
        if "-" in stem:
            tokens.append(stem)
    return sorted(set(tokens))


def build_case(index: int, spec) -> dict:
    kind, grounding, _declared_route, prompt, paths, discovery = spec
    route = derive_route(prompt)
    case = {"id": index, "prompt": prompt,
            "dimensions": {"type": kind, "grounding": grounding, "route": route}}
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
    # plans that decomposed differently. Demand evidence of reading instead: a
    # slashed repo path, which a prompt carrying a bare filename cannot supply.
    discovery_assertion = (
        {"id": "cites-a-repo-path",
         "why": "A plan that located the file cites its real path; echoing the bare filename "
                "from the request proves nothing was read",
         "type": "regex_any", "values": [r"[\w.-]+/[\w.-]+\.(py|sh|md|json|bats)"]}
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


def assign_splits(cases: list) -> None:
    """Read tranche membership from the frozen manifest; stratify only what is new.

    Membership must never move. Stratifying on a dimension that later gets
    re-derived reshuffled dev and test after dev had been read, which silently
    put examined cases into the held-out set.
    """
    try:
        with open(SPLIT_MANIFEST, encoding="utf-8") as f:
            frozen = json.load(f)["splits"]
    except (OSError, ValueError, KeyError):
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
    args = p.parse_args(argv)

    cases = [build_case(i, spec) for i, spec in enumerate(CASES, start=1)]
    assign_splits(cases)
    errors = validate(cases)
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

    planning = sum(1 for c in cases if c["expected_outcome"] == "plan")
    print(f"{len(cases)} cases ({planning} plan / {len(cases) - planning} clarify) -> {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
