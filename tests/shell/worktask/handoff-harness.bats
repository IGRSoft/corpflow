#!/usr/bin/env bats
# Contract tests for skills/worktask/scripts/handoff-harness.sh.
# Contracts (from header):
#   - default run (--out DIR): generates synthetic artifacts, computes token reduction,
#     reports >=30% on all stages (AC-12), "PASS: all stages"; exit 0
#   - --validate-frontmatter <file>: valid frontmatter => "ok: ... stage=X tokens=N", exit 0
#   - --validate-frontmatter <file>: missing frontmatter => "fail: missing", exit 1
#   - --validate-state <state.json>: valid state => "ok: ... idempotent=yes", exit 0
#   - --validate-state <bad>: invalid JSON => "fail: state.json invalid JSON", exit 1
#   - --self-test => "ALL PASS", exit 0
#   - unknown arg => usage exit 2
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/worktask/scripts/handoff-harness.sh"

setup() {
  WD="$(mk_tmpworkdir)"
  # Use our shared DV fixture which has valid frontmatter + DV anchors.
  cp "$FIXTURES/worktask/development-0.sample.md" "$WD/development-0.md"
  cp "$FIXTURES/worktask/state.sample.json" "$WD/state.json"
  # A file with NO frontmatter (to trigger the "fail: missing" path).
  printf '# plain markdown\nno frontmatter here\n' > "$WD/plain.md"
  # Corrupt JSON for --validate-state failure test.
  printf 'not json {{' > "$WD/corrupt.json"
}

@test "happy: default run (--out DIR) reports token reduction >=30% on all stages" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --out "$WD/out"
  assert_success
  assert_output --partial "PASS: all stages"

  # Re-derive the claim from the table's own numbers rather than asserting that
  # a "%" appeared somewhere: the previous spot-check was satisfied by the
  # header row alone and could not fail while "PASS: all stages" was asserted.
  local rows=0 line stage baseline new pct want
  while IFS= read -r line; do
    case "$line" in
      *"|"*"|"*"|"*) ;;
      *) continue ;;
    esac
    stage="$(printf '%s' "$line" | awk -F'|' '{gsub(/ /,"",$1); print $1}')"
    case "$stage" in stage|*-*|'') continue ;; esac
    baseline="$(printf '%s' "$line" | awk -F'|' '{gsub(/ /,"",$2); print $2}')"
    new="$(printf '%s' "$line" | awk -F'|' '{gsub(/ /,"",$3); print $3}')"
    pct="$(printf '%s' "$line" | awk -F'|' '{gsub(/[ %]/,"",$4); print $4}')"
    rows=$((rows + 1))
    [ "$baseline" -gt 0 ]
    # AC-12: the anchored prompt must be at most 70% of the inlined baseline.
    [ $((new * 100)) -le $((baseline * 70)) ] \
      || fail "stage=$stage new=$new is more than 70% of baseline=$baseline"
    # The printed percentage must be the one those two numbers imply.
    want="$(awk -v l="$baseline" -v n="$new" 'BEGIN { printf "%.0f", (l-n)*100.0/l }')"
    [ "$pct" = "$want" ] \
      || fail "stage=$stage printed reduction ${pct}% but numbers imply ${want}%"
  done <<< "$output"
  [ "$rows" -ge 5 ] || fail "expected a row per stage, parsed $rows"

  # Independent corroboration in bytes: the generated artifacts are what the
  # baseline inlines, so the winning prompt must be far smaller than they are.
  local artifact_bytes new_bytes
  artifact_bytes="$(cat "$WD/out/.context/"*.md "$WD/out/.context/state.json" | wc -c | tr -d ' ')"
  [ "$artifact_bytes" -gt 0 ]
  new_bytes="$(wc -c < "$WD/out/.context/state.json" | tr -d ' ')"
  [ $((new_bytes * 100)) -le $((artifact_bytes * 70)) ]
}

@test "happy: --validate-frontmatter on a valid DV artifact passes (exit 0)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/development-0.md"
  assert_success
  assert_output --partial "ok:"
  assert_output --partial "stage=DV"
  assert_output --partial "tokens="
}

@test "happy: --validate-frontmatter accepts the optional acted_on_msg_id (exit 0)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$FIXTURES/worktask/ack/development-acted-m2.md"
  assert_success
  assert_output --partial "ok:"
  assert_output --partial "stage=DV"
}

@test "edge: --validate-state on a valid state.json passes (exit 0, idempotent=yes)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-state "$WD/state.json"
  assert_success
  assert_output --partial "ok:"
  assert_output --partial "idempotent=yes"
}

@test "failure: --validate-frontmatter on a no-frontmatter file fails (exit 1)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/plain.md"
  assert_failure 1
  assert_output --partial "fail:"
  assert_output --partial "missing frontmatter"
}

# Counts the extractor's leftovers in the directory `mktemp -t` actually uses.
# BSD mktemp's -t ignores TMPDIR, so the count has to be taken where the file
# really lands rather than in a redirected fixture directory — a redirected one
# stays empty whether or not the cleanup works, which is a vacuous assertion.
_fm_temp_count() {
  ls "${TMPDIR:-/tmp}"/handoff-fm-* 2>/dev/null | wc -l | tr -d ' '
}

@test "cleanup: no frontmatter temp file survives, on the pass or the fail path" {
  # Fourteen exits used to carry their own `rm -f`; one RETURN trap now does it,
  # so this checks the property rather than the arms.
  local before
  before="$(_fm_temp_count)"

  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/development-0.md"
  assert_success
  [ "$(_fm_temp_count)" = "$before" ] || fail "pass path leaked a handoff-fm temp file"

  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/plain.md"
  assert_failure 1
  [ "$(_fm_temp_count)" = "$before" ] || fail "fail path leaked a handoff-fm temp file"
}

@test "failure: --validate-state on corrupt JSON fails (exit 1)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-state "$WD/corrupt.json"
  assert_failure 1
  assert_output --partial "fail:"
  assert_output --partial "invalid JSON"
}

@test "failure: unknown argument exits 2 (usage)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --bogus
  assert_failure 2
}

# A DV artifact with the given tests_executed / test_suite_compiles pair, and
# nothing else that could fail — so a failure here is this arm and no other.
_dv_test_evidence_artifact() {  # <path> <tests_executed> [test_suite_compiles]
  local _compiles="${3:-}"
  {
    printf -- '---\n'
    printf 'handoff:\n'
    printf '  stage: DV\n'
    printf '  verdict: ok\n'
    printf '  summary: "test evidence fixture"\n'
    printf '  tests_executed: %s\n' "$2"
    printf '  test_summary_line: "%s tests, 0 failures"\n' "$2"
    if [ -n "$_compiles" ]; then printf '  test_suite_compiles: %s\n' "$_compiles"; fi
    printf '  files_touched: [a.md]\n'
    printf '  next_stage_focus: "DR reviews"\n'
    printf '  open_questions: []\n'
    printf '  refs:\n'
    printf '    dev: development-0.md#files-changed\n'
    printf -- '---\n\n# Development\n\n## verification-command\n\n%s tests, 0 failures\n\n## elicitation-sweep\n\nnothing to ask\n' "$2"
  } > "$1"
}

@test "test-evidence: tests_executed: 0 with no test_suite_compiles fails (F-02)" {
  # The ambiguity the field exists to remove: a stage denied a run and a stage
  # whose suite never compiled both reported nothing, and the two were
  # indistinguishable to every reader downstream for ten hours of one run.
  local a="$WD/te-0.md"
  _dv_test_evidence_artifact "$a" 0
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$a"
  assert_failure
  [[ "$output" == *"tests_executed: 0 with no test_suite_compiles"* ]] || fail "$output"
}

@test "test-evidence: all three legal values clear a zero count" {
  # `unknown` included, deliberately: a stage that genuinely cannot tell must be
  # able to say so rather than pick one and be wrong.
  local a="$WD/te-1.md" v
  for v in true false unknown; do
    _dv_test_evidence_artifact "$a" 0 "$v"
    run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$a"
    assert_success
  done
}

@test "test-evidence: a non-zero count needs no test_suite_compiles" {
  local a="$WD/te-2.md"
  _dv_test_evidence_artifact "$a" 12
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$a"
  assert_success
}

@test "test-evidence: a value outside the enum is refused, not accepted as truthy" {
  # `yes` reads as an answer and carries none of the three meanings.
  local a="$WD/te-3.md"
  _dv_test_evidence_artifact "$a" 0 yes
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$a"
  assert_failure
  [[ "$output" == *"expected true, false or unknown"* ]] || fail "$output"
}

# --- AD-4: a non-zero count is checked against the runner's own words ---------

# mk_te <path> <stage> <count> <summary-line-yaml> <body-line>
# `-` in either slot omits it, so one generator covers absent, malformed and
# corroborated without a second fixture shape to drift.
mk_te() {
  {
    echo '---'
    echo 'handoff:'
    echo "  stage: $2"
    echo '  verdict: ok'
    echo '  summary: "ad4 fixture"'
    echo "  tests_executed: $3"
    [ "$4" = "-" ] || echo "  test_summary_line: $4"
    echo '  files_touched: [a.sh]'
    echo '  key_decisions: []'
    echo '  next_stage_focus: "next stage"'
    echo '  open_questions: []'
    echo '  refs: { dev: development.md#files-changed }'
    echo '---'
    echo
    echo '# Artifact'
    echo
    echo '## verification-command'
    echo
    [ "$5" = "-" ] || echo "$5"
    echo
    echo '## elicitation-sweep'
    echo
    echo 'nothing to ask'
  } > "$1"
}

@test "ad4: a non-zero count with no test_summary_line fails (R2d)" {
  # The hole in one line: the old arm returned early unless the count was zero,
  # so `tests_executed: 4000` validated clean for a stage that ran nothing.
  mk_te "$WD/ad4-absent.md" DV 4000 - -
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/ad4-absent.md"
  assert_failure
  [[ "$output" == *"tests_executed: 4000 with no test_summary_line"* ]] || fail "$output"
}

@test "ad4: an empty or digitless summary line fails with its own message" {
  local v
  for v in '"   "' '"all green"'; do
    mk_te "$WD/ad4-malformed.md" DV 12 "$v" -
    run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/ad4-malformed.md"
    assert_failure
    [[ "$output" == *"carries no digit"* ]] || fail "$v: $output"
  done
}

@test "ad4: a summary line corroborated nowhere fails — an excerpt must be checkable" {
  mk_te "$WD/ad4-uncorr.md" DV 12 '"12 tests, 0 failures"' -
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/ad4-uncorr.md"
  assert_failure
  [[ "$output" == *"uncorroborated"* ]] || fail "$output"
}

@test "ad4: the body quoting the line passes, and so does a named log capture" {
  mk_te "$WD/ad4-body.md" DV 12 '"12 tests, 0 failures"' '12 tests, 0 failures'
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/ad4-body.md"
  assert_success

  # The second legal home: a runner whose tally reaches only a terminal is
  # captured to .context/logs/ and the artifact names the capture, glob included.
  mkdir -p "$WD/logs"
  printf 'run 1\n12 tests, 0 failures\n' > "$WD/logs/dv-bats-1.log"
  mk_te "$WD/ad4-log.md" DV 12 '"12 tests, 0 failures"' 'capture: .context/logs/dv-bats-*.log'
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/ad4-log.md"
  assert_success
}

@test "ad4: a count the line does not name warns, it does not block (sw-AR0-2)" {
  # Warn-only because `verbatim` is not mechanically decidable: a TAP plan line
  # is the whole summary a scoped bats run prints, and blocking on the token
  # would fail a stage that satisfies the contract. Same posture as ar_ref.
  mk_te "$WD/ad4-tap.md" DV 1814 '"1..840"' '1..840'
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/ad4-tap.md"
  assert_success
  [[ "$output" == *"warn:"* && "$output" == *"is not a whole-number token"* ]] || fail "$output"
  [[ "$output" != *"fail:"* ]] || fail "the soft tier blocked: $output"
}

@test "ad4: QA carries the count and the line too (R2e)" {
  # QA is the sole holder of full-suite authority and reported no count at all,
  # so the arm that checks counts could never reach the one stage that has one.
  mk_te "$WD/ad4-qa.md" QA 840 '"1..840"' '1..840'
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/ad4-qa.md"
  assert_success

  mk_te "$WD/ad4-qa-absent.md" QA 840 - -
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/ad4-qa-absent.md"
  assert_failure
  [[ "$output" == *"stage=QA"* ]] || fail "$output"
}

@test "ad4: a QA artifact with no tests_executed at all fails the required set (R2e)" {
  {
    echo '---'
    echo 'handoff:'
    echo '  stage: QA'
    echo '  verdict: go'
    echo '  summary: "no count"'
    echo '  files_touched: [a.sh]'
    echo '  key_decisions: []'
    echo '  open_questions: []'
    echo '  refs: { qa: testing.md#results }'
    echo '---'
    echo
    echo '# QA'
  } > "$WD/ad4-qa-nofield.md"
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/ad4-qa-nofield.md"
  assert_failure
  [[ "$output" == *"missing required field: tests_executed"* ]] || fail "$output"
}

@test "ad4: a present non-numeric tests_executed is refused, not delegated (sw-DR0-3)" {
  # The required-field loop tests non-emptiness only, so a count carrying units or
  # a parenthetical used to satisfy it and then skip every tier of the evidence
  # contract below it.
  local stage
  for stage in DV QA; do
    mk_te "$WD/ad4-nonnum-$stage.md" "$stage" '"1841 (scoped)"' '"1..1841"' '1..1841'
    run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/ad4-nonnum-$stage.md"
    assert_failure
    [[ "$output" == *"stage=$stage tests_executed is"* ]] || fail "$stage: $output"
  done
}

@test "ad4: a zero count is untouched — test_suite_compiles still owns it" {
  mk_te "$WD/ad4-zero.md" DV 0 - -
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/ad4-zero.md"
  assert_failure
  [[ "$output" == *"no test_suite_compiles"* ]] || fail "$output"
  [[ "$output" != *"test_summary_line"* ]] || fail "the zero path asked for a summary line: $output"
}

@test "contract: --self-test passes (smoke, NON-counting)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --self-test
  assert_success
  assert_output --partial "ALL PASS"
}

# --- the sweep stub's ref must be anchor-shaped, not merely present ----------

# The item under the anchor for the first id in <stub-yaml>: two options, so only what a
# test plants decides the verdict.
sweep_item_for() {  # <stub-yaml>
  local id
  id="$(printf '%s\n' "$1" | sed -n 's/.*id: *\(sw-[A-Z][A-Z][0-9]*-[0-9]*\).*/\1/p' | head -1)"
  [ -n "$id" ] || { printf 'body\n'; return 0; }
  printf -- '- id: %s\n  summary: "Which way?"\n  options:\n' "$id"
  printf -- '    - { label: "A", detail: "first" }\n    - { label: "B", detail: "second" }\n'
}

# A DV artifact whose only variable is the one sweep stub.
sweep_artifact() {  # <path> <stub-yaml>
  {
    printf -- '---\n'
    printf 'handoff:\n'
    printf '  stage: DV\n'
    printf '  tests_executed: 12\n'
    printf '  test_summary_line: "12 tests, 0 failures"\n'
    printf '  verdict: ok\n'
    printf '  summary: "sweep fixture"\n'
    printf '  files_touched: [a.md]\n'
    printf '  next_stage_focus: "DR reviews"\n'
    printf '  open_questions:\n'
    printf '    - %s\n' "$2"
    printf '  refs:\n'
    printf '    dev: development.md#files-changed\n'
    printf -- '---\n\n# Development\n\n12 tests, 0 failures\n\n## elicitation-sweep\n\n'
    sweep_item_for "$2"
  } > "$1"
}

# sweep_artifact with the body under the anchor replaced by <sweep-body>.
item_artifact() {  # <path> <stub-yaml> <sweep-body>
  sweep_artifact "$1" "$2"
  sed '/^## elicitation-sweep$/q' "$1" > "$1.tmp"
  printf '\n%s\n' "$3" >> "$1.tmp"
  mv "$1.tmp" "$1"
}

@test "sweep: an empty ref fails the shape gate" {
  sweep_artifact "$WD/dv-empty-ref.md" '{ id: sw-DV0-1, class: decision, ref: "", blocks_next_stage: false }'
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv-empty-ref.md"
  assert_failure 1
  assert_output --partial "sw-DV0-1 carries no ref anchor"
}

@test "sweep: a ref naming no anchor fails the shape gate" {
  sweep_artifact "$WD/dv-no-anchor.md" '{ id: sw-DV0-1, class: decision, ref: "planning-0.md", blocks_next_stage: false }'
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv-no-anchor.md"
  assert_failure 1
  assert_output --partial "sw-DV0-1 carries no ref anchor"
}

@test "sweep: an uppercase anchor fails — anchors are lowercase-kebab" {
  sweep_artifact "$WD/dv-caps.md" '{ id: sw-DV0-1, class: decision, ref: "planning-0.md#Elicitation_Sweep", blocks_next_stage: false }'
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv-caps.md"
  assert_failure 1
  assert_output --partial "sw-DV0-1 carries no ref anchor"
}

@test "sweep: an anchor-only ref resolves to the emitting artifact and passes" {
  sweep_artifact "$WD/dv-anchor-only.md" '{ id: sw-DV0-1, class: decision, ref: "#elicitation-sweep", blocks_next_stage: false }'
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv-anchor-only.md"
  assert_success
}

@test "sweep: the class vocabulary is the library's, not a re-spelling" {
  sweep_artifact "$WD/dv-class.md" '{ id: sw-DV0-1, class: question, ref: "#elicitation-sweep", blocks_next_stage: false }'
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv-class.md"
  assert_failure 1
  assert_output --partial "class is not decision|escalate"
}

@test "sweep: a stub omitting blocks_next_stage fails the shape gate" {
  # The field is required, not optional-with-a-default: an absent flag is indistinguishable
  # from an explicit false, and that ambiguity is what let the two transports disagree.
  sweep_artifact "$WD/dv-noflag.md" '{ id: sw-DV0-1, class: decision, ref: "#elicitation-sweep" }'
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv-noflag.md"
  assert_failure 1
  assert_output --partial "sw-DV0-1 carries no blocks_next_stage"
}

# --- the item under the anchor must be a question, not a status note ----------

DSTUB='{ id: sw-DV0-1, class: decision, ref: "#elicitation-sweep", blocks_next_stage: false }'
ESTUB='{ id: sw-DV0-1, class: escalate, ref: "#elicitation-sweep", blocks_next_stage: false }'

@test "sweep item: a bare status note under the anchor fails, naming the stub id" {
  item_artifact "$WD/dv-note.md" "$DSTUB" '- sw-DV0-1 — reviewed, nothing to decide'
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv-note.md"
  assert_failure 1
  assert_output --partial "fail: sweep stub sw-DV0-1 is a status note, not a question"
}

@test "sweep item: a decision item with two options passes" {
  item_artifact "$WD/dv-two.md" "$DSTUB" "$(sweep_item_for "$DSTUB")"
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv-two.md"
  assert_success
}

@test "sweep item: an escalate item standing on an explicit question passes" {
  item_artifact "$WD/dv-esc.md" "$ESTUB" '- id: sw-DV0-1
  summary: "Ship with the token still in the log?"'
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv-esc.md"
  assert_success
}

@test "sweep item: a question mark does not rescue a decision item with one option" {
  item_artifact "$WD/dv-decq.md" "$DSTUB" '- id: sw-DV0-1
  summary: "Ship with the token still in the log?"
  options:
    - { label: "Ship", detail: "the only option" }'
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv-decq.md"
  assert_failure 1
  assert_output --partial "only an escalate item may stand on a bare question"
}

@test "sweep item: an id absent from the anchor section fails, and sw-DV0-12 does not stand in for sw-DV0-1" {
  item_artifact "$WD/dv-missing.md" "$DSTUB" "$(sweep_item_for 'id: sw-DV0-12')"
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv-missing.md"
  assert_failure 1
  assert_output --partial "fail: sweep stub sw-DV0-1 has no item under '## elicitation-sweep'"
}

@test "sweep item: options after the next ## heading do not belong to the item" {
  item_artifact "$WD/dv-cut.md" "$DSTUB" '- id: sw-DV0-1
  summary: "Which way?"

## follow-ups

  options:
    - { label: "A", detail: "first" }
    - { label: "B", detail: "second" }'
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv-cut.md"
  assert_failure 1
  assert_output --partial "sw-DV0-1 is a status note"
}

@test "sweep item: every note is reported on its own fail line" {
  item_artifact "$WD/dv-two-notes.md" "$DSTUB
    - { id: sw-DV0-2, class: escalate, ref: \"#elicitation-sweep\", blocks_next_stage: false }" \
    '- sw-DV0-1 — done
- sw-DV0-2 — also done'
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv-two-notes.md"
  assert_failure 1
  [ "$(printf '%s\n' "$output" | grep -c 'is a status note, not a question')" -eq 2 ] || fail "$output"
}

@test "sweep item: a mention of another sweep id inside the item does not end its block" {
  # Only a line that starts another item ends the block; a cross-reference in the summary
  # must not strand the options below it.
  item_artifact "$WD/dv-xref.md" "$DSTUB" '- id: sw-DV0-1
  summary: "Follow-up to sw-DV0-2: which way?"
  options:
    - { label: "A", detail: "first" }
    - { label: "B", detail: "second" }
- id: sw-DV0-2
  summary: "Unrelated"'
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv-xref.md"
  assert_success
}

# --- stub parity: id agreement is not agreement -------------------------------
#
# The frontmatter stub and facts.open_questions[] have two writers and no derivation
# between them. Until these cases existed the only cross-check was on id, so an item whose
# ledger copy said `blocks_next_stage: true` beside an artifact saying `false` validated
# clean and the orchestrator held a boundary gate its own author had waived.

parity_state() {  # <path> <class> <blocks|omit>
  local flag="{}"
  [ "$3" = "omit" ] || flag="{\"blocks_next_stage\": $3}"
  jq -n --arg cls "$2" --argjson flag "$flag" \
    '{version: 2, worktask_id: "t", plan_file: ".context/planning-0.md", platform: "all",
      run_index: 0, tasks: {DV0: {status: "in_progress"}},
      facts: {files_modified: [], tests_added: [], decisions: [],
              open_questions: [({id: "sw-DV0-1", class: $cls, ref: "#elicitation-sweep"} + $flag)]},
      handoffs: {}}' > "$1"
}

@test "parity: a blocks_next_stage divergence fails and names both transports" {
  sweep_artifact "$WD/dv-parity-flag.md" '{ id: sw-DV0-1, class: decision, ref: "#elicitation-sweep", blocks_next_stage: false }'
  parity_state "$WD/state-parity-flag.json" decision true
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv-parity-flag.md" --state "$WD/state-parity-flag.json"
  assert_failure 1
  assert_output --partial "blocks_next_stage is false in dv-parity-flag.md but true in facts.open_questions[]"
}

@test "parity: a class divergence fails too — the check is not flag-only" {
  sweep_artifact "$WD/dv-parity-class.md" '{ id: sw-DV0-1, class: decision, ref: "#elicitation-sweep", blocks_next_stage: false }'
  parity_state "$WD/state-parity-class.json" escalate false
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv-parity-class.md" --state "$WD/state-parity-class.json"
  assert_failure 1
  assert_output --partial "class is decision in dv-parity-class.md but escalate in facts.open_questions[]"
}

@test "parity: agreeing transports pass — and an absent ledger flag normalises to false" {
  # Anti-vacuity for the two cases above: the check must fire on divergence and ONLY on
  # divergence, or a legacy ledger row written before the field was required reads as a defect.
  sweep_artifact "$WD/dv-parity-ok.md" '{ id: sw-DV0-1, class: decision, ref: "#elicitation-sweep", blocks_next_stage: false }'
  parity_state "$WD/state-parity-ok.json" decision omit
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv-parity-ok.md" --state "$WD/state-parity-ok.json"
  assert_success
}

@test "parity: the harness refuses, it never reconciles — state.json is untouched" {
  sweep_artifact "$WD/dv-parity-ro.md" '{ id: sw-DV0-1, class: decision, ref: "#elicitation-sweep", blocks_next_stage: false }'
  parity_state "$WD/state-parity-ro.json" decision true
  cp "$WD/state-parity-ro.json" "$WD/state-parity-ro.snap"
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv-parity-ro.md" --state "$WD/state-parity-ro.json"
  assert_failure 1
  run diff -q "$WD/state-parity-ro.json" "$WD/state-parity-ro.snap"
  assert_success
}

@test "sweep: a ledger whose facts.open_questions is a string fails, never silently passes" {
  # jq aborts on a scalar there, and an aborted parity read is not evidence of parity:
  # the shapes that break the read are exactly the ones the gate exists to reject.
  sweep_artifact "$WD/dv-scalar-ledger.md" '{ id: sw-DV0-1, class: decision, ref: "#elicitation-sweep", blocks_next_stage: false }'
  printf '{"facts":{"open_questions":"none"}}\n' > "$WD/state-scalar.json"
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv-scalar-ledger.md" --state "$WD/state-scalar.json"
  assert_failure 1
  assert_output --partial "could not be read as an array of stubs"
}

# ---------------------------------------------------------------------------
# AR→DV architecture-reference gate (--state / --strict, 3.42.0).
# Ships warn-only: violations are `warn:` + exit 0 unless --strict is passed.
# The cases above this block are the AC-6 baseline pin — they must keep passing
# unmodified, since a bare --validate-frontmatter never runs this gate.
# ---------------------------------------------------------------------------

# Writes a DV artifact whose only variable is the refs block.
dv_artifact() {
  local path="$1" refs="$2"
  {
    printf -- '---\n'
    printf 'handoff:\n'
    printf '  stage: DV\n'
    printf '  tests_executed: 12\n'
    printf '  test_summary_line: "12 tests, 0 failures"\n'
    printf '  verdict: ok\n'
    printf '  summary: "gate fixture"\n'
    printf '  files_touched: [a.md]\n'
    printf '  next_stage_focus: "DR reviews"\n'
    printf '  open_questions: []\n'
    printf '  refs:\n'
    printf '    %s\n' "$refs"
    printf -- '---\n\n# Development\n\n12 tests, 0 failures\n\n## elicitation-sweep\n\nnothing to ask\n'
  } > "$path"
}

# state.sample.json has PL only; the gate keys off tasks.AR0 presence.
state_with_ar() {
  jq '.tasks.AR0 = {"status":"completed","verdict":"ok"}' "$WD/state.json" > "$WD/state-ar.json"
}

@test "ar-gate: AR in state + missing ref => warn, exit 0 (default warn-only rollout)" {
  state_with_ar
  dv_artifact "$WD/dv.md" 'dev: development.md#files-changed'
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv.md" --state "$WD/state-ar.json"
  assert_success
  assert_output --partial "warn: AR completed but DV refs.decisions missing"
  refute_output --partial "fail:"
}

@test "ar-gate: AR in state + missing ref + --strict => fail, exit 1" {
  state_with_ar
  dv_artifact "$WD/dv.md" 'dev: development.md#files-changed'
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv.md" --state "$WD/state-ar.json" --strict
  assert_failure 1
  assert_output --partial "fail: AR completed but DV refs.decisions missing"
}

@test "ar-gate: AR in state + dangling ref => warn exit 0; --strict => fail exit 1" {
  state_with_ar
  dv_artifact "$WD/dv.md" 'decisions: architecture-9.md#decisions'
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv.md" --state "$WD/state-ar.json"
  assert_success
  assert_output --partial "warn: DV architecture ref dangling"

  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv.md" --state "$WD/state-ar.json" --strict
  assert_failure 1
  assert_output --partial "fail: DV architecture ref dangling"
}

@test "ar-gate: AR in state + valid ref whose file exists => silent, exit 0 in both modes" {
  state_with_ar
  dv_artifact "$WD/dv.md" 'decisions: architecture-0.md#decisions'
  printf -- '---\nhandoff:\n  stage: AR\n---\n\n# Architecture\n\n## decisions\n' > "$WD/architecture-0.md"

  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv.md" --state "$WD/state-ar.json"
  assert_success
  refute_output --partial "AR completed but"
  refute_output --partial "architecture ref dangling"

  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv.md" --state "$WD/state-ar.json" --strict
  assert_success
  refute_output --partial "fail:"
}

@test "ar-gate: no AR in state + no ref => silent, exit 0" {
  dv_artifact "$WD/dv.md" 'dev: development.md#files-changed'
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv.md" --state "$WD/state.json"
  assert_success
  refute_output --partial "AR completed but"
  refute_output --partial "but state has no tasks.AR0"
}

@test "ar-gate: inverse guard — no AR in state + architecture ref => warn, exit 0 in BOTH modes" {
  # `AR<N>` is literal in the warning: the gate matches any AR[0-9]+, so when none exists
  # there is no index to name. Pinning AR0 would contradict the any-instance rule.
  dv_artifact "$WD/dv.md" 'decisions: architecture-0.md#decisions'
  printf -- '---\nhandoff:\n  stage: AR\n---\n\n# Architecture\n' > "$WD/architecture-0.md"

  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv.md" --state "$WD/state.json"
  assert_success
  assert_output --partial "warn: DV references architecture-0.md#decisions but state has no tasks.AR<N> entry"

  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv.md" --state "$WD/state.json" --strict
  assert_success
  assert_output --partial "warn: DV references architecture-0.md#decisions but state has no tasks.AR<N> entry"
  refute_output --partial "fail:"
}

@test "ar-gate: AC-6 baseline pin — no --state means the gate never runs" {
  # Same artifact that warns under --state with AR present: silent without it.
  dv_artifact "$WD/dv.md" 'dev: development.md#files-changed'
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv.md"
  assert_success
  assert_output --partial "ok:"
  refute_output --partial "AR completed but"

  # --strict alone is inert without a state file.
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv.md" --strict
  assert_success
  refute_output --partial "fail:"
}

# ---------------------------------------------------------------------------
# Sweep-ledger parity across the open_questions spill (AD-4).
# The newest-12 clamp evicts unresolved items to
# `open-questions-<run_index>.jsonl`; parity reads ledger UNION spill, so an item
# that reached the FN gate through the spill is not reported as dropped.
# ---------------------------------------------------------------------------

# A ledger carrying run_index and an explicit open_questions array.
spill_state() {  # <path> <run_index> <ids-json>
  jq -n --argjson r "$2" --argjson ids "$3" \
    '{version: 2, worktask_id: "t", plan_file: ".context/planning-0.md",
      platform: "all", run_index: $r,
      tasks: {DV0: {status: "in_progress"}},
      facts: {files_modified: [], tests_added: [], decisions: [],
              open_questions: [$ids[] | {id: ., class: "decision",
                                         ref: "#elicitation-sweep"}]},
      handoffs: {}}' > "$1"
}

@test "spill: an item present only in the spill file satisfies ledger parity" {
  sweep_artifact "$WD/dv-spill.md" '{ id: sw-DV0-1, class: decision, ref: "#elicitation-sweep", blocks_next_stage: false }'
  spill_state "$WD/state-spill.json" 4 '[]'
  printf '%s\n' '{"id":"sw-DV0-1","class":"decision","ref":"#elicitation-sweep","stage":"DV","status":"open","spilled_at":"2026-01-01T00:00:00Z","spilled_from_stage":"DV"}' \
    > "$WD/open-questions-4.jsonl"
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv-spill.md" --state "$WD/state-spill.json"
  assert_success
}

@test "spill: the same item with NO spill file still fails — parity is not weakened" {
  sweep_artifact "$WD/dv-nospill.md" '{ id: sw-DV0-1, class: decision, ref: "#elicitation-sweep", blocks_next_stage: false }'
  spill_state "$WD/state-nospill.json" 4 '[]'
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv-nospill.md" --state "$WD/state-nospill.json"
  assert_failure 1
  assert_output --partial "not in facts.open_questions[]"
}

@test "spill: a malformed spill file fails rather than reading as the empty set" {
  # Treating a corrupt overflow file as "no items" would restore the exact loss the
  # parity check exists to catch, and only in the runs that actually overflowed.
  sweep_artifact "$WD/dv-badspill.md" '{ id: sw-DV0-1, class: decision, ref: "#elicitation-sweep", blocks_next_stage: false }'
  spill_state "$WD/state-badspill.json" 4 '["sw-DV0-1"]'
  printf 'not json at all\n' > "$WD/open-questions-4.jsonl"
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv-badspill.md" --state "$WD/state-badspill.json"
  assert_failure 1
  assert_output --partial "not readable as JSON lines"
}

@test "spill: the path derives from the ledger's run_index, never a guess" {
  sweep_artifact "$WD/dv-idx.md" '{ id: sw-DV0-1, class: decision, ref: "#elicitation-sweep", blocks_next_stage: false }'
  spill_state "$WD/state-idx.json" 7 '[]'
  printf '%s\n' '{"id":"sw-DV0-1"}' > "$WD/open-questions-4.jsonl"
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv-idx.md" --state "$WD/state-idx.json"
  assert_failure 1
  mv "$WD/open-questions-4.jsonl" "$WD/open-questions-7.jsonl"
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv-idx.md" --state "$WD/state-idx.json"
  assert_success
}

# ---------------------------------------------------------------------------
# Frontmatter token budget (AD-2): discretionary = total - min(stub block, 64),
# fail > 200, advisory warn > 264. Sweep stubs are mandatory and fixed-shape, so
# excluding them stops the budget from penalising a stage for asking questions.
# ---------------------------------------------------------------------------

# A DV artifact padded to an approximate total token count, with <stubs> sweep stubs.
budget_artifact() {  # <path> <filler-words> <stubs>
  local path="$1" fill="$2" stubs="$3" i pad=""
  for ((i = 0; i < fill; i++)); do pad="$pad w"; done
  {
    printf -- '---\n'
    printf 'handoff:\n'
    printf '  stage: DV\n'
    printf '  tests_executed: 12\n'
    printf '  test_summary_line: "12 tests, 0 failures"\n'
    printf '  verdict: ok\n'
    printf '  summary: "budget fixture%s"\n' "$pad"
    printf '  files_touched: [a.md]\n'
    printf '  next_stage_focus: "DR reviews"\n'
    printf '  open_questions:\n'
    for ((i = 1; i <= stubs; i++)); do
      printf '    - { id: sw-DV0-%s, class: decision, ref: "#elicitation-sweep", blocks_next_stage: false }\n' "$i"
    done
    printf '  refs:\n'
    printf '    dev: development.md#files-changed\n'
    printf -- '---\n\n# Development\n\n12 tests, 0 failures\n\n## elicitation-sweep\n\n'
    for ((i = 1; i <= stubs; i++)); do
      sweep_item_for "id: sw-DV0-$i"
    done
  } > "$path"
}

@test "budget: a frontmatter over 200 discretionary tokens now FAILS, not warns" {
  budget_artifact "$WD/dv-fat.md" 200 1
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv-fat.md"
  assert_failure 1
  assert_output --partial "discretionary tokens > 200 budget"
}

@test "budget: the four permitted sweep stubs cannot push a compliant artifact over" {
  # Same prose in both files; the only difference is the mandatory stub block. If the
  # stubs were counted, the second call would fail — which is the AC-8 incentive.
  budget_artifact "$WD/dv-lean.md" 120 1
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv-lean.md"
  assert_success
  budget_artifact "$WD/dv-lean4.md" 120 4
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv-lean4.md"
  assert_success
  # The 4-stub file is over the old flat 200 in TOTAL tokens — the case the old check
  # flagged and the new one deliberately releases.
  assert_output --partial "tokens=2"
}

@test "budget: the exclusion is capped, so extra stubs cannot buy prose room" {
  # Twelve stubs is three times the per-stage cap; the exclusion still stops at 64
  # tokens, so an artifact this size fails on its prose exactly as it would at four.
  budget_artifact "$WD/dv-gamed.md" 200 12
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv-gamed.md"
  assert_failure 1
  assert_output --partial "discretionary tokens > 200 budget"
  # The excluded amount is the cap, not the measured 12-stub block.
  assert_output --partial "- 64 sweep-stub tokens excluded"
}

@test "budget: the 264 absolute ceiling is reported alongside the failure" {
  budget_artifact "$WD/dv-huge.md" 260 4
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv-huge.md"
  assert_failure 1
  assert_output --partial "> 264 absolute ceiling"
}

@test "budget: every stage artifact this repo ships passes the promoted gate" {
  # R8 is deliberately breaking; the claim that no in-tree artifact fails it is
  # verified here rather than asserted in prose.
  local f
  for f in "$PLUGIN_ROOT"/.context/*-[0-9].md; do
    [ -e "$f" ] || continue
    run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$f"
    assert_success
  done
}

# --- files_touched structural cap (R-2.1) ------------------------------------

# mk_dv <file> <files_touched-yaml-flow> [body] — a minimal valid DV artifact.
mk_dv_ft() {
  local out="$1" ft="$2"
  {
    echo '---'
    echo 'handoff:'
    echo '  stage: DV'
    echo '  tests_executed: 12'
    echo '  test_summary_line: "12 tests, 0 failures"'
    echo '  verdict: ok'
    echo '  summary: "cap fixture"'
    echo "  files_touched: $ft"
    echo '  next_stage_focus: "DR reviews"'
    echo '  open_questions: []'
    echo '  refs: { dev: development.md#files-changed }'
    echo '---'
    echo
    echo '# Development'
    echo
    echo '12 tests, 0 failures'
    echo
    echo '## elicitation-sweep'
    echo
    echo 'nothing to ask'
  } > "$out"
}

@test "files_touched: ten paths plus one '+ N more' marker passes" {
  local ft="[a1.sh, a2.sh, a3.sh, a4.sh, a5.sh, a6.sh, a7.sh, a8.sh, a9.sh, a10.sh, \"+ 7 more\"]"
  mk_dv_ft "$WD/capped.md" "$ft"
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/capped.md"
  assert_success
}

@test "files_touched: more than FILES_TOUCHED_MAX paths without a marker fails" {
  local ft="[a1.sh, a2.sh, a3.sh, a4.sh, a5.sh, a6.sh, a7.sh, a8.sh, a9.sh, a10.sh, a11.sh]"
  mk_dv_ft "$WD/uncapped.md" "$ft"
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/uncapped.md"
  assert_failure
  assert_output --partial "FILES_TOUCHED_MAX=10"
}

@test "files_touched: a marker that is not last fails" {
  local ft="[\"+ 3 more\", a1.sh]"
  mk_dv_ft "$WD/misplaced.md" "$ft"
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/misplaced.md"
  assert_failure
  assert_output --partial "not the last entry"
}

# --- decision divergence (R-4.1) ---------------------------------------------

# mk_qa_dec <file> <fm-summary> <body-summary>
mk_qa_dec() {
  {
    echo '---'
    echo 'handoff:'
    echo '  stage: QA'
    echo '  verdict: ok'
    echo '  tests_executed: 12'
    echo '  test_summary_line: "12 tests, 0 failures"'
    echo '  summary: "divergence fixture"'
    echo '  files_touched: [a.sh]'
    echo '  key_decisions:'
    echo "    - { id: qa-1, summary: \"$2\" }"
    echo '  open_questions: []'
    echo '  refs: { qa: testing.md#results }'
    echo '---'
    echo
    echo '## decisions'
    echo
    echo "| id | summary |"
    echo "|----|---------|"
    echo "| qa-1 | $3 |"
    echo
    echo '12 tests, 0 failures'
    echo
    echo '## elicitation-sweep'
    echo
    echo 'nothing to ask'
  } > "$1"
}

@test "decisions: a body table restating the same decision passes" {
  mk_qa_dec "$WD/agree.md" \
    "Selection runs the full suite because the harness itself changed" \
    "The full suite runs: the harness changed, so a scoped selection proves nothing"
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/agree.md"
  assert_success
}

@test "decisions: the same id carrying an unrelated body summary fails, naming both" {
  mk_qa_dec "$WD/diverge.md" \
    "Selection runs the full suite because the harness itself changed" \
    "Screenshots are waived for this platform"
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/diverge.md"
  assert_failure
  assert_output --partial "decision qa-1 disagrees across transports"
}

@test "decisions: a restated bound with a different number fails" {
  mk_qa_dec "$WD/numbers.md" \
    "The retry budget for a failing stage is 3 attempts" \
    "The retry budget for a failing stage is 5 attempts"
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/numbers.md"
  assert_failure
  assert_output --partial "disagrees across transports"
}

# --- reverse sweep parity, stage-scoped (R-1.3) ------------------------------

@test "sweep parity: a ledger stub for this stage that the artifact omits fails" {
  cd "$WD"
  jq '.facts.open_questions = [{"id":"sw-DV0-9","class":"decision","ref":"development-0.md#elicitation-sweep","blocks_next_stage":false,"stage":"DV","status":"open"}]' \
    state.json > state2.json
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter development-0.md --state state2.json
  assert_failure
  assert_output --partial "in ledger, not in frontmatter"
}

@test "sweep parity: a resolved ledger stub the artifact omits does not fail a rework round" {
  cd "$WD"
  # The rework topology: round 1 raised sw-DV0-9 and it was answered, so the reworked
  # artifact re-emits only what is still open. Charging it with the answered id fails the
  # round, and Step B.1 reads that as missing_input and re-dispatches the whole stage.
  jq '.facts.open_questions = [{"id":"sw-DV0-9","class":"decision","ref":"development-0.md#elicitation-sweep","blocks_next_stage":false,"stage":"DV","status":"resolved"}]' \
    state.json > state_resolved.json
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter development-0.md --state state_resolved.json
  assert_success
}

@test "sweep parity: an open ledger stub is still charged when a resolved sibling exists" {
  cd "$WD"
  # Non-vacuity twin: the status filter must not disable the arm wholesale.
  jq '.facts.open_questions = [
        {"id":"sw-DV0-8","class":"decision","ref":"development-0.md#elicitation-sweep","blocks_next_stage":false,"stage":"DV","status":"resolved"},
        {"id":"sw-DV0-9","class":"decision","ref":"development-0.md#elicitation-sweep","blocks_next_stage":false,"stage":"DV","status":"open"}]' \
    state.json > state_mixed.json
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter development-0.md --state state_mixed.json
  assert_failure
  assert_output --partial "sw-DV0-9"
  refute_output --partial "sw-DV0-8"
}

@test "sweep parity: a ledger stub belonging to another stage is not charged to this one" {
  cd "$WD"
  jq '.facts.open_questions = [{"id":"sw-PL0-1","class":"decision","ref":"planning-0.md#elicitation-sweep","blocks_next_stage":false,"stage":"PL","status":"open"}]' \
    state.json > state3.json
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter development-0.md --state state3.json
  assert_success
}

@test "files_touched: two '+ N more' markers fail — the overflow must be declared once" {
  local ft="[a1.sh, \"+ 3 more\", \"+ 4 more\"]"
  mk_dv_ft "$WD/twomarkers.md" "$ft"
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/twomarkers.md"
  assert_failure
  assert_output --partial "markers"
}

@test "sweep parity: a split stage charges each stream only its own task's stubs" {
  cd "$WD"
  # DV0 and DV1 both live in the ledger; the DV1 artifact re-emits sw-DV1-1 and must not be
  # charged DV0's sw-DV0-9, which shares the `.stage == "DV"` slice.
  jq '.tasks.DV0 = {status:"completed"} | .tasks.DV1 = {status:"in_progress"}
      | .facts.open_questions = [
          {"id":"sw-DV0-9","class":"decision","ref":"development-0.md#elicitation-sweep","blocks_next_stage":false,"stage":"DV","status":"open"},
          {"id":"sw-DV1-1","class":"decision","ref":"#elicitation-sweep","blocks_next_stage":false,"stage":"DV","status":"open"}]' \
    state.json > state4.json
  sweep_artifact "$WD/dv1.md" '{ id: sw-DV1-1, class: decision, ref: "#elicitation-sweep", blocks_next_stage: false }'
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv1.md" --state state4.json
  assert_success
}

@test "sweep parity: a stub-less artifact of a split stage is not guessed onto either stream" {
  cd "$WD"
  jq '.tasks.DV0 = {status:"completed"} | .tasks.DV1 = {status:"in_progress"}
      | .facts.open_questions = [{"id":"sw-DV0-9","class":"decision","ref":"development-0.md#elicitation-sweep","blocks_next_stage":false,"stage":"DV","status":"open"}]' \
    state.json > state5.json
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter development-0.md --state state5.json
  assert_success
}

# mk_qa_dec_bullet <file> <fm-summary> <body-bullet-line> — the two bullet body forms the
# extractor must reach; the table fixture above covered neither.
mk_qa_dec_bullet() {
  {
    echo '---'
    echo 'handoff:'
    echo '  stage: QA'
    echo '  verdict: ok'
    echo '  tests_executed: 12'
    echo '  test_summary_line: "12 tests, 0 failures"'
    echo '  summary: "divergence fixture"'
    echo '  files_touched: [a.sh]'
    echo '  key_decisions:'
    echo "    - { id: qa-1, summary: \"$2\" }"
    echo '  open_questions: []'
    echo '  refs: { qa: testing.md#results }'
    echo '---'
    echo
    echo '## decisions'
    echo
    echo "$3"
    echo
    echo '12 tests, 0 failures'
    echo
    echo '## elicitation-sweep'
    echo
    echo 'nothing to ask'
  } > "$1"
}

@test "decisions: the bullet body form is extracted, not silently skipped" {
  # Anti-vacuity for the two bullet passes below: if the extractor found nothing, a
  # contradiction this total would still pass.
  mk_qa_dec_bullet "$WD/bullet-diverge.md" \
    "Selection runs the full suite because the harness itself changed" \
    '- **qa-1** — Screenshots are waived for this platform'
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/bullet-diverge.md"
  assert_failure
  assert_output --partial "decision qa-1 disagrees across transports"
}

@test "decisions: the '- **id — title.**' bullet form is reached too" {
  # The form this repo's own architecture artifacts use; the extractor was inert against it.
  mk_qa_dec_bullet "$WD/bullet-inline-diverge.md" \
    "Selection runs the full suite because the harness itself changed" \
    '- **qa-1 — Screenshots are waived for this platform.**'
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/bullet-inline-diverge.md"
  assert_failure
  assert_output --partial "decision qa-1 disagrees across transports"
}

@test "decisions: an agreeing '- **id — title.**' bullet passes" {
  mk_qa_dec_bullet "$WD/bullet-inline-agree.md" \
    "Selection runs the full suite because the harness itself changed" \
    '- **qa-1 — The full suite runs: the harness changed, so a scoped selection proves nothing.**'
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/bullet-inline-agree.md"
  assert_success
}

@test "decisions: an em-dash inside the summary is not eaten by the trim" {
  # The inline-bullet trim anchors to the id, so a second separator belongs to the summary.
  mk_qa_dec_bullet "$WD/bullet-emdash.md" \
    "Selection runs the full suite because the harness itself changed" \
    '- **qa-1 — Selection — the full one — runs because the harness changed.**'
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/bullet-emdash.md"
  assert_success
}

@test "decisions: a body citing a sibling artifact does not manufacture a digit (F-07a)" {
  # planning-0.md used to contribute a bare 0, so the frontmatter's 3 matched nothing and
  # the boundary blocked on an artifact that agrees with itself.
  mk_qa_dec "$WD/filename-digit.md" \
    "The retry budget for a failing stage is 3 attempts" \
    "The retry budget for a failing stage is three attempts, per planning-0.md"
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/filename-digit.md"
  assert_success
}

@test "decisions: every filename extension in the allow-list is stripped" {
  local ext
  for ext in md yml yaml json jsonl sh bats txt log; do
    mk_qa_dec "$WD/fn-$ext.md" \
      "The retry budget for a failing stage is 3 attempts" \
      "The retry budget for a failing stage is three attempts, per state-0.$ext"
    run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/fn-$ext.md"
    assert_success || fail "extension $ext still contributed a digit"
  done
}

@test "decisions: a digit inside a hyphenated name is not a quoted count (F-07b)" {
  # `newest-8` names a ring; it is not the "restated bound or count" the arm looks for.
  mk_qa_dec "$WD/hyphen-digit.md" \
    "The newest-8 decisions ring is rescoped per task" \
    "The newest-4 questions ring is rescoped per task as well"
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/hyphen-digit.md"
  assert_success
}

@test "decisions: a genuine numeric divergence still fails after both harvest fixes" {
  # The sensitivity floor for AC-6: standalone counts on both sides, none common.
  mk_qa_dec "$WD/still-fails.md" \
    "The retry budget for a failing stage is 3 attempts, see planning-0.md" \
    "The retry budget for a failing stage is 5 attempts, see planning-0.md"
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/still-fails.md"
  assert_failure
  assert_output --partial "decision qa-1 disagrees across transports"
}

@test "decisions: stripping filenames cannot false-fail arm 1" {
  # A summary made entirely of filenames empties one side, and arm 1 declines rather than
  # firing on a vocabulary set it just erased.
  mk_qa_dec "$WD/all-filenames.md" \
    "planning-0.md architecture-0.md" \
    "Selection runs the full suite because the harness itself changed"
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/all-filenames.md"
  assert_success
}

# --- collect-all frontmatter reporting (REQ-13) ------------------------------

@test "collect-all: two violated check groups report two lines and one non-zero exit" {
  # AC-7. Before this, an author fixed the cap failure and was immediately handed the stub
  # failure on the re-run — one boundary round per defect.
  local ft="[a1.sh, a2.sh, a3.sh, a4.sh, a5.sh, a6.sh, a7.sh, a8.sh, a9.sh, a10.sh, a11.sh]"
  {
    echo '---'
    echo 'handoff:'
    echo '  stage: DV'
    echo '  tests_executed: 12'
    echo '  test_summary_line: "12 tests, 0 failures"'
    echo '  verdict: ok'
    echo '  summary: "collect-all fixture"'
    echo "  files_touched: $ft"
    echo '  next_stage_focus: "DR reviews"'
    echo '  open_questions:'
    echo '    - "q1: not a stub"'
    echo '  refs: { dev: development.md#files-changed }'
    echo '---'
    echo
    echo '# Development'
    echo
    echo '12 tests, 0 failures'
  } > "$WD/two-faults.md"
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/two-faults.md"
  assert_failure 1
  assert_output --partial "FILES_TOUCHED_MAX=10"
  assert_output --partial "is not a sweep stub"
  # Each failure keeps its own greppable line; they are not aggregated.
  local lines
  lines="$(printf '%s\n' "$output" | grep -c '^fail: ')"
  [ "$lines" -ge 2 ] || fail "expected >=2 distinct fail: lines, got $lines"
}

@test "collect-all: the required-field loop reports every missing field, not the first" {
  {
    echo '---'
    echo 'handoff:'
    echo '  stage: DV'
    echo '  tests_executed: 12'
    echo '  test_summary_line: "12 tests, 0 failures"'
    echo '  verdict: ok'
    echo '  summary: "missing fields fixture"'
    echo '---'
    echo
    echo '# Development'
    echo
    echo '12 tests, 0 failures'
  } > "$WD/missing-fields.md"
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/missing-fields.md"
  assert_failure 1
  assert_output --partial "missing required field: refs"
  assert_output --partial "missing required field: files_touched"
  assert_output --partial "missing required field: next_stage_focus"
}

@test "collect-all: the prologue still fails fast — an unknown stage reports only itself" {
  {
    echo '---'
    echo 'handoff:'
    echo '  stage: ZZ'
    echo '  verdict: ok'
    echo '---'
    echo
    echo '# Nothing'
  } > "$WD/unknown-stage.md"
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/unknown-stage.md"
  assert_failure 1
  assert_output --partial "fail: unknown stage ZZ"
  refute_output --partial "missing required field"
}

@test "collect-all: a broken stub counts in full against the budget and says so" {
  # Not a skip: the exclusion is only sound once the stub shape passes, and skipping the
  # budget arm would let a broken stub hide an over-budget block for a round.
  local pad
  pad="$(head -c 900 < /dev/zero | tr '\0' 'x' | sed 's/x/word /g')"
  {
    echo '---'
    echo 'handoff:'
    echo '  stage: DV'
    echo '  tests_executed: 12'
    echo '  test_summary_line: "12 tests, 0 failures"'
    echo '  verdict: ok'
    echo "  summary: \"budget fixture $pad\""
    echo '  files_touched: [a.md]'
    echo '  next_stage_focus: "DR reviews"'
    echo '  open_questions:'
    echo '    - "q1: not a stub"'
    echo '  refs: { dev: development.md#files-changed }'
    echo '---'
    echo
    echo '# Development'
    echo
    echo '12 tests, 0 failures'
  } > "$WD/broken-stub-budget.md"
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/broken-stub-budget.md"
  assert_failure 1
  assert_output --partial "is not a sweep stub"
  assert_output --partial "(stub-shape invalid: sweep stubs counted in full)"
  assert_output --partial "- 0 sweep-stub tokens excluded"
}

@test "collect-all: a clean artifact still reports one ok: line and exit 0" {
  # Anti-vacuity: an aggregate return that never resets would fail everything.
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/development-0.md"
  assert_success
  assert_output --partial "ok: "
}

# --- raw control bytes are a gate failure ------------------------------------
# Bytes are printf-generated; the NUL rides inside an inline-code list of escape spellings,
# the exact shape a typed escape was decoded into.

@test "control bytes: a raw NUL fails naming the path and byte offset" {
  local off
  off=$(( $(wc -c < "$WD/development-0.md") + 19 ))
  { cat "$WD/development-0.md"; printf 'spellings `\\0` raw \000 end\n'; } > "$WD/nul.md"
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/nul.md"
  assert_failure 1
  assert_output --partial "fail: control byte 0x00 at byte offset $off in $WD/nul.md"
}

@test "control bytes: the same text spelling the escape literally passes" {
  { cat "$WD/development-0.md"; printf '%s\n' 'spellings `\0` raw \0 end'; } > "$WD/literal.md"
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/literal.md"
  assert_success
}

@test "control bytes: --strict fails the same way" {
  { cat "$WD/development-0.md"; printf 'esc \033 here\n'; } > "$WD/esc.md"
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/esc.md" --strict
  assert_failure 1
  assert_output --partial "fail: control byte 0x1B at byte offset"
}

@test "control bytes: the gate refuses to run when the library is unreachable" {
  local copy="$WD/scripts"
  mkdir -p "$copy"
  cp "$PLUGIN_ROOT/$SCRIPT" "$PLUGIN_ROOT/skills/worktask/scripts/sweep-stub-lib.sh" \
    "$PLUGIN_ROOT/skills/worktask/scripts/frontmatter-lib.sh" "$copy/"
  run bash "$copy/handoff-harness.sh" --validate-frontmatter "$WD/development-0.md"
  assert_failure 1
  assert_output --partial "control-byte-lib.sh unreachable"
}

# --- split-stage parity scoped by handoff.task_id -----------------------------

# split_artifact <path> <task_id|-> [stub-yaml] — a DV artifact; no stub means `open_questions: []`.
# A stub's anchor carries a two-option item naming its id, so the harness's item-body check
# never decides a verdict here and each case isolates task_id parity.
split_artifact() {
  local stub_id=""
  if [ -n "${3:-}" ]; then
    stub_id="${3#*id: }"
    stub_id="${stub_id%%,*}"
  fi
  {
    printf -- '---\nhandoff:\n  stage: DV\n'
    [ "$2" = "-" ] || printf '  task_id: %s\n' "$2"
    printf '  tests_executed: 12\n  test_summary_line: "12 tests, 0 failures"\n'
    printf '  verdict: ok\n  summary: "split fixture"\n  files_touched: [a.md]\n'
    printf '  next_stage_focus: "DR reviews"\n'
    if [ -n "${3:-}" ]; then
      printf '  open_questions:\n    - %s\n' "$3"
    else
      printf '  open_questions: []\n'
    fi
    printf '  refs:\n    dev: development.md#files-changed\n'
    printf -- '---\n\n# Development\n\n12 tests, 0 failures\n\n## elicitation-sweep\n\n'
    if [ -n "$stub_id" ]; then
      printf -- '- id: %s\n  summary: "Which way?"\n  options:\n' "$stub_id"
      printf -- '    - { label: "A", detail: "first" }\n    - { label: "B", detail: "second" }\n'
    else
      printf 'body\n'
    fi
  } > "$1"
}

# split_state <out> <open-id>... — DV0 and DV1 share the DV slice; each id is an open DV item.
split_state() {
  local out="$1"
  shift
  # The file precedes --args: every operand after it is a positional string, not an input.
  jq '.tasks.DV0 = {status:"in_progress"} | .tasks.DV1 = {status:"in_progress"}
      | .facts.open_questions = [$ARGS.positional[] | {id: ., class: "decision",
          ref: "#elicitation-sweep", blocks_next_stage: false, stage: "DV", status: "open"}]' \
    state.json --args "$@" > "$out"
  jq -e '.tasks.DV1' "$out" > /dev/null || fail "split_state wrote no ledger"
}

@test "task_id parity: DV0 is not charged DV1's open item" {
  cd "$WD"
  split_state split.json sw-DV1-1
  split_artifact "$WD/dv0.md" DV0
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv0.md" --state split.json
  assert_success
  refute_output --partial "warn:"
}

@test "task_id parity: a stub-less DV1 is charged only its own open item" {
  cd "$WD"
  split_state split.json sw-DV0-1 sw-DV1-1
  split_artifact "$WD/dv1.md" DV1
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv1.md" --state split.json
  assert_failure 1
  assert_output --partial "sweep stub sw-DV1-1 is in ledger, not in frontmatter"
  refute_output --partial "sw-DV0-1"
}

@test "task_id parity: DV1 re-emitting its item passes beside DV0's open item" {
  cd "$WD"
  split_state split.json sw-DV0-1 sw-DV1-1
  split_artifact "$WD/dv1.md" DV1 '{ id: sw-DV1-1, class: decision, ref: "#elicitation-sweep", blocks_next_stage: false }'
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv1.md" --state split.json
  assert_success
}

@test "task_id parity: the mirror passes DV1 and charges DV0" {
  cd "$WD"
  split_state split.json sw-DV0-1
  split_artifact "$WD/dv1.md" DV1
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv1.md" --state split.json
  assert_success
  split_artifact "$WD/dv0.md" DV0
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv0.md" --state split.json
  assert_failure 1
  assert_output --partial "sweep stub sw-DV0-1 is in ledger, not in frontmatter"
}

@test "task_id parity: a sibling's id over this stream's stubs fails instead of escaping" {
  cd "$WD"
  split_state split.json sw-DV1-1 sw-DV1-2
  split_artifact "$WD/dv1.md" DV0 '{ id: sw-DV1-1, class: decision, ref: "#elicitation-sweep", blocks_next_stage: false }'
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv1.md" --state split.json
  assert_failure 1
  assert_output --partial "fail: sweep stub sw-DV1-1 does not belong to handoff.task_id DV0"
}

@test "task_id: another stage's id or a lowercase id fails the shape check" {
  split_artifact "$WD/dr0.md" DR0
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dr0.md"
  assert_failure 1
  assert_output --partial "fail: handoff.task_id 'DR0' is not a task id of stage DV"
  split_artifact "$WD/lower.md" dv0
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/lower.md"
  assert_failure 1
  assert_output --partial "fail: handoff.task_id 'dv0' is not a task id of stage DV"
}

@test "task_id: an id missing from tasks{} fails" {
  cd "$WD"
  split_state split.json sw-DV1-1
  split_artifact "$WD/dv7.md" DV7
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv7.md" --state split.json
  assert_failure 1
  assert_output --partial "fail: handoff.task_id DV7 is not in tasks{}"
}

@test "task_id: absent on a split stage warns and keeps today's rule" {
  cd "$WD"
  split_state split.json sw-DV0-9
  split_artifact "$WD/nostub.md" -
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/nostub.md" --state split.json
  assert_success
  assert_output --partial "warn: nostub.md omits handoff.task_id while stage DV has 2 tasks"
}

@test "task_id: absent on a single-task stage does not warn" {
  cd "$WD"
  jq '.tasks.DV0 = {status:"in_progress"} | .facts.open_questions = []' state.json > single.json
  split_artifact "$WD/single.md" -
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/single.md" --state single.json
  assert_success
  refute_output --partial "warn:"
}

# --- blocked_on: the typed need, gated identically with and without yq ---------------
# The enums are skills/worktask/scripts/blocked-on-lib.sh's; the cases below are the bats twin of
# self_test_blocked_on in skills/worktask/scripts/handoff-harness-selftest.sh.

BO_FIX="${FIXTURES}/worktask/blocked-on"

# _dv_blocked_artifact <path> <lines under handoff:> — a passing DV artifact plus one need.
_dv_blocked_artifact() {
  {
    printf -- '---\nhandoff:\n  stage: DV\n  verdict: blocked\n'
    printf '  summary: "blocked_on fixture"\n  tests_executed: 3\n'
    printf '  test_summary_line: "3 tests, 0 failures"\n  files_touched: [a.md]\n'
    printf '  next_stage_focus: "DR reviews"\n  open_questions: []\n'
    printf '%s\n' "$2"
    printf '  refs:\n    dev: development-0.md#files-changed\n'
    printf -- '---\n\n# Development\n\n## verification-command\n\n3 tests, 0 failures\n\n## elicitation-sweep\n\nnothing to ask\n'
  } > "$1"
}

# _bo_from_fixture <name> — the fixture's need as one JSON flow line, which YAML reads as-is.
_bo_from_fixture() {
  if jq -e 'has("blocked_on")' "$BO_FIX/$1.handoff.json" > /dev/null; then
    printf '  blocked_on: %s' "$(jq -c '.blocked_on' "$BO_FIX/$1.handoff.json")"
  else
    printf '  cross_session_ask: %s' "$(jq -c '.cross_session_ask' "$BO_FIX/$1.handoff.json")"
  fi
}

@test "blocked_on: each of the seven kinds passes the gate, with and without yq" {
  local kind
  for kind in user_decision user_action permission peer_session artifact correction host_environment; do
    _dv_blocked_artifact "$WD/bo-$kind.md" "$(_bo_from_fixture "$kind")"
    run_script_env --separate-stderr "$SCRIPT" --validate-frontmatter "$WD/bo-$kind.md"
    [ "$status" -eq 0 ] || fail "$kind (host reader): exit $status: $stderr"
    run_script_env --separate-stderr --hide yq "$SCRIPT" --validate-frontmatter "$WD/bo-$kind.md"
    [ "$status" -eq 0 ] || fail "$kind (no yq): exit $status: $stderr"
  done
}

@test "blocked_on: unknown kind, unknown resume_with and missing detail fail by name, with and without yq" {
  local spec name want hide
  for spec in 'invalid-unknown-kind|fail: blocked_on.kind "coffee_break" is not one of' \
    'invalid-unknown-resume-with|fail: blocked_on.resume_with "carrier_pigeon" is not one of' \
    'invalid-missing-detail|fail: blocked_on.detail is missing or empty'; do
    name="${spec%%|*}" want="${spec#*|}"
    _dv_blocked_artifact "$WD/$name.md" "$(_bo_from_fixture "$name")"
    for hide in no yes; do
      if [ "$hide" = yes ]; then
        run_script_env --separate-stderr --hide yq "$SCRIPT" --validate-frontmatter "$WD/$name.md"
      else
        run_script_env --separate-stderr "$SCRIPT" --validate-frontmatter "$WD/$name.md"
      fi
      [ "$status" -eq 1 ] || fail "$name (hide yq: $hide): exit $status, want 1"
      [[ "$stderr" == *"$want"* ]] || fail "$name (hide yq: $hide): no '$want' in: $stderr"
    done
  done
}

@test "blocked_on: an empty detail object fails like a missing one" {
  _dv_blocked_artifact "$WD/empty.md" '  blocked_on:
    kind: user_action
    detail: {}
    resume_with: decision_ref'
  run_script_env --separate-stderr --hide yq "$SCRIPT" --validate-frontmatter "$WD/empty.md"
  assert_failure 1
  [[ "$stderr" == *"fail: blocked_on.detail is missing or empty"* ]]
  run_script_env --separate-stderr "$SCRIPT" --validate-frontmatter "$WD/empty.md"
  assert_failure 1
}

@test "--read-blocked-on: the legacy alias reads as peer_session with source cross_session_ask" {
  _dv_blocked_artifact "$WD/alias.md" '  cross_session_ask:
    to: backend-session
    question: "Which base branch does the API change target?"'
  run_script_env --separate-stderr --hide yq "$SCRIPT" --read-blocked-on "$WD/alias.md"
  assert_success
  [ "${#lines[@]}" -eq 2 ]
  jq -e '. == {kind: "peer_session", detail: {to: "backend-session",
    question: "Which base branch does the API change target?"}, resume_with: "reply_ref"}' <<< "${lines[0]}"
  [ "${lines[1]}" = "source: cross_session_ask" ]
  run_script_env --separate-stderr "$SCRIPT" --read-blocked-on "$WD/alias.md"
  assert_success
  [ "${lines[1]}" = "source: cross_session_ask" ]
}

@test "--read-blocked-on: blocked_on wins over the alias, and neither present exits 1" {
  _dv_blocked_artifact "$WD/both.md" "$(_bo_from_fixture artifact)
$(_bo_from_fixture legacy-cross-session-ask)"
  run_script_env --separate-stderr --hide yq "$SCRIPT" --read-blocked-on "$WD/both.md"
  assert_success
  jq -e '.kind == "artifact"' <<< "${lines[0]}"
  [ "${lines[1]}" = "source: blocked_on" ]
  _dv_test_evidence_artifact "$WD/none.md" 3
  run_script_env --separate-stderr --hide yq "$SCRIPT" --read-blocked-on "$WD/none.md"
  assert_failure 1
  [[ "$stderr" == *"no blocked_on or cross_session_ask"* ]]
}

@test "--read-blocked-on: the no-yq reader parses block style, flow style and a block sequence alike" {
  local want
  want='{"kind":"user_decision","detail":{"question":"Ship: behind a flag?","options":["flag","no-flag"],"recommended":"flag"},"resume_with":"decision_ref"}'
  _dv_blocked_artifact "$WD/block.md" '  blocked_on:
    kind: user_decision   # the stage cannot choose
    detail:
      question: "Ship: behind a flag?"
      options:
        - flag
        - '"'no-flag'"'
      recommended: flag
    resume_with: decision_ref'
  _dv_blocked_artifact "$WD/flow.md" '  blocked_on: { kind: user_decision, detail: { question: "Ship: behind a flag?", options: [flag, no-flag], recommended: flag }, resume_with: decision_ref }'
  local f
  for f in block flow; do
    run_script_env --separate-stderr --hide yq "$SCRIPT" --read-blocked-on "$WD/$f.md"
    assert_success
    [ "$(jq -cS . <<< "${lines[0]}")" = "$(jq -cS . <<< "$want")" ] || fail "$f (no yq): ${lines[0]}"
    run_script_env --separate-stderr "$SCRIPT" --read-blocked-on "$WD/$f.md"
    assert_success
    [ "$(jq -cS . <<< "${lines[0]}")" = "$(jq -cS . <<< "$want")" ] || fail "$f (host reader): ${lines[0]}"
  done
}

@test "blocked_on: the self-test source carries one case per kind and each refusal, each asserting its exit code" {
  local st="$PLUGIN_ROOT/skills/worktask/scripts/handoff-harness-selftest.sh" kind
  for kind in user_decision user_action permission peer_session artifact correction host_environment; do
    grep -qE "^$kind\|" "$st" || fail "no self-test case row for $kind"
  done
  grep -qF '_bo_case "valid/$kind" 0' "$st" || fail "the valid cases do not assert exit 0"
  grep -qF '_bo_case "unknown-kind" 1' "$st" || fail "no unknown-kind case asserting exit 1"
  grep -qF '_bo_case "unknown-resume_with" 1' "$st" || fail "no unknown resume_with case asserting exit 1"
  grep -qF '_bo_case "missing-detail" 1' "$st" || fail "no missing-detail case asserting exit 1"
  grep -qF 'legacy-alias/reads-as-peer_session' "$st" || fail "no legacy alias read case"
  grep -qF 'skills/worktask/scripts/blocked-on-lib.sh' "$BATS_TEST_FILENAME"
}
