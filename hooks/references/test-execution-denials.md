# Test-execution denial remediation

Remediation prose for `hooks/test-execution-gate.sh`. The gate composes each denial as
*condition clause* (inline, because assertions match it) + *the section below* (read here on
the deny path only). Editing a section changes what the gate says on the next run.

Each section is delimited by an HTML comment holding its id; the gate reads the lines between
one marker and the next and joins them with single spaces, so a paragraph may wrap freely but
a blank line is not a paragraph break in the emitted text. An unreadable document degrades to
the condition clause alone: a gate that cannot find its help text must still deny, and must
never deny harder than it would with the text present.

## Wording constraints

These hold for every section and are not style preferences — each is a defect the wording
already caused once:

- **Name the agent-serviceable relief first.** `requests_test_evidence` and blocked-escalation
  are self-serviceable from inside a stage's own artifact; `--no-test` gets what the caller
  usually wants without any authority change. Omitting `--no-test` cost one run two streams:
  both were denied, neither discovered the flag, both invented `--build-only` (which no
  build-test command accepts and the classifier therefore reads as a full test run), and both
  fell back to raw toolchain calls — exactly what `agents/developer.md` forbids. A denial that
  does not name the supported escape hatch manufactures that workaround.
- **Frame `CORPFLOW_TEST_GATE=off` / `CORPFLOW_TEST_DEDUPE=off` as a human ask.** The hook
  reads process env, not the command string, so a retry carrying the variable as a prefix
  denies identically. Text that reads like an agent-serviceable flag invites that retry loop.
- **Do not reuse the per-stage wording for a settled ledger.** It would print "Stage '(none in
  progress)' has no authority", which reads as a bug and says nothing about why *now* is the
  wrong time.

<!-- authority -->
DV may run scoped tests only; QA is the sole full-suite authority. To proceed: (1) if you only
need to BUILD, re-run the same build-test command with --no-test — build-only verification is
permitted at every stage and is allowed by this gate (note: --build-only is not a real flag and
will be denied again); (2) record requests_test_evidence: <what and why> in this stage's
artifact so QA executes it; or (3) return verdict: blocked with error_escalated_to: "DV" if it
blocks this stage's completion. Do NOT fall back to invoking the toolchain directly —
agents/developer.md requires build/test to go through the platform's build-test command. A
human operator may disable this gate for a debugging session by restarting with
CORPFLOW_TEST_GATE=off in the process environment — an agent cannot self-serve this by retrying
the command with a prefix.

<!-- settled -->
Running a suite here gates no decision: the work it would verify is already committed or not
yet dispatched, and no verification stage has recorded an open no-go. To proceed: (1) if a
stage needs this, dispatch it and let DV (scoped) or QA (full) run it under its own authority,
(2) if a verification stage is remediating its own failure, record that stage's verdict as
"no-go" in the ledger — its authority persists until the verdict flips, so re-opening the stage
to lie about its status is never required; or (3) if you want evidence for work already merged,
say so and ask a human first. A human operator may disable this gate for a debugging session by
restarting with CORPFLOW_TEST_GATE=off in the process environment — an agent cannot self-serve
this by retrying the command with a prefix.

<!-- dedupe -->
Read the evidence token first: it says what the run being cited actually produced. `tests:<n>`
is a count read off that run's own summary line and is the strongest form; `bundle:<name>` is the
file name of a results bundle or log that existed on this machine when the run finished — search
for it by that name under your build output or results directory; `output:<n>B` means the run
returned something but no
count could be read from it, so it is weak evidence and worth re-reading before you rely on it;
`errtext:<n>B` is a failing run that printed its failures, which is still a run. Two tokens never
reach you here, because a prior carrying either no longer suppresses anything: `discovered:<n>`
(the runner enumerated n cases and executed none) and `unrecorded` (a marker predating this
grammar, whose evidence was never captured). Both are no evidence at all; if you are somehow
reading one, cite nothing and make the edit in (2). To proceed: (1) cite that run as
the evidence for this stage — it covers the same tree and the
same selection; (2) if you have since changed something, make the edit and re-run — any
modification to tracked content re-enables this command automatically, no flag required; or (3)
if you need a repeat run of an unchanged tree to investigate a flake, ask a human to restart
with CORPFLOW_TEST_DEDUPE=off in the process environment. An agent cannot self-serve that by
retrying the command with a prefix, because this hook reads process env rather than the command
string.

<!-- end -->
