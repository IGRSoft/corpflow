#!/usr/bin/env bats
# Single-sourcing and completeness contracts for the closing elicitation sweep
# (skills/shared/stage-contracts.md § Closing Elicitation Sweep).
#
# Every parity assertion extracts BOTH sides from their own defining file. A
# hardcoded copy inside the test would be the same drift defect these contracts
# exist to catch, so each helper takes the files it reads as arguments — which is
# also what lets the can-actually-fail twin re-run it against a planted copy.
#
# No JSON-Schema validator is vendored in this suite, so AC-3 asserts the schema
# FACTS (branch disjointness; exactly-one-recommended as contains/minContains/
# maxContains) rather than executing the schema against instances.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

CONTRACTS="skills/shared/stage-contracts.md"
HANDOFF="skills/worktask/references/handoff-protocol.md"
STAGE_CODES="skills/shared/stage-codes.md"
WORKTASK_CMD="commands/worktask.md"
PL0_PROC="skills/worktask/references/pl0-procedure.md"
PREFLIGHT="skills/worktask/scripts/preflight-issue-scan.sh"
WORKTASK_SKILL="skills/worktask/SKILL.md"

# Agents that are NOT stage agents and therefore owe no sweep pointer.
NON_STAGE_AGENTS="designer prompt-engineer"

# --- extraction helpers ------------------------------------------------------

# Canonical stage vocabulary: stage-codes.md § Primary Stages UNION the
# handoff-protocol.md § Handoff Schemas titles (ET lives only in the latter).
left_codes() {
  { awk '/^## Primary Stages/,/^### /' "$1" | sed -nE 's/^\| ([A-Z]{2}) \|.*/\1/p'
    sed -nE 's/^ *"title": "([A-Z]{2})Handoff",?$/\1/p' "$2" ; } | sort -u
}

# The obligation matrix's own rows. `####` sub-headings stay inside the range;
# the next `### ` ends it, so the range needs no knowledge of what follows it.
matrix_codes() {
  awk '/^### Sweep obligation matrix/{f=1;next} /^### /{f=0} f' "$1" \
    | sed -nE 's/^\| ([A-Z]{2}) \|.*/\1/p' | sort -u
}

canonical_phrase() { sed -nE 's/^## (Closing Elicitation Sweep)$/\1/p' "$1"; }

# The open_questions branch list, extracted from the frontmatter schema block.
open_questions_schema() {
  awk '/^      open_questions:$/{f=1} f{print} f&&/^      refs:$/{exit}' "$1"
}

sweep_defs() { awk '/^  SweepItem:$/{f=1} f{print} /^  SweepStub:$/{g=1} g&&/^```$/{exit}' "$1"; }

section_body() {  # section_body <file> <heading-regex>
  awk -v re="$2" '$0 ~ re {f=1;next} f && /^#{2,5} /{f=0} f' "$1"
}

# --- contract helpers (each carries its own non-vacuity guard) ---------------

check_matrix_completeness() {  # <contracts> <stage-codes> <handoff>
  local left right nl nr
  left="$(left_codes "$2" "$3")"; right="$(matrix_codes "$1")"
  nl=$(printf '%s\n' "$left" | grep -c '[A-Z]' || true)
  nr=$(printf '%s\n' "$right" | grep -c '[A-Z]' || true)
  [ "$nl" -ge 12 ] || { echo "non-vacuity: canonical stage list extracted only $nl codes"; return 1; }
  [ "$nr" -ge 12 ] || { echo "non-vacuity: matrix extracted only $nr rows"; return 1; }
  [ "$left" = "$right" ] || {
    echo "matrix rows and canonical stage list disagree:"
    diff <(printf '%s\n' "$left") <(printf '%s\n' "$right") || true
    return 1
  }
}

check_pointer_once() {  # <agents-dir> <contracts>
  local phrase f base n checked=0 rc=0
  phrase="$(canonical_phrase "$2")"
  [ -n "$phrase" ] || { echo "non-vacuity: no canonical heading found in $2"; return 1; }
  for f in "$1"/*.md; do
    base="$(basename "$f" .md)"
    case " $NON_STAGE_AGENTS " in *" $base "*) continue ;; esac
    checked=$((checked + 1))
    n="$(grep -c -F "$phrase" "$f" || true)"
    [ "$n" -eq 1 ] || { echo "$base.md: expected exactly 1 pointer, got $n"; rc=1; }
  done
  [ "$checked" -ge 14 ] || { echo "non-vacuity: only $checked stage agents checked"; return 1; }
  return $rc
}

check_schema_branches() {  # <handoff>
  local blk defs
  blk="$(open_questions_schema "$1")"
  [ "$(printf '%s\n' "$blk" | grep -c '^            - ' || true)" -ge 3 ] \
    || { echo "non-vacuity: fewer than 3 oneOf branches extracted"; return 1; }
  printf '%s\n' "$blk" | grep -q 'oneOf' || { echo "open_questions is not a oneOf"; return 1; }
  printf '%s\n' "$blk" | grep -qE '^ *- type: string' || { echo "legacy string form dropped"; return 1; }
  printf '%s\n' "$blk" | grep -qE '^ *required: \[id, summary\]' || { echo "legacy bare-object form dropped"; return 1; }
  printf '%s\n' "$blk" | grep -qE '^ *not: \{ required: \[class\] \}' \
    || { echo "legacy bare-object branch lacks the disjointness guard: a sweep stub would match two branches and oneOf then fails every existing handoff"; return 1; }
  printf '%s\n' "$blk" | grep -q 'SweepStub' || { echo "no additive sweep branch"; return 1; }

  defs="$(sweep_defs "$1")"
  [ -n "$defs" ] || { echo "non-vacuity: \$defs block not extracted"; return 1; }
  printf '%s\n' "$defs" | grep -q 'minItems: 2' || { echo "options minItems 2 missing"; return 1; }
  printf '%s\n' "$defs" | grep -q 'maxItems: 4' || { echo "options maxItems 4 missing"; return 1; }
  printf '%s\n' "$defs" | grep -qE 'contains:.*recommended.*const: true' \
    || { echo "exactly-one-recommended is not a schema fact"; return 1; }
  printf '%s\n' "$defs" | grep -q 'minContains: 1' || { echo "zero recommended options would pass"; return 1; }
  printf '%s\n' "$defs" | grep -q 'maxContains: 1' || { echo "two recommended options would pass"; return 1; }
}

check_templates_carry_field() {  # <contracts>
  local n_tpl n_field
  n_tpl=$(grep -c '^### #tpl-' "$1" || true)
  [ "$n_tpl" -ge 13 ] || { echo "non-vacuity: only $n_tpl templates found"; return 1; }
  n_field=$(awk '/^### #tpl-/{t=1} t&&/^  open_questions:/{c++} END{print c+0}' "$1")
  [ "$n_field" -eq "$n_tpl" ] \
    || { echo "$n_field of $n_tpl per-stage templates carry open_questions:"; return 1; }
}

check_empty_obligation_once() {  # <contracts>
  local n; n=$(grep -c 'nothing to elicit' "$1" || true)
  [ "$n" -eq 1 ] || { echo "explicit-empty obligation stated $n times, expected exactly 1"; return 1; }
}

check_raise_only() {  # <worktask-cmd>
  local body c2 c3
  body="$(section_body "$1" '^##### Escalation guard — raise-only self-labels')"
  [ -n "$body" ] || { echo "non-vacuity: raise-only guard section absent"; return 1; }
  printf '%s\n' "$body" | grep -q 'max(' || { echo "guard is not stated as a monotone join"; return 1; }
  printf '%s\n' "$body" | grep -q 'decision < escalate' || { echo "the class lattice is not ordered"; return 1; }
  # Raising honoured AND lowering refused — both directions must be spelled out.
  [ "$(printf '%s\n' "$body" | grep -o '→ `escalate`' | grep -c . || true)" -ge 2 ] \
    || { echo "both lattice directions are not stated"; return 1; }
  c2=$(grep -n 'C.2 — Classify' "$1" | head -1 | cut -d: -f1)
  c3=$(grep -n 'C.3 — Auto-answer' "$1" | head -1 | cut -d: -f1)
  [ -n "$c2" ] && [ -n "$c3" ] || { echo "non-vacuity: Step C.2/C.3 not found"; return 1; }
  [ "$c2" -lt "$c3" ] || { echo "classification does not precede auto-answer"; return 1; }
}

# Carriers are extracted from the files that DEFINE them, never listed here.
carrier_tokens() {  # <pl0> <worktask-cmd> <preflight>
  { grep -oE '\b[a-z][a-z_]*_gate\b' "$1"
    grep -oE '\bmegatask_group\b' "$2"
    grep -oE '\bCORPFLOW_NONINTERACTIVE\b' "$3" ; } | sort -u
}

check_carriers() {  # <contracts> <pl0> <worktask-cmd> <preflight>
  local tables tok n hits rc=0
  tables="$(awk '/^### Unattended fallbacks/{f=1;next} /^### /{f=0} f' "$1")"
  [ -n "$tables" ] || { echo "non-vacuity: fallback tables not extracted"; return 1; }
  n=$(carrier_tokens "$2" "$3" "$4" | grep -c . || true)
  [ "$n" -ge 5 ] || { echo "non-vacuity: only $n carriers extracted from their defining files"; return 1; }
  for tok in $(carrier_tokens "$2" "$3" "$4"); do
    hits=$(printf '%s\n' "$tables" | grep -c -F "$tok" || true)
    [ "$hits" -eq 1 ] || { echo "carrier $tok has $hits behaviour rows, expected exactly 1"; rc=1; }
  done
  return $rc
}

check_channels() {  # <contracts> <repo-root>
  local rows n line path token needle rc=0
  rows="$(awk '/^### Not the sweep/{f=1;next} /^### /{f=0} f' "$1" | grep -E '^\| [a-z]' || true)"
  n=$(printf '%s\n' "$rows" | grep -c . || true)
  [ "$n" -eq 4 ] || { echo "expected 4 pre-existing channels, found $n"; return 1; }
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    token=$(printf '%s\n' "$line" | awk -F'|' '{print $3}' | grep -oE '`[^`]+`' | head -1 | tr -d '`:')
    path=$(printf '%s\n' "$line" | awk -F'|' '{print $4}' | grep -oE '[A-Za-z0-9_./-]+\.md' | head -1)
    if [ -z "$token" ] || [ -z "$path" ]; then
      echo "unparseable channel row: $line"; rc=1; continue
    fi
    case "$path" in */*) ;; *) echo "channel row must cite a repo-relative path: $line"; rc=1; continue ;; esac
    [ -f "$2/$path" ] || { echo "channel row cites a missing file: $path"; rc=1; continue; }
    needle=$(printf '%s' "$token" | sed 's/^handoff\.//; s/^facts\.//')
    grep -qF "$needle" "$2/$path" \
      || { echo "channel $token is not defined in the file it cites ($path)"; rc=1; }
  done <<EOF
$rows
EOF
  return $rc
}

check_single_heading() {  # <repo-root>
  local n
  n=$(cd "$1" && grep -rl '^## Closing Elicitation Sweep' --include='*.md' agents/ commands/ skills/ 2>/dev/null | wc -l | tr -d ' ')
  [ "$n" -eq 1 ] || { echo "canonical heading appears in $n files, expected exactly 1"; return 1; }
}

check_no_fourth_escalation_copy() {  # <repo-root>
  local n
  n=$(cd "$1" && grep -rlE 'spend[- ]authoriz' --include='*.md' agents/ commands/ skills/ 2>/dev/null | wc -l | tr -d ' ')
  [ "$n" -eq 3 ] || { echo "escalation-class enumeration is in $n files, expected 3 (point at the canonical one)"; return 1; }
}

check_no_escape_hatch() {  # <contracts>
  local body
  body="$(awk '/^## Closing Elicitation Sweep/{f=1;next} /^## /{f=0} f' "$1")"
  [ -n "$body" ] || { echo "non-vacuity: canonical section not extracted"; return 1; }
  if printf '%s\n' "$body" | grep -qiE 'warn-only|warn:|advisory|_STRICT|--strict|opt-in'; then
    echo "the sweep surface carries a rollout escape hatch; REQ-10 is strict from day one"
    return 1
  fi
  return 0
}

check_frontmatter_line_budget() {  # <contracts>
  local over
  [ "$(grep -c '^### #tpl-' "$1" || true)" -ge 13 ] || { echo "non-vacuity: templates not found"; return 1; }
  over=$(awk '/^```yaml$/{n=0;f=1;next} f&&/^```$/{if(n>30) print NR":"n; f=0; next} f{n++}' "$1")
  [ -z "$over" ] || { echo "template yaml block over the 30-line budget at line:count $over"; return 1; }
}

# P2-6: check_no_escape_hatch only reaches the canonical section body. The
# sweep obligation is also enforced by three functions in handoff-harness.sh
# (check_sweep_stub_shape, check_sweep_ref_anchor, check_sweep_ledger) and
# their call sites — a warn-only arm could land there without tripping the
# canonical-section grep. This widens the reach without keying on the generic
# "warn:"/"--strict" vocabulary, which the UNRELATED AR-reference rollout
# (§ Step B) legitimately uses in the same file — a naive wide grep would
# false-positive on that rollout's own advisory text.
check_no_sweep_escape_hatch_wide() {  # <harness>
  local fn body hits ln
  for fn in check_sweep_stub_shape check_sweep_ref_anchor check_sweep_ledger; do
    body=$(awk -v f="${fn}() {" 'index($0, f) == 1 {p=1} p{print} p && /^}/{exit}' "$1")
    [ -n "$body" ] || { echo "non-vacuity: $fn not found in $1"; return 1; }
    if printf '%s\n' "$body" | grep -qE 'STRICT|--strict|warn-only|opt-in|echo "warn:'; then
      echo "$fn carries a strict/warn-only escape hatch"
      return 1
    fi
  done
  # Keyed on the CALL (with its real argument list), not on an "if !" prefix:
  # a warn-only wrapper naturally changes the if-condition's shape (e.g. adds
  # a STRICT test ahead of the "!"), which would silently evade a prefix match.
  hits=$(grep -n 'check_sweep_stub_shape "\$fmfile"\|check_sweep_ref_anchor "\$f" "\$fmfile"\|check_sweep_ledger "\$fmfile"' "$1")
  [ -n "$hits" ] || { echo "non-vacuity: no sweep check call sites found in $1"; return 1; }
  while IFS=: read -r ln _; do
    if sed -n "$((ln - 2)),$((ln + 2))p" "$1" | grep -qE 'STRICT|--strict|warn-only|opt-in'; then
      echo "sweep check call at line $ln is gated behind a strict/warn-only conditional"
      return 1
    fi
  done <<< "$hits"
  return 0
}

# --- fixture helper ----------------------------------------------------------

plant() {  # plant <src> <sed-expr> -> prints the mutated copy's path
  local d out
  d="$(mk_tmpworkdir)"
  out="$d/$(basename "$1")"
  sed "$2" "$1" > "$out"
  printf '%s' "$out"
}

# --- AC-1: obligation matrix covers every stage code -------------------------

@test "AC-1: sweep obligation matrix rows equal the canonical stage list (both sides extracted)" {
  run check_matrix_completeness "$PLUGIN_ROOT/$CONTRACTS" "$PLUGIN_ROOT/$STAGE_CODES" "$PLUGIN_ROOT/$HANDOFF"
  assert_success
}

@test "AC-1 twin: dropping one matrix row makes the completeness check fail" {
  local planted
  planted="$(plant "$PLUGIN_ROOT/$CONTRACTS" '/^| ET | Required |/d')"
  run check_matrix_completeness "$planted" "$PLUGIN_ROOT/$STAGE_CODES" "$PLUGIN_ROOT/$HANDOFF"
  assert_failure
}

# --- AC-2: one pointer per stage agent, never a restatement ------------------

@test "AC-2: every stage agent carries the sweep pointer exactly once" {
  run check_pointer_once "$PLUGIN_ROOT/agents" "$PLUGIN_ROOT/$CONTRACTS"
  assert_success
}

@test "AC-2 twin: a duplicated pointer in one agent fails the check" {
  local d phrase
  d="$(mk_tmpworkdir)"
  cp "$PLUGIN_ROOT"/agents/*.md "$d/"
  phrase="$(canonical_phrase "$PLUGIN_ROOT/$CONTRACTS")"
  printf '\nsee %s\n' "$phrase" >> "$d/stakeholder.md"
  run check_pointer_once "$d" "$PLUGIN_ROOT/$CONTRACTS"
  assert_failure
}

@test "AC-2 twin: an agent restating the canonical section as its own heading fails AC-8" {
  local d
  d="$(mk_tmpworkdir)"
  mkdir -p "$d/agents" "$d/commands" "$d/skills"
  cp "$PLUGIN_ROOT/agents/stakeholder.md" "$d/agents/"
  cp "$PLUGIN_ROOT/$CONTRACTS" "$d/skills/"
  printf '\n## Closing Elicitation Sweep\n\nrestated\n' >> "$d/agents/stakeholder.md"
  run check_single_heading "$d"
  assert_failure
}

# --- AC-3: additive schema branch, both legacy forms still valid -------------

@test "AC-3: open_questions keeps both legacy forms, adds a disjoint sweep branch, and pins exactly-one-recommended" {
  run check_schema_branches "$PLUGIN_ROOT/$HANDOFF"
  assert_success
}

@test "AC-3 twin: removing the not:{required:[class]} guard fails (two branches would match)" {
  local planted
  planted="$(plant "$PLUGIN_ROOT/$HANDOFF" '/not: { required: \[class\] }/d')"
  run check_schema_branches "$planted"
  assert_failure
  assert_output --partial "disjointness guard"
}

@test "AC-3 twin: dropping maxContains would let a two-recommended item pass, and fails" {
  local planted
  planted="$(plant "$PLUGIN_ROOT/$HANDOFF" '/maxContains: 1/d')"
  run check_schema_branches "$planted"
  assert_failure
}

@test "AC-3 twin: dropping minContains would let a zero-recommended item pass, and fails" {
  local planted
  planted="$(plant "$PLUGIN_ROOT/$HANDOFF" '/minContains: 1/d')"
  run check_schema_branches "$planted"
  assert_failure
}

@test "AC-3 twin: dropping the legacy string branch fails (existing producers would break)" {
  local planted
  planted="$(plant "$PLUGIN_ROOT/$HANDOFF" '/- type: string  *# legacy free-text form/d')"
  run check_schema_branches "$planted"
  assert_failure
}

# --- AC-4: every template carries the field; empty obligation stated once ----

@test "AC-4: every per-stage frontmatter template carries open_questions" {
  run check_templates_carry_field "$PLUGIN_ROOT/$CONTRACTS"
  assert_success
}

@test "AC-4 twin: a template missing open_questions fails the enumeration" {
  local planted
  planted="$(plant "$PLUGIN_ROOT/$CONTRACTS" '/sw-ST0-1/d')"
  sed -i.bak '/^  stage: ST$/,/^  refs:$/ s/^  open_questions:$//' "$planted"
  run check_templates_carry_field "$planted"
  assert_failure
}

@test "AC-4: the explicit-empty obligation is stated exactly once" {
  run check_empty_obligation_once "$PLUGIN_ROOT/$CONTRACTS"
  assert_success
}

@test "AC-4 twin: restating the explicit-empty obligation a second time fails" {
  local planted
  planted="$(plant "$PLUGIN_ROOT/$CONTRACTS" '$a\
A stage with nothing to ask says so: nothing to elicit.')"
  run check_empty_obligation_once "$planted"
  assert_failure
}

# --- AC-5: raise-only classification -----------------------------------------

@test "AC-5: the class self-label may be raised, never lowered, and is applied before auto-answer" {
  run check_raise_only "$PLUGIN_ROOT/$WORKTASK_CMD"
  assert_success
}

@test "AC-5 twin: removing the monotone-join statement fails the guard check" {
  local planted
  planted="$(plant "$PLUGIN_ROOT/$WORKTASK_CMD" 's/`effective = max(agent_label, orchestrator_label)`/the orchestrator picks a label/')"
  run check_raise_only "$planted"
  assert_failure
}

# --- AC-6: one behaviour row per unattended carrier --------------------------

@test "AC-6: every carrier named in its defining file has exactly one fallback row" {
  run check_carriers "$PLUGIN_ROOT/$CONTRACTS" "$PLUGIN_ROOT/$PL0_PROC" "$PLUGIN_ROOT/$WORKTASK_CMD" "$PLUGIN_ROOT/$PREFLIGHT"
  assert_success
}

@test "AC-6 twin: deleting a carrier's fallback row fails the completeness check" {
  local planted
  planted="$(plant "$PLUGIN_ROOT/$CONTRACTS" '/CORPFLOW_NONINTERACTIVE=1/d')"
  run check_carriers "$planted" "$PLUGIN_ROOT/$PL0_PROC" "$PLUGIN_ROOT/$WORKTASK_CMD" "$PLUGIN_ROOT/$PREFLIGHT"
  assert_failure
}

# --- AC-7: no duplication of channels that already exist ---------------------

@test "AC-7: each of the four pre-existing channels is named once and resolves in the file it cites" {
  run check_channels "$PLUGIN_ROOT/$CONTRACTS" "$PLUGIN_ROOT"
  assert_success
}

@test "AC-7 twin: a fifth channel row fails the count" {
  local planted
  planted="$(plant "$PLUGIN_ROOT/$CONTRACTS" '/^| an ethics decision |/a\
| a fifth thing | `made_up_field:` | `skills/shared/stage-codes.md` |')"
  run check_channels "$planted" "$PLUGIN_ROOT"
  assert_failure
}

# --- AC-8: single-sourcing across the whole prompt surface -------------------

@test "AC-8: the canonical section heading exists in exactly one file" {
  run check_single_heading "$PLUGIN_ROOT"
  assert_success
}

@test "AC-8: the sweep added no fourth copy of the escalation-class enumeration" {
  run check_no_fourth_escalation_copy "$PLUGIN_ROOT"
  assert_success
}

@test "AC-8 twin: a fourth escalation-class copy fails the count" {
  local d
  d="$(mk_tmpworkdir)"
  mkdir -p "$d/agents" "$d/commands" "$d/skills"
  cp "$PLUGIN_ROOT/commands/worktask.md" "$d/commands/"
  cp "$PLUGIN_ROOT/skills/worktask/SKILL.md" "$d/skills/"
  cp "$PLUGIN_ROOT/skills/worktask/references/pl0-procedure.md" "$d/skills/"
  cp "$PLUGIN_ROOT/agents/stakeholder.md" "$d/agents/"
  printf '\nirreversible, scope-expanding, posture-weakening, or spend-authorizing.\n' >> "$d/agents/stakeholder.md"
  run check_no_fourth_escalation_copy "$d"
  assert_failure
}

# --- AC-13: the 30-line frontmatter budget survives the wider template -------

@test "AC-13: every per-stage template yaml block stays within the 30-line budget" {
  run check_frontmatter_line_budget "$PLUGIN_ROOT/$CONTRACTS"
  assert_success
}

@test "AC-13 twin: a template block past 30 lines fails the budget check" {
  local planted
  planted="$(plant "$PLUGIN_ROOT/$CONTRACTS" '/^  stage: ST$/a\
  filler_01: x\
  filler_02: x\
  filler_03: x\
  filler_04: x\
  filler_05: x\
  filler_06: x\
  filler_07: x\
  filler_08: x\
  filler_09: x\
  filler_10: x\
  filler_11: x\
  filler_12: x\
  filler_13: x\
  filler_14: x\
  filler_15: x\
  filler_16: x\
  filler_17: x\
  filler_18: x\
  filler_19: x\
  filler_20: x\
  filler_21: x\
  filler_22: x\
  filler_23: x\
  filler_24: x\
  filler_25: x')"
  run check_frontmatter_line_budget "$planted"
  assert_failure
}

@test "AC-13: the agent-side frontmatter template lint passes for EVERY stage agent, no carve-outs" {
  local f base rc=0 checked=0
  for f in "$PLUGIN_ROOT"/agents/*.md; do
    base="$(basename "$f" .md)"
    case " $NON_STAGE_AGENTS " in *" $base "*) continue ;; esac
    # No file is skipped: a `## Handoff Protocol` section is itself part of the contract,
    # so an agent lacking one must fail here rather than be stepped over.
    checked=$((checked + 1))
    grep -q '^## Handoff Protocol[[:space:]]*$' "$f" \
      || { echo "$base.md: no '## Handoff Protocol' section"; rc=1; continue; }
    run bash "$PLUGIN_ROOT/skills/worktask/scripts/cache-lint.sh" --frontmatter-template-lint "$f"
    if [ "$status" -ne 0 ]; then echo "$base: $output"; rc=1; fi
  done
  [ "$checked" -ge 14 ] || fail "non-vacuity: only $checked stage agents checked"
  [ "$rc" -eq 0 ]
}

# --- AC-15: strict from day one, no escape hatch -----------------------------

@test "AC-15: the sweep surface carries no warn-only mode, opt-in variable, or advisory tier" {
  run check_no_escape_hatch "$PLUGIN_ROOT/$CONTRACTS"
  assert_success
}

@test "AC-15 twin: adding a warn-only arm to the canonical section fails" {
  local planted
  planted="$(plant "$PLUGIN_ROOT/$CONTRACTS" '/^### Sweep obligation matrix$/a\
A missing sweep is warn-only until the next minor.')"
  run check_no_escape_hatch "$planted"
  assert_failure
}

@test "AC-15 twin: an advisory column in the matrix fails" {
  local planted
  planted="$(plant "$PLUGIN_ROOT/$CONTRACTS" 's/^| Code | Obligation |/| Code | Advisory | Obligation |/')"
  run check_no_escape_hatch "$planted"
  assert_failure
}

@test "P2-6: the sweep-specific harness gate (check_sweep_*) carries no strict/warn-only escape hatch" {
  run check_no_sweep_escape_hatch_wide "$PLUGIN_ROOT/skills/worktask/scripts/handoff-harness.sh"
  assert_success
}

@test "P2-6 twin: gating a check_sweep_* call site behind STRICT fails the wide check" {
  local planted
  planted="$(plant "$PLUGIN_ROOT/skills/worktask/scripts/handoff-harness.sh" \
    's/if ! check_sweep_ledger "\$fmfile"; then/if [[ "\$STRICT" == "1" ]] \&\& ! check_sweep_ledger "\$fmfile"; then/')"
  run check_no_sweep_escape_hatch_wide "$planted"
  assert_failure
}

@test "P2-6 twin: an unrelated warn-only rollout elsewhere in the same file does not false-positive" {
  # The AR-reference check (§ Step B) legitimately says warn-only/--strict in this
  # same file; the widened guard must key on the sweep functions specifically.
  run bash -c "grep -q 'warn-only in 3.42.0' '$PLUGIN_ROOT/skills/worktask/scripts/handoff-harness.sh'"
  assert_success
  run check_no_sweep_escape_hatch_wide "$PLUGIN_ROOT/skills/worktask/scripts/handoff-harness.sh"
  assert_success
}

# --- orchestrator wiring: the STOP is not moved ------------------------------

@test "the sweep render precedes the FN approve/reject STOP, which stays last and unmodified" {
  local render stop
  render=$(grep -n '(c+) Render the collected sweep' "$PLUGIN_ROOT/$WORKTASK_SKILL" | head -1 | cut -d: -f1)
  stop=$(grep -n '(d) AskUserQuestion: approve' "$PLUGIN_ROOT/$WORKTASK_SKILL" | head -1 | cut -d: -f1)
  [ -n "$render" ] && [ -n "$stop" ] || fail "non-vacuity: step 4.9 sub-steps not found"
  [ "$render" -lt "$stop" ] || fail "the sweep does not precede the approve/reject call"
}

@test "both orchestrator commands declare AskUserQuestion in allowed-tools" {
  local f
  for f in commands/worktask.md commands/megatask.md; do
    grep -q 'AskUserQuestion' "$PLUGIN_ROOT/$f" || fail "$f never calls AskUserQuestion"
    grep -E '^allowed-tools:' "$PLUGIN_ROOT/$f" | grep -q 'AskUserQuestion' \
      || fail "$f calls AskUserQuestion but does not declare it"
  done
}

# --- P1-1 rework: the ledger transport has a writer, and it is checked ------

HARNESS="skills/worktask/scripts/handoff-harness.sh"
STATE_PATCH="skills/worktask/scripts/state-patch.sh"

# Every agent that shows a --facts payload must show open_questions in it: the
# frontmatter stub and facts.open_questions[] are separate transports with separate
# writers, so an example without it teaches the stage to drop its own sweep.
facts_example_agents() {  # <agents-dir> -> agent files carrying a --facts example
  grep -rl -- "state-patch.sh --stage .* --facts" "$1"/*.md 2>/dev/null | sort
}

check_facts_examples() {  # <agents-dir>
  local f n=0 rc=0 block
  for f in $(facts_example_agents "$1"); do
    n=$((n + 1))
    block="$(awk '/state-patch\.sh --stage .* --facts/{f=1} f{print} f&&/\}.$/{exit}' "$f")"
    printf '%s\n' "$block" | grep -q '"open_questions"' \
      || { echo "$(basename "$f"): --facts example omits open_questions"; rc=1; }
  done
  [ "$n" -ge 8 ] || { echo "non-vacuity: only $n --facts examples found"; return 1; }
  return $rc
}

@test "P1-1: every agent --facts example carries open_questions" {
  run check_facts_examples "$PLUGIN_ROOT/agents"
  assert_success
}

@test "P1-1 twin: an agent whose --facts example drops open_questions fails" {
  local d
  d="$(mk_tmpworkdir)"
  cp "$PLUGIN_ROOT"/agents/*.md "$d/"
  sed -i.bak '/"open_questions": \[{"id":"sw-DC0-1"/d' "$d/technical-writer.md"
  sed -i.bak2 's/"decisions": \[{"id":"dv-1","summary":"≤160 chars","ref":"development-0.md#deviations"}\],/"decisions": [{"id":"dv-1","summary":"≤160 chars","ref":"development-0.md#deviations"}]}'"'"'/' "$d/developer.md"
  run check_facts_examples "$d"
  assert_failure
}

# The harness cross-check is what makes the obligation non-memory-dependent.
sweep_fixture() {  # sweep_fixture <dir> <ref-or-empty>
  local d="$1" ref="$2"
  mkdir -p "$d"
  {
    printf -- '---\nhandoff:\n  stage: DC\n  verdict: ok\n'
    printf '  summary: "fixture"\n  files_touched: [a.md]\n'
    printf '  open_questions:\n'
    if [ -n "$ref" ]; then
      printf '    - { id: sw-DC0-1, summary: "q", class: decision, ref: "%s" }\n' "$ref"
    else
      printf '    - { id: sw-DC0-1, summary: "q", class: decision }\n'
    fi
    printf '  refs: { dev: development-0.md#files-changed }\n'
    printf -- '---\n\n# Documentation\n'
    # The anchor the stub points at: present by default so each test isolates one contract.
    if [ "${3:-with-anchor}" = "with-anchor" ]; then printf '\n## elicitation-sweep\n\nq\n'; fi
  } > "$d/documentation-0.md"
}

@test "P1-1: the harness fails a class-bearing stub that never reached facts.open_questions[]" {
  local d
  d="$(mk_tmpworkdir)"
  sweep_fixture "$d" "documentation-0.md#elicitation-sweep"
  printf '{"facts":{"open_questions":[]}}\n' > "$d/state.json"
  run bash "$PLUGIN_ROOT/$HARNESS" --validate-frontmatter "$d/documentation-0.md" --state "$d/state.json"
  assert_failure
  assert_output --partial "not in facts.open_questions[]"
}

@test "P1-1 twin: the same stub passes once it is in the ledger (the check is not unconditional)" {
  local d
  d="$(mk_tmpworkdir)"
  sweep_fixture "$d" "documentation-0.md#elicitation-sweep"
  printf '{"facts":{"open_questions":[{"id":"sw-DC0-1","summary":"q"}]}}\n' > "$d/state.json"
  run bash "$PLUGIN_ROOT/$HARNESS" --validate-frontmatter "$d/documentation-0.md" --state "$d/state.json"
  assert_success
}

@test "the class-without-ref hole fails legibly rather than as a bare schema mismatch" {
  local d
  d="$(mk_tmpworkdir)"
  sweep_fixture "$d" ""
  run bash "$PLUGIN_ROOT/$HARNESS" --validate-frontmatter "$d/documentation-0.md"
  assert_failure
  assert_output --partial "carry class but no ref"
}

# --- sw-DR0-2: the stage filter reads a field that may be absent -------------

@test "sw-DR0-2: Step C.1 derives the stage from the item id and treats an explicit stage as optional" {
  local body
  body="$(awk '/^### Step C — Closing-sweep collection/{f=1;next} f && /^#{2,3} /{f=0} f' "$PLUGIN_ROOT/$WORKTASK_CMD")"
  [ -n "$body" ] || fail "non-vacuity: Step C not found"
  printf '%s\n' "$body" | grep -q 'Derive' || fail "C.1 does not derive the stage"
  printf '%s\n' "$body" | grep -q 'sw-<TASK_ID>-<n>' || fail "C.1 does not name the id shape it parses"
  printf '%s\n' "$body" | grep -q 'takes precedence' || fail "explicit stage precedence unstated"
  # The schema must keep `stage` optional, or the derivation is pointless.
  local defs
  defs="$(sweep_stub_defs "$PLUGIN_ROOT/$HANDOFF")"
  printf '%s\n' "$defs" | grep -q 'required: \[id, class, ref\]' \
    || fail "SweepStub's required set changed; stage may have become mandatory"
}

# --- sw-DR0-3: sweep answers must not evict architectural decisions ----------

@test "sw-DR0-3: Step C.5 records answers in open_questions[].resolution, not facts.decisions[]" {
  local body
  body="$(section_body "$PLUGIN_ROOT/$WORKTASK_CMD" '^#### Step C.5')"
  [ -n "$body" ] || fail "non-vacuity: Step C.5 not found"
  printf '%s\n' "$body" | grep -q 'resolution' || fail "C.5 does not record into resolution"
  printf '%s\n' "$body" | grep -q 'do \*\*not\*\* go to' || fail "C.5 does not exclude facts.decisions[]"
  # The field it writes has to exist in the ledger schema.
  grep -q 'resolution: { type: string, maxLength: 160 }' "$PLUGIN_ROOT/$HANDOFF" \
    || fail "facts.open_questions[].resolution is not in the ledger schema"
}

# The clamp is extracted from state-patch.sh and executed, so this asserts behaviour
# rather than the presence of a line.
bounds_filter() { sed -n "/^_STATE_BOUNDS_FILTER='/,/'$/p" "$1" | sed "1s/^_STATE_BOUNDS_FILTER='//" | sed "\$s/'$//"; }

@test "sw-DR0-3: facts.open_questions is clamped, unresolved items surviving ahead of resolved ones" {
  local filter out
  filter="$(bounds_filter "$PLUGIN_ROOT/$STATE_PATCH")"
  [ -n "$filter" ] || fail "non-vacuity: bounds filter not extracted"
  printf '%s\n' "$filter" | grep -q 'open_questions' || fail "open_questions is not clamped at the chokepoint"

  # 10 resolved + 10 open: every open item survives, resolved ones are evicted first.
  local input
  input='{"facts":{"open_questions":['
  local i
  for i in 0 1 2 3 4 5 6 7 8 9; do input="${input}{\"id\":\"r$i\",\"status\":\"resolved\"},"; done
  for i in 0 1 2 3 4 5 6 7 8; do input="${input}{\"id\":\"o$i\"},"; done
  input="${input}{\"id\":\"o9\"}]}}"
  out="$(printf '%s' "$input" | jq -c "$filter" | jq -c '[.facts.open_questions[] | .id]')"
  [ "$(printf '%s' "$out" | jq 'length')" -eq 12 ] || fail "clamp did not bound the array: $out"
  printf '%s' "$out" | jq -e 'index("o0") != null and index("o9") != null' > /dev/null \
    || fail "an unresolved item was evicted while resolved ones survived: $out"
}

@test "sw-DR0-3 twin: a below-bound array is left byte-identical (no-op path holds)" {
  local filter out
  filter="$(bounds_filter "$PLUGIN_ROOT/$STATE_PATCH")"
  out="$(printf '%s' '{"facts":{"open_questions":[{"id":"a"},{"id":"b"}]}}' | jq -c "$filter")"
  [ "$out" = '{"facts":{"open_questions":[{"id":"a"},{"id":"b"}]}}' ] || fail "no-op path mutated state: $out"
}

# --- P2-7: the new anchor must not fail artifacts written before it existed --

@test "P2-7: the elicitation-sweep anchor is allowed but not required (non-retroactive)" {
  local d
  d="$(mk_tmpworkdir)"
  {
    printf -- '---\nhandoff:\n  stage: DC\n  verdict: ok\n  summary: "s"\n'
    printf '  refs: { dev: development-0.md#files-changed }\n---\n\n'
    printf '## files-changed\n\nx\n\n## cross-references\n\nx\n\n## follow-ups\n\nx\n'
  } > "$d/documentation-0.md"
  # Written before the sweep existed: no elicitation-sweep anchor at all.
  run env PATH="/usr/bin:/bin" bash "$PLUGIN_ROOT/skills/worktask/scripts/cache-lint.sh" \
    --anchor-lint "$d/documentation-0.md"
  assert_success
  # And the anchor is accepted when present, rather than reported as unexpected.
  printf '\n## elicitation-sweep\n\nnothing to elicit\n' >> "$d/documentation-0.md"
  run env PATH="/usr/bin:/bin" bash "$PLUGIN_ROOT/skills/worktask/scripts/cache-lint.sh" \
    --anchor-lint "$d/documentation-0.md"
  assert_success
  # rework-<N> rides the same allowance: agents/technical-lead.md reads it at the DR gate,
  # and anchor-lint used to reject the very section its own contract asks for.
  printf '\n## rework-1\n\nx\n' >> "$d/documentation-0.md"
  run env PATH="/usr/bin:/bin" bash "$PLUGIN_ROOT/skills/worktask/scripts/cache-lint.sh" \
    --anchor-lint "$d/documentation-0.md"
  assert_success
}

@test "P2-7 twin: a genuinely unknown anchor is still rejected (the allowance is scoped)" {
  local d
  d="$(mk_tmpworkdir)"
  {
    printf -- '---\nhandoff:\n  stage: DC\n  verdict: ok\n  summary: "s"\n'
    printf '  refs: { dev: development-0.md#files-changed }\n---\n\n'
    printf '## files-changed\n\nx\n\n## cross-references\n\nx\n\n## follow-ups\n\nx\n'
    printf '\n## not-an-anchor\n\nx\n'
  } > "$d/documentation-0.md"
  run env PATH="/usr/bin:/bin" bash "$PLUGIN_ROOT/skills/worktask/scripts/cache-lint.sh" \
    --anchor-lint "$d/documentation-0.md"
  assert_failure
}

# --- sw-DR0-5 / sw-DV0-5: the ref anchor is the only transport of options[] ---

@test "sw-DV0-5: a stub whose ref anchor does not exist fails, naming the dangling anchor" {
  local d
  d="$(mk_tmpworkdir)"
  # Same stub, same well-formed ref — but no `## elicitation-sweep` heading to resolve to.
  sweep_fixture "$d" "documentation-0.md#elicitation-sweep" no-anchor
  run bash "$PLUGIN_ROOT/$HARNESS" --validate-frontmatter "$d/documentation-0.md"
  assert_failure
  assert_output --partial "dangling"
}

@test "sw-DV0-5 twin: the identical stub passes once the anchor exists (the check is not unconditional)" {
  local d
  d="$(mk_tmpworkdir)"
  sweep_fixture "$d" "documentation-0.md#elicitation-sweep"
  run bash "$PLUGIN_ROOT/$HARNESS" --validate-frontmatter "$d/documentation-0.md"
  assert_success
}

@test "sw-DV0-5: a ref naming a file that does not exist fails" {
  local d
  d="$(mk_tmpworkdir)"
  sweep_fixture "$d" "no-such-artifact-0.md#elicitation-sweep"
  run bash "$PLUGIN_ROOT/$HARNESS" --validate-frontmatter "$d/documentation-0.md"
  assert_failure
  assert_output --partial "does not exist"
}

@test "sw-DV0-5: the anchor check is non-retroactive — a legacy artifact with no class-bearing stub passes" {
  local d
  d="$(mk_tmpworkdir)"
  {
    printf -- '---\nhandoff:\n  stage: DC\n  verdict: ok\n  summary: "legacy"\n'
    printf '  files_touched: [a.md]\n'
    printf '  open_questions:\n'
    printf '    - "q1: legacy free-text form"\n'
    printf '    - { id: q2, summary: "legacy bare object" }\n'
    printf '  refs: { dev: development-0.md#files-changed }\n'
    printf -- '---\n\n# Documentation\n'
  } > "$d/documentation-0.md"
  run bash "$PLUGIN_ROOT/$HARNESS" --validate-frontmatter "$d/documentation-0.md"
  assert_success
}

@test "sw-DV0-5: no warn arm — the dangling-anchor path fails rather than warning (REQ-10)" {
  local d
  d="$(mk_tmpworkdir)"
  sweep_fixture "$d" "documentation-0.md#elicitation-sweep" no-anchor
  run bash "$PLUGIN_ROOT/$HARNESS" --validate-frontmatter "$d/documentation-0.md"
  [ "$status" -ne 0 ] || fail "non-vacuity: the fixture did not exercise the check at all"
  printf '%s\n' "$output" | grep -q '^warn:' && fail "the sweep surface degraded to a warning"
  printf '%s\n' "$output" | grep -q '^fail:' || fail "expected a fail: line, got: $output"
}

# --- sw-DV0-4 (USER: keep 12, resolved-first): pin the ORDERING, not just the count ---

@test "sw-DV0-4: eviction prefers resolved items — every unresolved item outlives every resolved one" {
  local filter input out i
  filter="$(bounds_filter "$PLUGIN_ROOT/$STATE_PATCH")"
  [ -n "$filter" ] || fail "non-vacuity: bounds filter not extracted"

  # 11 unresolved + 11 resolved, interleaved so position alone cannot produce the answer.
  input='{"facts":{"open_questions":['
  for i in 0 1 2 3 4 5 6 7 8 9 10; do
    input="${input}{\"id\":\"o$i\",\"status\":\"open\"},{\"id\":\"r$i\",\"status\":\"resolved\"},"
  done
  input="${input%,}]}}"
  out="$(printf '%s' "$input" | jq -c "$filter" | jq -c '[.facts.open_questions[]]')"

  [ "$(printf '%s' "$out" | jq 'length')" -eq 12 ] || fail "bound not applied: $out"
  # Every unresolved item survives; the single surviving spare is a resolved one.
  [ "$(printf '%s' "$out" | jq '[.[] | select(.status == "open")] | length')" -eq 11 ] \
    || fail "an unresolved item was evicted while resolved ones survived: $out"
  [ "$(printf '%s' "$out" | jq '[.[] | select(.status == "resolved")] | length')" -eq 1 ] \
    || fail "resolved items were not evicted first: $out"
}

@test "sw-DV0-4: the bound is documented as a deliberate choice with its eviction preference" {
  local body
  # Read the whole H4 subtree: the rationale lives in its H5 child, and section_body
  # (leaf semantics, matching section-lint) would stop at that child's heading.
  body="$(awk '/^#### Ledger bounds/{f=1;next} f && /^#{2,4} /{f=0} f' "$PLUGIN_ROOT/$CONTRACTS")"
  [ -n "$body" ] || fail "non-vacuity: the Ledger bounds section is absent"
  printf '%s\n' "$body" | grep -q '12' || fail "the bound is not stated"
  printf '%s\n' "$body" | grep -qi 'resolved' || fail "the eviction preference is not stated"
  printf '%s\n' "$body" | grep -qi 'deliberate' || fail "the bound does not read as a decision anyone made"
}

# --- q10: the stub sheds `summary`, and the disjointness guard must survive it ---

# SweepStub spans two fenced blocks since the routing/answer fields were split out for the
# section cap; read from its definition to the end of that H4 subtree, not to the first fence.
sweep_stub_defs() {
  awk '/^#### \$defs — SweepStub/{f=1;next} f && /^#{2,4} /{f=0} f' "$1"
}

@test "q10: SweepStub requires only [id, class, ref]" {
  local defs
  defs="$(sweep_stub_defs "$PLUGIN_ROOT/$HANDOFF")"
  [ -n "$defs" ] || fail "non-vacuity: SweepStub not extracted"
  printf '%s\n' "$defs" | grep -q 'required: \[id, class, ref\]' \
    || fail "SweepStub's required set is not [id, class, ref]: $defs"
  printf '%s\n' "$defs" | grep -q 'summary:' \
    || fail "summary was removed entirely; it must stay legal-but-optional"
}

@test "q10 TRAP: summary is not a second discriminator — the not:{required:[class]} guard survives" {
  # {id, summary, class, ref} matches branch 2 AND branch 3 unless the guard fires, which
  # is why shortening `required` does not make the guard redundant. Both halves asserted.
  local blk
  blk="$(open_questions_schema "$PLUGIN_ROOT/$HANDOFF")"
  printf '%s\n' "$blk" | grep -qE '^ *not: \{ required: \[class\] \}' \
    || fail "the disjointness guard was dropped as redundant after q10 — it is not"
  # And the reasoning is written down where the next reader will look.
  grep -q 'why the .not. guard survives q10' "$PLUGIN_ROOT/$HANDOFF" \
    || fail "nothing records why the guard is still load-bearing after q10"
}

@test "q10 twin: a stub schema that keeps summary required fails the check" {
  local planted
  planted="$(plant "$PLUGIN_ROOT/$HANDOFF" 's/required: \[id, class, ref\]/required: [id, summary, class, ref]/')"
  run bash -c "awk '/^  SweepStub:\$/{f=1} f{print} f&&/^\`\`\`\$/{exit}' '$planted' | grep -q 'required: \[id, class, ref\]'"
  assert_failure
}

@test "q10: the 200-token budget is stated as a property of the whole handoff block" {
  local body
  body="$(awk '/^#### The stub carries no summary/{f=1;next} f && /^#{2,4} /{f=0} f' "$PLUGIN_ROOT/$CONTRACTS")"
  [ -n "$body" ] || fail "non-vacuity: the stub-shortening rationale section is absent"
  printf '%s\n' "$body" | grep -q '200-token' || fail "the driver budget is not named"
  printf '%s\n' "$body" | grep -qi 'whole .handoff:. block\|property of the block' \
    || fail "the budget is described as the sweep's, not the block's"
}

@test "q10: no per-stage template still carries summary in its sweep stub" {
  local hits
  hits="$(grep -c 'id: sw-[A-Z][A-Z]0-1, summary:' "$PLUGIN_ROOT/$CONTRACTS" || true)"
  [ "$hits" -eq 0 ] || fail "$hits templates still put summary in the stub"
  [ "$(grep -c 'id: sw-[A-Z][A-Z]0-1, class: decision, ref:' "$PLUGIN_ROOT/$CONTRACTS")" -ge 13 ] \
    || fail "non-vacuity: shortened stubs not found in the templates"
}

# --- q8 / sw-DR0-4: no downgrade of status or resolution, in BOTH transports ---

union_filter() { sed -n "/^_FACTS_UNION_FILTER='/,/'\$/p" "$1" | sed "1s/^_FACTS_UNION_FILTER='//" | sed "\$s/'\$//"; }

@test "q8 union: a re-emitted open stub cannot downgrade a recorded resolution" {
  local filter out
  filter="$(union_filter "$PLUGIN_ROOT/$STATE_PATCH")"
  [ -n "$filter" ] || fail "non-vacuity: union filter not extracted"
  out="$(printf '%s' '{"facts":{"open_questions":[{"id":"sw-DV0-1","status":"resolved","resolution":"answered"}]}}' \
        | jq -c --argjson f '{"open_questions":[{"id":"sw-DV0-1","class":"decision","ref":"a.md#x"}]}' "$filter")"
  printf '%s' "$out" | jq -e '.facts.open_questions[0].status == "resolved"' > /dev/null \
    || fail "the downgrade was accepted: $out"
  printf '%s' "$out" | jq -e '.facts.open_questions[0].resolution == "answered"' > /dev/null \
    || fail "the recorded answer was lost: $out"
}

@test "q8 union: raising open to resolved is honoured (the join is monotone, not frozen)" {
  local filter out
  filter="$(union_filter "$PLUGIN_ROOT/$STATE_PATCH")"
  out="$(printf '%s' '{"facts":{"open_questions":[{"id":"sw-DV0-1","status":"open"}]}}' \
        | jq -c --argjson f '{"open_questions":[{"id":"sw-DV0-1","status":"resolved","resolution":"now answered"}]}' "$filter")"
  printf '%s' "$out" | jq -e '.facts.open_questions[0].resolution == "now answered"' > /dev/null \
    || fail "a genuine answer was refused: $out"
}

@test "q8 union: an incoming stub that omits resolution inherits it, even when both say resolved" {
  # Found live: patching a stub with status:resolved but no body wiped three recorded answers.
  # Status and resolution are guarded independently — dropping the body is a downgrade too.
  local filter out
  filter="$(union_filter "$PLUGIN_ROOT/$STATE_PATCH")"
  out="$(printf '%s' '{"facts":{"open_questions":[{"id":"x","status":"resolved","resolution":"the answer"}]}}' \
        | jq -c --argjson f '{"open_questions":[{"id":"x","status":"resolved"}]}' "$filter")"
  printf '%s' "$out" | jq -e '.facts.open_questions[0].resolution == "the answer"' > /dev/null \
    || fail "the recorded answer was dropped by a resolution-less re-emit: $out"
}

@test "q8 union: a genuinely new resolution still replaces the old one (guarded, not frozen)" {
  local filter out
  filter="$(union_filter "$PLUGIN_ROOT/$STATE_PATCH")"
  out="$(printf '%s' '{"facts":{"open_questions":[{"id":"x","status":"resolved","resolution":"old"}]}}' \
        | jq -c --argjson f '{"open_questions":[{"id":"x","status":"resolved","resolution":"new"}]}' "$filter")"
  printf '%s' "$out" | jq -e '.facts.open_questions[0].resolution == "new"' > /dev/null \
    || fail "the field was frozen rather than guarded: $out"
}

@test "q8 union: scoped to open_questions — facts.decisions keeps last-writer-wins" {
  local filter out
  filter="$(union_filter "$PLUGIN_ROOT/$STATE_PATCH")"
  printf '%s\n' "$filter" | grep -q '_union_keyed(.id)' \
    || fail "the shared keyed union was removed; facts.decisions semantics changed"
  out="$(printf '%s' '{"facts":{"decisions":[{"id":"d1","summary":"old"}]}}' \
        | jq -c --argjson f '{"decisions":[{"id":"d1","summary":"new"}]}' "$filter")"
  printf '%s' "$out" | jq -e '.facts.decisions[0].summary == "new"' > /dev/null \
    || fail "decisions no longer take the last writer: $out"
}

@test "q8 union: a legacy entry merges byte-identically (no null status/resolution keys)" {
  local filter out
  filter="$(union_filter "$PLUGIN_ROOT/$STATE_PATCH")"
  out="$(printf '%s' '{"facts":{"open_questions":[{"id":"q1","summary":"legacy"}]}}' \
        | jq -c --argjson f '{"open_questions":[{"id":"q1","summary":"legacy"}]}' "$filter")"
  [ "$out" = '{"facts":{"open_questions":[{"id":"q1","summary":"legacy"}]}}' ] \
    || fail "the union mutated a legacy entry: $out"
}

@test "q8 artifact side: § Item shape requires a re-emitted stub to carry its answer forward" {
  local body
  body="$(awk '/^#### A re-emitted stub carries its answer forward/{f=1;next} f && /^#{2,4} /{f=0} f' "$PLUGIN_ROOT/$CONTRACTS")"
  [ -n "$body" ] || fail "non-vacuity: the carry-forward rule is absent from the canonical section"
  printf '%s\n' "$body" | grep -q 'status' || fail "carry-forward does not name status"
  printf '%s\n' "$body" | grep -q 'resolution' || fail "carry-forward does not name resolution"
  # The reason the artifact arm exists at all: it outlives ledger eviction.
  printf '%s\n' "$body" | grep -qi 'eviction' \
    || fail "the artifact arm's rationale (it survives ledger eviction) is unstated"
}

# --- q9 / sw-DR0-5: blocking items surface at their own boundary --------------

@test "q9: blocks_next_stage exists on the stub and is optional (class stays the discriminator)" {
  local defs
  defs="$(sweep_stub_defs "$PLUGIN_ROOT/$HANDOFF")"
  printf '%s\n' "$defs" | grep -q 'blocks_next_stage' || fail "the q9 carrier is absent from SweepStub"
  printf '%s\n' "$defs" | grep -q 'required: \[id, class, ref\]' \
    || fail "blocks_next_stage leaked into required[]; it must be additive"
}

@test "q9: the canonical section no longer claims no stage boundary gains a round-trip" {
  local body
  body="$(awk '/^## Closing Elicitation Sweep/{f=1;next} /^## Per-Stage/{f=0} f' "$PLUGIN_ROOT/$CONTRACTS")"
  [ -n "$body" ] || fail "non-vacuity: canonical section not extracted"
  printf '%s\n' "$body" | grep -q 'no stage boundary gains a round-trip' \
    && fail "the section still asserts a claim q9 made false"
  printf '%s\n' "$body" | grep -q 'No new gate is created' \
    || fail "the surviving half of the claim (no new gate) was dropped too"
}

@test "q9: both destinations are documented, selected per item rather than per stage" {
  local body
  body="$(awk '/^#### Where an item is answered/{f=1;next} f && /^#{2,4} /{f=0} f' "$PLUGIN_ROOT/$CONTRACTS")"
  [ -n "$body" ] || fail "non-vacuity: § Where an item is answered is absent"
  printf '%s\n' "$body" | grep -q 'blocks_next_stage' || fail "the selector is not named"
  printf '%s\n' "$body" | grep -qi 'never by stage' || fail "per-item selection is not stated"
}

@test "q9: Step C.0 renders blocking items at their own boundary, with a per-boundary subject" {
  grep -q '^#### Step C.0 — blocking items, at their own boundary' "$PLUGIN_ROOT/$WORKTASK_CMD" \
    || fail "Step C.0 is absent"
  local body
  body="$(awk '/^#### Step C.0 — blocking/{f=1;next} f && /^#{2,4} /{f=0} f' "$PLUGIN_ROOT/$WORKTASK_CMD")"
  printf '%s\n' "$body" | grep -q 'subject:"<CODE><N>"' || fail "C.0 does not scope its audit subject to the boundary"
  printf '%s\n' "$body" | grep -qi 'no-op' || fail "the common (no blocking items) path is unstated"
  grep -q 'Step 6.6' "$PLUGIN_ROOT/$WORKTASK_SKILL" || fail "the loop has no step for the blocking render"
}

@test "q9: Step C.1's filter is status-based, and explicitly not stage-based" {
  local body
  body="$(awk '/^#### Step C.1 — collect/{f=1;next} f && /^#{2,4} /{f=0} f' "$PLUGIN_ROOT/$WORKTASK_CMD")"
  [ -n "$body" ] || fail "non-vacuity: Step C.1 not found"
  printf '%s\n' "$body" | grep -q 'stage != "PL"' && fail "the stage-name exclusion survived q9"
  printf '%s\n' "$body" | grep -qi 'not.. filter on stage' || fail "C.1 does not forbid a stage filter"
  # sw-DR0-2's id-derivation is retained for grouping rather than deleted silently.
  printf '%s\n' "$body" | grep -qi 'grouping' || fail "id-derivation's surviving purpose is unstated"
}

@test "q9: the obligation matrix Surfaced-by column is conditional, and AC-1 still passes" {
  grep -q 'Surfaced by (non-blocking / blocking)' "$PLUGIN_ROOT/$CONTRACTS" \
    || fail "the Surfaced by column was not made conditional"
  # AC-1 reads the code column only, so it must be unaffected by the column rename.
  run check_matrix_completeness "$PLUGIN_ROOT/$CONTRACTS" "$PLUGIN_ROOT/$STAGE_CODES" "$PLUGIN_ROOT/$HANDOFF"
  assert_success
}

@test "q9: the raise-only guard covers the blocking axis by OR, and keeps the axes orthogonal" {
  local body
  body="$(awk '/^###### Escalation guard — the blocking axis/{f=1;next} f && /^#{2,6} /{f=0} f' "$PLUGIN_ROOT/$WORKTASK_CMD")"
  [ -n "$body" ] || fail "non-vacuity: the blocking-axis guard is absent"
  printf '%s\n' "$body" | grep -q 'OR' || fail "the join is not stated as OR"
  printf '%s\n' "$body" | grep -qi 'never clear' || fail "raise-only is not stated for the blocking axis"
  printf '%s\n' "$body" | grep -qi 'orthogonal' || fail "orthogonality with class is unstated"
}

@test "q9: agent-coordination's checkpoint clause survives its third reconciliation" {
  local f body
  f="$PLUGIN_ROOT/skills/agent-coordination/SKILL.md"
  body="$(awk '/^### Gate prompts \(AskUserQuestion\)/{f=1;next} f && /^#{2,4} /{f=0} f' "$f")"
  [ -n "$body" ] || fail "non-vacuity: the gate-prompts section is absent"
  printf '%s\n' "$body" | grep -q 'the one such checkpoint' && fail "the original wrong count came back"
  printf '%s\n' "$body" | grep -q 'blocks_next_stage' \
    || fail "the clause does not account for the boundary render q9 introduced"
  printf '%s\n' "$body" | grep -qi 'not a gate' \
    || fail "the boundary render is not distinguished from a gate"
}

@test "q9: the megatask park subject is per-boundary, not FN-scoped" {
  local f
  f="$PLUGIN_ROOT/skills/megatask/SKILL.md"
  grep -q 'subject:"FN<N>". instead of' "$f" && fail "the park path is still FN-scoped"
  grep -q 'CODE><N>' "$f" || fail "the park path names no per-boundary subject"
}

# --- P2-13 / P2-14 -----------------------------------------------------------

@test "P2-13: the \$defs injector is stated as an obligation, not attributed to a section that lacks it" {
  local note
  note="$(grep -n 'inline that .\$defs. block' "$PLUGIN_ROOT/$HANDOFF" || true)"
  [ -n "$note" ] || fail "non-vacuity: the \$defs obligation sentence is absent"
  # The previous text cited SKILL.md Step 6, which carries no such claim. Verify both:
  # the citation is gone, and the file it named still does not carry the claim.
  grep -q 'Orchestrator Execution Loop. Step 6, so the item shape' "$PLUGIN_ROOT/$HANDOFF" \
    && fail "the misattributed citation is still present"
  grep -q 'SweepItem' "$PLUGIN_ROOT/$WORKTASK_SKILL" \
    && fail "SKILL.md now mentions SweepItem — re-check whether the citation should be restored"
  grep -q 'no shipped file implements that step today' "$PLUGIN_ROOT/$HANDOFF" \
    || fail "the unimplemented status is not stated"
}

@test "P2-14: a re-review section is an allowed anchor, like rework-<N>" {
  local d
  d="$(mk_tmpworkdir)"
  {
    printf -- '---\nhandoff:\n  stage: DR\n  verdict: pass\n  summary: "s"\n'
    printf '  refs: { dev: development-0.md#files-changed }\n---\n\n'
    printf '## findings\n\nx\n\n## verdict\n\npass\n\n## blockers\n\nnone\n\n## follow-ups\n\nx\n'
    printf '\n## re-review\n\nsecond pass\n'
  } > "$d/developer-review-0.md"
  run env PATH="/usr/bin:/bin" bash "$PLUGIN_ROOT/skills/worktask/scripts/cache-lint.sh" \
    --anchor-lint "$d/developer-review-0.md"
  assert_success
}

@test "P2-14 twin: the allowance is still scoped — an invented anchor is rejected" {
  local d
  d="$(mk_tmpworkdir)"
  {
    printf -- '---\nhandoff:\n  stage: DR\n  verdict: pass\n  summary: "s"\n'
    printf '  refs: { dev: development-0.md#files-changed }\n---\n\n'
    printf '## findings\n\nx\n\n## verdict\n\npass\n\n## blockers\n\nnone\n\n## follow-ups\n\nx\n'
    printf '\n## re-re-review\n\nnope\n'
  } > "$d/developer-review-0.md"
  run env PATH="/usr/bin:/bin" bash "$PLUGIN_ROOT/skills/worktask/scripts/cache-lint.sh" \
    --anchor-lint "$d/developer-review-0.md"
  assert_failure
}
