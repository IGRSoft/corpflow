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

@test "contract: --self-test passes (smoke, NON-counting)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --self-test
  assert_success
  assert_output --partial "ALL PASS"
}

# --- the sweep stub's ref must be anchor-shaped, not merely present ----------

# A DV artifact whose only variable is the one sweep stub.
sweep_artifact() {  # <path> <stub-yaml>
  {
    printf -- '---\n'
    printf 'handoff:\n'
    printf '  stage: DV\n'
    printf '  verdict: ok\n'
    printf '  summary: "sweep fixture"\n'
    printf '  files_touched: [a.md]\n'
    printf '  next_stage_focus: "DR reviews"\n'
    printf '  open_questions:\n'
    printf '    - %s\n' "$2"
    printf '  refs:\n'
    printf '    dev: development.md#files-changed\n'
    printf -- '---\n\n# Development\n\n## elicitation-sweep\n\nbody\n'
  } > "$1"
}

@test "sweep: an empty ref fails the shape gate" {
  sweep_artifact "$WD/dv-empty-ref.md" '{ id: sw-DV0-1, class: decision, ref: "" }'
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv-empty-ref.md"
  assert_failure 1
  assert_output --partial "sw-DV0-1 carries no ref anchor"
}

@test "sweep: a ref naming no anchor fails the shape gate" {
  sweep_artifact "$WD/dv-no-anchor.md" '{ id: sw-DV0-1, class: decision, ref: "planning-0.md" }'
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv-no-anchor.md"
  assert_failure 1
  assert_output --partial "sw-DV0-1 carries no ref anchor"
}

@test "sweep: an uppercase anchor fails — anchors are lowercase-kebab" {
  sweep_artifact "$WD/dv-caps.md" '{ id: sw-DV0-1, class: decision, ref: "planning-0.md#Elicitation_Sweep" }'
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv-caps.md"
  assert_failure 1
  assert_output --partial "sw-DV0-1 carries no ref anchor"
}

@test "sweep: an anchor-only ref resolves to the emitting artifact and passes" {
  sweep_artifact "$WD/dv-anchor-only.md" '{ id: sw-DV0-1, class: decision, ref: "#elicitation-sweep" }'
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv-anchor-only.md"
  assert_success
}

@test "sweep: the class vocabulary is the library's, not a re-spelling" {
  sweep_artifact "$WD/dv-class.md" '{ id: sw-DV0-1, class: question, ref: "#elicitation-sweep" }'
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv-class.md"
  assert_failure 1
  assert_output --partial "class is not decision|escalate"
}

@test "sweep: a ledger whose facts.open_questions is a string fails, never silently passes" {
  # jq aborts on a scalar there, and an aborted parity read is not evidence of parity:
  # the shapes that break the read are exactly the ones the gate exists to reject.
  sweep_artifact "$WD/dv-scalar-ledger.md" '{ id: sw-DV0-1, class: decision, ref: "#elicitation-sweep" }'
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
    printf '  verdict: ok\n'
    printf '  summary: "gate fixture"\n'
    printf '  files_touched: [a.md]\n'
    printf '  next_stage_focus: "DR reviews"\n'
    printf '  open_questions: []\n'
    printf '  refs:\n'
    printf '    %s\n' "$refs"
    printf -- '---\n\n# Development\n'
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
  sweep_artifact "$WD/dv-spill.md" '{ id: sw-DV0-1, class: decision, ref: "#elicitation-sweep" }'
  spill_state "$WD/state-spill.json" 4 '[]'
  printf '%s\n' '{"id":"sw-DV0-1","class":"decision","ref":"#elicitation-sweep","stage":"DV","status":"open","spilled_at":"2026-01-01T00:00:00Z","spilled_from_stage":"DV"}' \
    > "$WD/open-questions-4.jsonl"
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv-spill.md" --state "$WD/state-spill.json"
  assert_success
}

@test "spill: the same item with NO spill file still fails — parity is not weakened" {
  sweep_artifact "$WD/dv-nospill.md" '{ id: sw-DV0-1, class: decision, ref: "#elicitation-sweep" }'
  spill_state "$WD/state-nospill.json" 4 '[]'
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv-nospill.md" --state "$WD/state-nospill.json"
  assert_failure 1
  assert_output --partial "not in facts.open_questions[]"
}

@test "spill: a malformed spill file fails rather than reading as the empty set" {
  # Treating a corrupt overflow file as "no items" would restore the exact loss the
  # parity check exists to catch, and only in the runs that actually overflowed.
  sweep_artifact "$WD/dv-badspill.md" '{ id: sw-DV0-1, class: decision, ref: "#elicitation-sweep" }'
  spill_state "$WD/state-badspill.json" 4 '["sw-DV0-1"]'
  printf 'not json at all\n' > "$WD/open-questions-4.jsonl"
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv-badspill.md" --state "$WD/state-badspill.json"
  assert_failure 1
  assert_output --partial "not readable as JSON lines"
}

@test "spill: the path derives from the ledger's run_index, never a guess" {
  sweep_artifact "$WD/dv-idx.md" '{ id: sw-DV0-1, class: decision, ref: "#elicitation-sweep" }'
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
    printf '  verdict: ok\n'
    printf '  summary: "budget fixture%s"\n' "$pad"
    printf '  files_touched: [a.md]\n'
    printf '  next_stage_focus: "DR reviews"\n'
    printf '  open_questions:\n'
    for ((i = 1; i <= stubs; i++)); do
      printf '    - { id: sw-DV0-%s, class: decision, ref: "#elicitation-sweep" }\n' "$i"
    done
    printf '  refs:\n'
    printf '    dev: development.md#files-changed\n'
    printf -- '---\n\n# Development\n\n## elicitation-sweep\n\nbody\n'
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
