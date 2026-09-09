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
# Contract: defines `self_test` and `self_test_ar_gate`; `self_test` owns the
# exit for this invocation.

# ---------- Self-test ----------
self_test() {
  local td
  td=$(mktemp -d -t handoff-selftest-XXXXXX)
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
  self_test_collect_all "$td"

  echo "self-test: ALL PASS"
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
    echo '---'; echo 'handoff:'; echo '  stage: DV'; echo '  verdict: ok'; echo '  tests_executed: 12'
    echo '  summary: "Two independent violations in one artifact."'
    echo '  files_touched: [a1.sh, a2.sh, a3.sh, a4.sh, a5.sh, a6.sh, a7.sh, a8.sh, a9.sh, a10.sh, a11.sh]'
    echo '  next_stage_focus: "DR reviews"'
    echo '  open_questions:'
    echo '    - "q1: not a stub"'
    echo '  refs:'; echo '    dev: development.md#files-changed'; echo '---'; echo
    echo '# Development'
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
    echo '---'; echo 'handoff:'; echo '  stage: DV'; echo '  verdict: ok'; echo '  tests_executed: 12'
    echo '  summary: "Filename digits must not be harvested."'
    echo '  files_touched: [a.md]'
    echo '  key_decisions:'
    echo '    - { id: dv-1, summary: "The retry budget for a failing stage is 3 attempts" }'
    echo '  next_stage_focus: "DR reviews"'
    echo '  open_questions: []'
    echo '  refs:'; echo '    dev: development.md#files-changed'; echo '---'; echo
    echo '## decisions'; echo
    echo '- **dv-1 — The retry budget for a failing stage is three attempts, per planning-0.md.**'
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

  # The shared preamble every gate fixture needs; only refs differ per case.
  # $3 replaces the default empty sweep array, so a case can plant a rejected item shape.
  _dv_artifact() {
    local path="$1" refs_block="$2" oq="${3:-  open_questions: []}"
    {
      echo '---'
      echo 'handoff:'
      echo '  stage: DV'
      echo '  tests_executed: 12'
      echo '  verdict: ok'
      echo '  summary: "Implemented."'
      echo '  files_touched: [a.md]'
      echo '  next_stage_focus: "DR reviews"'
      printf '%s\n' "$oq"
      echo '  refs:'
      printf '%s\n' "$refs_block"
      echo '---'
      echo
      echo '# Development'
      echo
      echo '## elicitation-sweep'
      echo
      echo 'nothing to elicit'
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
    echo '---'; echo 'handoff:'; echo '  stage: DV'; echo '  verdict: ok'; echo '  tests_executed: 12'
    echo '  summary: "Implemented."'; echo '  files_touched: [a.md]'
    echo '  next_stage_focus: "DR reviews"'
    echo '  open_questions:'
    echo '    - { id: sw-DV0-1, class: decision, ref: "dv-stub.md#elicitation-sweep", blocks_next_stage: false }'
    echo '  refs:'; echo '    dev: development.md#files-changed'; echo '---'; echo
    echo '# Development'; echo; echo '## elicitation-sweep'; echo; echo 'q'
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
    - { id: sw-DV0-1, class: decision, ref: \"$(basename "$ctx")/dv-ctx-ref.md#elicitation-sweep\", blocks_next_stage: false }"
  _ar_case "sweep/dir-prefixed-ref" - 0 0 - "$ctx/dv-ctx-ref.md"
}
