#!/usr/bin/env bash
# handoff-harness-selftest.sh — the `--self-test` harness for handoff-harness.sh.
#
# SOURCED, never executed: handoff-harness.sh loads this file only on the
# `--self-test` path, so the validate paths never pay for it. Sourcing leaves
# every validator the caller has already defined in scope — this file calls
# make_fixtures, validate_frontmatter, validate_state and run_token_count, and
# is not standalone.
#
# make_fixtures deliberately STAYS in the caller: `--run`, the token-count
# measurement mode, calls it too, and moving it would make a non-self-test mode
# depend on this file.
#
# Contract: defines `self_test` and its `self_test_*` cases; `self_test` owns the
# exit for this invocation.

# ---------- Self-test ----------
self_test() {
  local td
  td=$(mktemp -d "${TMPDIR:-/tmp}/handoff-selftest-XXXXXX")
  trap "rm -rf '$td'" EXIT

  make_fixtures "$td"
  validate_frontmatter "$td/.context/planning-0.md" >/dev/null
  validate_frontmatter "$td/.context/architecture.md" >/dev/null
  validate_frontmatter "$td/.context/development.md" >/dev/null
  validate_state "$td/.context/state.json" >/dev/null

  if run_token_count "$td" >/dev/null 2>&1; then
    echo "self-test: token-count ≥30% reduction: ok"
  else
    echo "self-test: token-count: FAIL" >&2; exit 1
  fi

  self_test_ar_gate "$td"
  self_test_tests_executed "$td"
  self_test_anchors "$td"
  self_test_collect_all "$td"
  self_test_control_bytes "$td"
  self_test_blocked_on "$td"

  echo "self-test: ALL PASS"
}

# One case per blocked_on kind, plus each refusal and the legacy alias. Every case asserts the
# gate's exit code on the host's reader AND on the no-yq awk reader, because CI hosts lack yq and
# a verdict that differs between the two is the drift this gate exists to prevent.
self_test_blocked_on() {
  local ctx="$1/.context" kind detail rw out rc awk_rc

  if ! command -v jq >/dev/null 2>&1; then
    echo "self-test: blocked_on: SKIP (jq unavailable)"
    return 0
  fi

  # <path> <blocked_on block lines, indented under handoff:>
  _bo_artifact() {
    {
      echo '---'; echo 'handoff:'; echo '  stage: DV'; echo '  verdict: blocked'
      echo '  tests_executed: [{ runner: bats, count: 12, summary_line: "12 tests, 0 failures" }]'
      echo '  summary: "Blocked on a typed need."'; echo '  files_touched: [a.md]'
      echo '  next_stage_focus: "DR reviews"'; echo '  open_questions: []'
      printf '%s\n' "$2"
      echo '  refs:'; echo '    dev: development.md#files-changed'; echo '---'; echo
      echo '# Development'; echo; echo '12 tests, 0 failures'
      printf '\n## %s\n\nx\n' files-changed tests-added deviations follow-ups
      echo; echo '## elicitation-sweep'; echo; echo 'nothing to elicit'
    } > "$1"
  }

  # The verdict the no-yq reader reaches on the same artifact: 0 valid or absent, 1 refused.
  _bo_awk_verdict() {
    local fm raw norm vrc=0
    fm=$(mktemp "${TMPDIR:-/tmp}/handoff-bo-st-XXXXXX")
    corpflow_fm_block "$1" > "$fm" 2> /dev/null || true
    raw=$(awk "$_FM_BO_AWK" "$fm" 2> /dev/null) || { rm -f "$fm"; return 1; }
    rm -f "$fm"
    norm=$(blocked_on_normalize "$raw") || return 0
    blocked_on_validate "$(printf '%s' "$norm" | jq -c '.blocked_on')" 2> /dev/null || vrc=$?
    return "$vrc"
  }

  # <label> <want-rc> <want-pattern|-> <artifact>
  _bo_case() {
    rc=0; awk_rc=0
    out=$(validate_frontmatter "$4" 2>&1) || rc=$?
    _bo_awk_verdict "$4" || awk_rc=$?
    if [[ "$rc" -ne "$2" || "$awk_rc" -ne "$2" ]]; then
      echo "self-test: blocked_on $1: FAIL (rc=$rc awk_rc=$awk_rc want=$2)" >&2; exit 1
    fi
    if [[ "$3" != "-" ]] && ! printf '%s\n' "$out" | grep -qF "$3"; then
      echo "self-test: blocked_on $1: FAIL (pattern not found: $3)" >&2; exit 1
    fi
    echo "self-test: blocked_on $1: ok"
  }

  while IFS='|' read -r kind detail rw; do
    [[ -n "$kind" ]] || continue
    _bo_artifact "$ctx/dv-bo-$kind.md" "  blocked_on:
    kind: $kind
    detail: $detail
    resume_with: $rw"
    _bo_case "valid/$kind" 0 - "$ctx/dv-bo-$kind.md"
  done <<'KINDS'
user_decision|{ question: "Ship behind a flag?", options: [flag, no-flag], recommended: flag }|decision_ref
user_action|{ request: "Boot the simulator", command: "xcrun simctl boot 'iPhone 16'", verify: "xcrun simctl list devices booted" }|decision_ref
permission|{ tool: Bash, command: "gh pr merge 412 --squash", classifier_reason: "Blocked by classifier", allow_rule: "" }|decision_ref
peer_session|{ to: backend-session, question: "Which base branch?", deadline: "2026-09-20T00:00:00Z" }|reply_ref
artifact|{ producer_task: DV0, path: development-0.md }|artifact_path
correction|{ target_task: DV0, finding: "wrong exit code", evidence_ref: "a.sh:12", severity: blocking }|artifact_path
host_environment|{ check: gh-pr-create, observed: "gh auth status: not logged in" }|decision_ref
KINDS

  _bo_artifact "$ctx/dv-bo-bad-kind.md" '  blocked_on:
    kind: coffee_break
    detail: { request: "x", command: "" }
    resume_with: decision_ref'
  _bo_case "unknown-kind" 1 'fail: blocked_on.kind "coffee_break" is not one of' "$ctx/dv-bo-bad-kind.md"

  _bo_artifact "$ctx/dv-bo-bad-rw.md" '  blocked_on:
    kind: user_action
    detail: { request: "x", command: "" }
    resume_with: carrier_pigeon'
  _bo_case "unknown-resume_with" 1 'fail: blocked_on.resume_with "carrier_pigeon" is not one of' "$ctx/dv-bo-bad-rw.md"

  _bo_artifact "$ctx/dv-bo-no-detail.md" '  blocked_on:
    kind: user_action
    resume_with: decision_ref'
  _bo_case "missing-detail" 1 'fail: blocked_on.detail is missing or empty' "$ctx/dv-bo-no-detail.md"

  _bo_artifact "$ctx/dv-bo-empty-detail.md" '  blocked_on:
    kind: user_action
    detail: {}
    resume_with: decision_ref'
  _bo_case "empty-detail" 1 'fail: blocked_on.detail is missing or empty' "$ctx/dv-bo-empty-detail.md"

  _bo_artifact "$ctx/dv-bo-alias.md" '  cross_session_ask:
    to: backend-session
    question: "Which base branch?"'
  _bo_case "legacy-alias/validates" 0 - "$ctx/dv-bo-alias.md"
  rc=0
  out=$(read_blocked_on "$ctx/dv-bo-alias.md" 2>&1) || rc=$?
  if [[ "$rc" -ne 0 ]] \
     || ! printf '%s\n' "$out" | head -n 1 | jq -e '. == {kind: "peer_session", detail: {to: "backend-session", question: "Which base branch?"}, resume_with: "reply_ref"}' > /dev/null 2>&1 \
     || [[ "$(printf '%s\n' "$out" | sed -n 2p)" != "source: cross_session_ask" ]]; then  # legacy alias
    echo "self-test: blocked_on legacy-alias/reads-as-peer_session: FAIL (rc=$rc)" >&2; exit 1
  fi
  echo "self-test: blocked_on legacy-alias/reads-as-peer_session: ok"
}

# tests_executed is a per-runner list: a list passes, a scalar fails, an entry without a
# runner fails, and the legacy opt-in accepts a scalar with exactly one deprecation warn.
self_test_tests_executed() {
  local ctx="$1/.context" out rc

  if ! command -v yq > /dev/null 2>&1; then
    echo "self-test: tests-executed: SKIP (yq unavailable)"
    return 0
  fi

  # <path> <tests_executed block lines> [extra handoff lines]
  _te_artifact() {
    {
      echo '---'; echo 'handoff:'; echo '  stage: DV'; echo '  verdict: ok'
      echo '  summary: "Implemented."'
      printf '%s\n' "$2"
      [[ -z "${3:-}" ]] || printf '%s\n' "$3"
      echo '  files_touched: [a.md]'
      echo '  next_stage_focus: "DR reviews"'
      echo '  open_questions: []'
      echo '  refs:'; echo '    dev: development.md#files-changed'; echo '---'; echo
      echo '# Development'; echo; echo '1..12'; echo '3 passed in 0.4s'
      printf '\n## %s\n\nx\n' files-changed tests-added deviations follow-ups
      echo; echo '## elicitation-sweep'; echo; echo 'nothing to ask'
    } > "$1"
  }

  _te_artifact "$ctx/dv-te-list.md" '  tests_executed:
    - { runner: bats, count: 12, summary_line: "1..12" }
    - { runner: pytest, count: 3, summary_line: "3 passed in 0.4s" }'
  rc=0; out=$(validate_frontmatter "$ctx/dv-te-list.md" 2>&1) || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    echo "self-test: tests-executed list: FAIL (rc=$rc) $out" >&2; exit 1
  fi
  echo "self-test: tests-executed list: ok"

  _te_artifact "$ctx/dv-te-scalar.md" '  tests_executed: 12' '  test_summary_line: "1..12"  # legacy shape'
  rc=0; out=$(validate_frontmatter "$ctx/dv-te-scalar.md" 2>&1) || rc=$?
  if [[ "$rc" -ne 1 ]] || ! printf '%s\n' "$out" | grep -qF 'tests_executed is a scalar ("12")'; then
    echo "self-test: tests-executed scalar: FAIL (rc=$rc) $out" >&2; exit 1
  fi
  echo "self-test: tests-executed scalar: ok"

  _te_artifact "$ctx/dv-te-norunner.md" '  tests_executed:
    - { count: 12, summary_line: "1..12" }'
  rc=0; out=$(validate_frontmatter "$ctx/dv-te-norunner.md" 2>&1) || rc=$?
  if [[ "$rc" -ne 1 ]] || ! printf '%s\n' "$out" | grep -qF 'tests_executed[0] has no runner'; then
    echo "self-test: tests-executed no-runner: FAIL (rc=$rc) $out" >&2; exit 1
  fi
  echo "self-test: tests-executed no-runner: ok"

  rc=0; out=$(LEGACY_TE=1 validate_frontmatter "$ctx/dv-te-scalar.md" 2>&1) || rc=$?
  if [[ "$rc" -ne 0 ]] || [[ "$(printf '%s\n' "$out" | grep -c 'is a legacy scalar')" -ne 1 ]]; then
    echo "self-test: tests-executed legacy opt-in: FAIL (rc=$rc) $out" >&2; exit 1
  fi
  echo "self-test: tests-executed legacy opt-in: ok"
}

# Every stage's H2 set is enforced: a drifted retrospective names each defect on its own line.
self_test_anchors() {
  local ctx="$1/.context" out rc=0
  {
    printf -- '---\nhandoff:\n  stage: ST\n  verdict: ok\n  summary: "s"\n  key_decisions: []\n'
    printf '  open_questions: []\n  refs: { plan: planning-0.md#requirements }\n---\n\n'
    printf '## %s\n\nx\n\n' decision learnings elicitation-sweep Notes
  } > "$ctx/retrospective-9.md"
  out=$(validate_frontmatter "$ctx/retrospective-9.md" 2>&1) || rc=$?
  if [[ "$rc" -ne 1 ]] \
    || ! printf '%s\n' "$out" | grep -qF "fail: anchor-lint stage=ST missing required H2 '## followups' in retrospective-9.md" \
    || ! printf '%s\n' "$out" | grep -qF "fail: anchor-lint stage=ST unexpected H2 '## Notes' in retrospective-9.md"; then
    echo "self-test: anchors: FAIL (rc=$rc)" >&2; exit 1
  fi
  echo "self-test: anchors: ok"
}

# A raw NUL is a gate failure naming the path; the same text spelling the escape passes.
self_test_control_bytes() {
  local ctx="$1/.context" out rc=0

  # shellcheck disable=SC2016  # the backticks are fixture text, not a command substitution
  { cat "$ctx/planning-0.md"; printf 'escape spellings `\\0` then \000 raw\n'; } > "$ctx/planning-nul.md"
  out=$(validate_frontmatter "$ctx/planning-nul.md" 2>&1) || rc=$?
  if [[ "$rc" -ne 1 ]] || ! printf '%s\n' "$out" | grep -qF "control byte 0x00 at byte offset" \
     || ! printf '%s\n' "$out" | grep -qF "$ctx/planning-nul.md"; then
    echo "self-test: control-bytes: FAIL (raw NUL: rc=$rc)" >&2; exit 1
  fi

  # shellcheck disable=SC2016  # the backticks are fixture text, not a command substitution
  { cat "$ctx/planning-0.md"; printf '%s\n' 'escape spellings `\0` then \0 literal'; } > "$ctx/planning-literal.md"
  rc=0
  validate_frontmatter "$ctx/planning-literal.md" > /dev/null 2>&1 || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    echo "self-test: control-bytes: FAIL (literal escape text: rc=$rc)" >&2; exit 1
  fi
  echo "self-test: control-bytes: ok"
}

# The frontmatter body reports every failure per invocation, and the divergence check no
# longer harvests a digit out of a sibling artifact's filename.
self_test_collect_all() {
  local ctx="$1/.context"

  if ! command -v yq >/dev/null 2>&1; then
    echo "self-test: collect-all: SKIP (yq unavailable)"
    return 0
  fi

  {
    echo '---'; echo 'handoff:'; echo '  stage: DV'; echo '  verdict: ok'; echo '  tests_executed: [{ runner: bats, count: 12, summary_line: "12 tests, 0 failures" }]'
    echo '  summary: "Two independent violations in one artifact."'
    echo '  files_touched: [a1.sh, a2.sh, a3.sh, a4.sh, a5.sh, a6.sh, a7.sh, a8.sh, a9.sh, a10.sh, a11.sh]'
    echo '  next_stage_focus: "DR reviews"'
    echo '  open_questions:'
    echo '    - "q1: not a stub"'
    echo '  refs:'; echo '    dev: development.md#files-changed'; echo '---'; echo
    echo '# Development'; echo; echo '12 tests, 0 failures'
  } > "$ctx/dv-two-faults.md"

  local out rc=0
  out=$(validate_frontmatter "$ctx/dv-two-faults.md" 2>&1) || rc=$?
  if [[ "$rc" -ne 1 ]]; then
    echo "self-test: collect-all: FAIL (rc=$rc want=1)" >&2; exit 1
  fi
  if ! printf '%s\n' "$out" | grep -q "FILES_TOUCHED_MAX=10" \
     || ! printf '%s\n' "$out" | grep -q "is not a sweep stub"; then
    echo "self-test: collect-all: FAIL (one invocation did not report both faults)" >&2; exit 1
  fi
  echo "self-test: collect-all: ok"

  {
    echo '---'; echo 'handoff:'; echo '  stage: DV'; echo '  verdict: ok'; echo '  tests_executed: [{ runner: bats, count: 12, summary_line: "12 tests, 0 failures" }]'
    echo '  summary: "Filename digits must not be harvested."'
    echo '  files_touched: [a.md]'
    echo '  key_decisions:'
    echo '    - { id: dv-1, summary: "The retry budget for a failing stage is 3 attempts" }'
    echo '  next_stage_focus: "DR reviews"'
    echo '  open_questions: []'
    echo '  refs:'; echo '    dev: development.md#files-changed'; echo '---'; echo
    printf '## %s\n\nx\n\n' files-changed tests-added deviations follow-ups
    echo '## decisions'; echo
    echo '- **dv-1 — The retry budget for a failing stage is three attempts, per planning-0.md.**'
    echo; echo '12 tests, 0 failures'
    echo; echo '## elicitation-sweep'; echo; echo 'nothing to ask'
  } > "$ctx/dv-filename-digit.md"

  if ! validate_frontmatter "$ctx/dv-filename-digit.md" >/dev/null 2>&1; then
    echo "self-test: harvest: FAIL (a filename digit still blocks the boundary)" >&2; exit 1
  fi
  echo "self-test: harvest: ok"
}

# Exercises every branch of the AR->DV gate. Each case restores STATE_ARG/STRICT
# itself, so ordering between cases carries no state.
self_test_ar_gate() {
  local ctx="$1/.context"

  if ! command -v yq >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    echo "self-test: ar-ref gate: SKIP (yq/jq unavailable)"
    return 0
  fi

  jq 'del(.tasks.AR0)' "$ctx/state.json" > "$ctx/state-no-ar.json"

  _dv_required_h2s() { printf '\n## %s\n\nx\n' files-changed tests-added deviations follow-ups; }

  # The item the harness requires under a stub's anchor: at least two options[].
  _two_option_item() {  # <id>
    printf -- '- id: %s\n  summary: "Which way?"\n  options:\n    - { label: "A", detail: "first" }\n    - { label: "B", detail: "second" }\n' "$1"
  }

  # The shared preamble every gate fixture needs; only refs differ per case.
  # $3 replaces the default empty sweep array, so a case can plant a rejected item shape.
  # $4 replaces the body under `## elicitation-sweep`.
  _dv_artifact() {
    local path="$1" refs_block="$2" oq="${3:-  open_questions: []}" sweep_body="${4:-nothing to elicit}"
    {
      echo '---'
      echo 'handoff:'
      echo '  stage: DV'
      echo '  tests_executed: [{ runner: bats, count: 12, summary_line: "12 tests, 0 failures" }]'
      echo '  verdict: ok'
      echo '  summary: "Implemented."'
      echo '  files_touched: [a.md]'
      echo '  next_stage_focus: "DR reviews"'
      printf '%s\n' "$oq"
      echo '  refs:'
      printf '%s\n' "$refs_block"
      echo '---'
      echo
      echo '# Development'; echo; echo '12 tests, 0 failures'
      _dv_required_h2s
      echo
      echo '## elicitation-sweep'
      echo
      printf '%s\n' "$sweep_body"
    } > "$path"
  }

  _dv_artifact "$ctx/dv-no-ref.md"    '    dev: development.md#files-changed'
  _dv_artifact "$ctx/dv-dangling.md"  '    decisions: architecture-9.md#decisions'
  _dv_artifact "$ctx/dv-valid.md"     '    decisions: architecture-0.md#decisions'
  cp "$ctx/architecture.md" "$ctx/architecture-0.md"

  # <label> <state-file|-> <strict> <want-rc> <want-pattern|-> <artifact>
  _ar_case() {
    local label="$1" state="$2" strict="$3" want_rc="$4" want_pat="$5" artifact="$6"
    STATE_ARG=""; [[ "$state" != "-" ]] && STATE_ARG="$state"
    STRICT="$strict"
    local out rc=0
    out=$(validate_frontmatter "$artifact" 2>&1) || rc=$?
    # Read by validate_frontmatter in the caller (handoff-harness.sh); shellcheck
    # cannot follow across the source boundary since the harness moved out.
    # shellcheck disable=SC2034
    STATE_ARG=""
    # shellcheck disable=SC2034
    STRICT=0
    if [[ "$rc" -ne "$want_rc" ]]; then
      echo "self-test: ar-ref $label: FAIL (rc=$rc want=$want_rc)" >&2; exit 1
    fi
    if [[ "$want_pat" == "-" ]]; then
      if printf '%s' "$out" | grep -qE '^(warn|fail): (AR completed|DV architecture|DV references)'; then
        echo "self-test: ar-ref $label: FAIL (unexpected gate line)" >&2; exit 1
      fi
    elif ! printf '%s' "$out" | grep -q "$want_pat"; then
      echo "self-test: ar-ref $label: FAIL (pattern not found: $want_pat)" >&2; exit 1
    fi
    echo "self-test: ar-ref $label: ok"
  }

  _ar_case "AR+missing/default"  "$ctx/state.json"       0 0 "warn: AR completed but DV refs.decisions missing" "$ctx/dv-no-ref.md"
  _ar_case "AR+missing/strict"   "$ctx/state.json"       1 1 "fail: AR completed but DV refs.decisions missing" "$ctx/dv-no-ref.md"
  _ar_case "AR+dangling/default" "$ctx/state.json"       0 0 "warn: DV architecture ref dangling"               "$ctx/dv-dangling.md"
  _ar_case "AR+dangling/strict"  "$ctx/state.json"       1 1 "fail: DV architecture ref dangling"               "$ctx/dv-dangling.md"
  _ar_case "AR+valid/default"    "$ctx/state.json"       0 0 -                                                  "$ctx/dv-valid.md"
  _ar_case "AR+valid/strict"     "$ctx/state.json"       1 0 -                                                  "$ctx/dv-valid.md"
  _ar_case "noAR+noref/default"  "$ctx/state-no-ar.json" 0 0 -                                                  "$ctx/dv-no-ref.md"
  _ar_case "noAR+ref/default"    "$ctx/state-no-ar.json" 0 0 "warn: DV references architecture-0.md"               "$ctx/dv-valid.md"
  _ar_case "noAR+ref/strict"     "$ctx/state-no-ar.json" 1 0 "warn: DV references architecture-0.md"               "$ctx/dv-valid.md"
  _ar_case "baseline/no-state"   -                       0 0 -                                                  "$ctx/dv-no-ref.md"
  _ar_case "baseline/no-state+strict" -                    1 0 -                                                  "$ctx/dv-dangling.md"

  # F5: an unreadable --state must be loud, not silently indistinguishable from "no AR".
  printf 'not json {{' > "$ctx/state-corrupt.json"
  _ar_case "badstate/missing/default" "$ctx/nope.json"     0 0 "warn: AR-ref check skipped" "$ctx/dv-no-ref.md"
  _ar_case "badstate/missing/strict"  "$ctx/nope.json"     1 1 "fail: AR-ref check skipped" "$ctx/dv-no-ref.md"
  _ar_case "badstate/corrupt/default" "$ctx/state-corrupt.json" 0 0 "warn: AR-ref check skipped" "$ctx/dv-no-ref.md"
  _ar_case "badstate/corrupt/strict"  "$ctx/state-corrupt.json" 1 1 "fail: AR-ref check skipped" "$ctx/dv-no-ref.md"

  # Sweep ledger parity rides on the same invocation: every stub must be in the
  # ledger, and an unreadable ledger fails (never skips) when there is a stub to compare.
  {
    echo '---'; echo 'handoff:'; echo '  stage: DV'; echo '  verdict: ok'; echo '  tests_executed: [{ runner: bats, count: 12, summary_line: "12 tests, 0 failures" }]'
    echo '  summary: "Implemented."'; echo '  files_touched: [a.md]'
    echo '  next_stage_focus: "DR reviews"'
    echo '  open_questions:'
    echo '    - { id: sw-DV0-1, class: decision, ref: "dv-stub.md#elicitation-sweep", blocks_next_stage: false }'
    echo '  refs:'; echo '    dev: development.md#files-changed'; echo '---'; echo
    echo '# Development'; echo; echo '12 tests, 0 failures'; _dv_required_h2s; echo; echo '## elicitation-sweep'; echo; _two_option_item sw-DV0-1
  } > "$ctx/dv-stub.md"
  jq '.facts.open_questions += [{"id":"sw-DV0-1","class":"decision","ref":"dv-stub.md#elicitation-sweep","blocks_next_stage":false}]' \
     "$ctx/state-no-ar.json" > "$ctx/state-stub.json"
  _ar_case "sweep/stub+ledger"        "$ctx/state-stub.json"    0 0 -                                              "$ctx/dv-stub.md"
  _ar_case "sweep/stub+not-in-ledger" "$ctx/state-no-ar.json"   0 1 "fail: sweep stub sw-DV0-1 is in the frontmatter" "$ctx/dv-stub.md"
  _ar_case "sweep/stub+missing-state" "$ctx/nope.json"          0 1 "fail: sweep ledger parity cannot be verified"  "$ctx/dv-stub.md"
  _ar_case "sweep/stub+corrupt-state" "$ctx/state-corrupt.json" 0 1 "fail: sweep ledger parity cannot be verified"  "$ctx/dv-stub.md"
  _ar_case "sweep/nostub+missing-state" "$ctx/nope.json"        0 0 "warn: AR-ref check skipped"                    "$ctx/dv-no-ref.md"

  # Stub parity: id agreement is not agreement. Each ledger below carries the SAME id as
  # dv-stub.md and differs in exactly one field, so a pass here could only come from a check
  # that never looked. The agreeing case is the anti-vacuity arm — normalising an absent flag
  # to false must not manufacture a divergence out of a legacy ledger entry.
  jq '.facts.open_questions[0].blocks_next_stage = true' \
     "$ctx/state-stub.json" > "$ctx/state-stub-flag.json"
  jq '.facts.open_questions[0].class = "escalate"' \
     "$ctx/state-stub.json" > "$ctx/state-stub-class.json"
  jq 'del(.facts.open_questions[0].blocks_next_stage)' \
     "$ctx/state-stub.json" > "$ctx/state-stub-noflag.json"
  _ar_case "sweep/stub+flag-divergence"  "$ctx/state-stub-flag.json"   0 1 \
    "fail: sweep stub sw-DV0-1 disagrees across transports — blocks_next_stage is false in dv-stub.md but true" "$ctx/dv-stub.md"
  _ar_case "sweep/stub+class-divergence" "$ctx/state-stub-class.json"  0 1 \
    "fail: sweep stub sw-DV0-1 disagrees across transports — class is decision in dv-stub.md but escalate" "$ctx/dv-stub.md"
  _ar_case "sweep/stub+flag-absent-in-ledger" "$ctx/state-stub-noflag.json" 0 0 - "$ctx/dv-stub.md"

  # F4: the flag is required on the frontmatter side too, so the divergence check can never be
  # dodged by simply omitting the field the ledger disagrees with.
  _dv_artifact "$ctx/dv-noflag.md" '    dev: development.md#files-changed' \
    '  open_questions:
    - { id: sw-DV0-1, class: decision, ref: "dv-noflag.md#elicitation-sweep" }'
  _ar_case "sweep/stub+no-flag" - 0 1 "fail: sweep stub sw-DV0-1 carries no blocks_next_stage" "$ctx/dv-noflag.md"

  # The stub is the ONLY item shape: the two pre-sweep forms and a mistyped class are
  # rejected by name, so the diagnostic tells the agent what to write instead.
  _dv_artifact "$ctx/dv-legacy-string.md" '    dev: development.md#files-changed' \
    '  open_questions:
    - "q1: hook lang (AR to decide)"'
  _dv_artifact "$ctx/dv-legacy-bare.md" '    dev: development.md#files-changed' \
    '  open_questions:
    - { id: q2, summary: "bare object" }'
  _dv_artifact "$ctx/dv-bad-class.md" '    dev: development.md#files-changed' \
    '  open_questions:
    - { id: sw-DV0-9, class: advisory, ref: "dv-bad-class.md#elicitation-sweep", blocks_next_stage: false }'
  _ar_case "sweep/legacy-string" - 0 1 "fail: open_questions\[0\] is not a sweep stub" "$ctx/dv-legacy-string.md"
  _ar_case "sweep/legacy-bare"   - 0 1 'fail: open_questions\[0\] id "q2" is not sw-'   "$ctx/dv-legacy-bare.md"
  _ar_case "sweep/bad-class"     - 0 1 "fail: sweep stub sw-DV0-9 class is not decision|escalate" "$ctx/dv-bad-class.md"

  # Fail-closed: a non-string id (yq's test() throws on it) and a scalar open_questions
  # (invisible to `[]?`) must both fail by name rather than pass on the read error.
  _dv_artifact "$ctx/dv-int-id.md" '    dev: development.md#files-changed' \
    '  open_questions:
    - { id: 5, class: decision, ref: "dv-int-id.md#elicitation-sweep", blocks_next_stage: false }'
  _dv_artifact "$ctx/dv-scalar.md" '    dev: development.md#files-changed' \
    '  open_questions: "none"'
  _ar_case "sweep/int-id"  - 0 1 'fail: open_questions\[0\] id "5" is not sw-'        "$ctx/dv-int-id.md"
  _ar_case "sweep/scalar"  - 0 1 "fail: open_questions is !!str, not a sequence"     "$ctx/dv-scalar.md"

  # A ref spelled with the artifact's own directory (the templates' refs: convention) is the
  # same file: it resolves rather than failing as missing.
  _dv_artifact "$ctx/dv-ctx-ref.md" '    dev: development.md#files-changed' \
    "  open_questions:
    - { id: sw-DV0-1, class: decision, ref: \"$(basename "$ctx")/dv-ctx-ref.md#elicitation-sweep\", blocks_next_stage: false }" \
    "$(_two_option_item sw-DV0-1)"
  _ar_case "sweep/dir-prefixed-ref" - 0 0 - "$ctx/dv-ctx-ref.md"

  # The anchor resolving is not enough: the item under it must be something the FN gate can
  # put to a human. Each fixture differs only in class and in the body under the anchor.
  local dstub='  open_questions:
    - { id: sw-DV0-1, class: decision, ref: "#elicitation-sweep", blocks_next_stage: false }'
  local estub='  open_questions:
    - { id: sw-DV0-1, class: escalate, ref: "#elicitation-sweep", blocks_next_stage: false }'
  local dev='    dev: development.md#files-changed'
  _dv_artifact "$ctx/dv-item-note.md" "$dev" "$dstub" '- sw-DV0-1 — reviewed, nothing to decide'
  _dv_artifact "$ctx/dv-item-options.md" "$dev" "$dstub" "$(_two_option_item sw-DV0-1)"
  _dv_artifact "$ctx/dv-item-escalate-q.md" "$dev" "$estub" '- id: sw-DV0-1
  summary: "Ship with the token still in the log?"'
  _dv_artifact "$ctx/dv-item-escalate-note.md" "$dev" "$estub" '- sw-DV0-1 — token still in the log'
  _dv_artifact "$ctx/dv-item-decision-q.md" "$dev" "$dstub" '- id: sw-DV0-1
  summary: "Ship with the token still in the log?"
  options:
    - { label: "Ship", detail: "only one option" }'
  _dv_artifact "$ctx/dv-item-missing.md" "$dev" "$dstub" "$(_two_option_item sw-DV0-12)"
  _ar_case "sweep-item/status-note"         - 0 1 "fail: sweep stub sw-DV0-1 is a status note, not a question" "$ctx/dv-item-note.md"
  _ar_case "sweep-item/decision+2-options"  - 0 0 - "$ctx/dv-item-options.md"
  _ar_case "sweep-item/escalate+question"   - 0 0 - "$ctx/dv-item-escalate-q.md"
  _ar_case "sweep-item/escalate+no-question" - 0 1 "fail: sweep stub sw-DV0-1 is a status note, not a question" "$ctx/dv-item-escalate-note.md"
  _ar_case "sweep-item/decision+question+1-option" - 0 1 "only an escalate item may stand on a bare question" "$ctx/dv-item-decision-q.md"
  _ar_case "sweep-item/id-missing"          - 0 1 "fail: sweep stub sw-DV0-1 has no item under" "$ctx/dv-item-missing.md"
}
