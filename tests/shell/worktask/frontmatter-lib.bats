#!/usr/bin/env bats
# frontmatter-lib.sh — the one reader of a stage artifact's `handoff:` block, shared by
# handoff-harness.sh (the boundary gate) and state-patch.sh (the ledger writer).
#
# The load-bearing block is the parity section: the two tools previously disagreed about
# what a valid artifact looked like, so a flat-shaped artifact was UNREADABLE to the harness
# and still wrote a healthy ledger row. Testing the library alone would not catch a
# regression where one consumer stops calling it, so both verdicts are compared per case.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

LIB="skills/worktask/scripts/frontmatter-lib.sh"
HARNESS="skills/worktask/scripts/handoff-harness.sh"
PATCH="skills/worktask/scripts/state-patch.sh"

setup() {
  WD="$(mk_tmpworkdir)"
  mkdir -p "$WD/.context/logs"
  printf '%s\n' '{"version":2,"worktask_id":"wt-fm","run_index":0,"tasks":{"DV0":{"status":"in_progress"}},"facts":{}}' \
    > "$WD/.context/state.json"
}

# A DV artifact whose frontmatter is either nested under `handoff:` or flat.
_artifact() {  # <path> <nested|flat>
  local pad="  " lead="handoff:"
  if [ "$2" = "flat" ]; then pad=""; lead=""; fi
  {
    printf -- '---\n'
    [ -n "$lead" ] && printf '%s\n' "$lead"
    printf '%sstage: DV\n' "$pad"
    printf '%sverdict: ok\n' "$pad"
    printf '%ssummary: "shape fixture"\n' "$pad"
    printf '%stests_executed: 12\n' "$pad"
    printf '%sfiles_touched: [a.md]\n' "$pad"
    printf '%snext_stage_focus: "DR reviews"\n' "$pad"
    printf '%sopen_questions: []\n' "$pad"
    printf '%srefs:\n' "$pad"
    printf '%s  dev: development-0.md#files-changed\n' "$pad"
    printf -- '---\n\n# Development\n\n## elicitation-sweep\n\nnothing to ask\n'
  } > "$1"
}

# --- the library's own contract ---------------------------------------------------------

@test "guard: executing the library directly is refused" {
  run bash "$PLUGIN_ROOT/$LIB"
  [ "$status" -eq 2 ]
  [[ "$output" == *"source it, do not execute it directly"* ]]
}

@test "guard: a double source is a no-op, not a redefinition" {
  run bash -c ". '$PLUGIN_ROOT/$LIB'; . '$PLUGIN_ROOT/$LIB'; echo ok"
  assert_success
  assert_output "ok"
}

@test "block: extraction stops at the CLOSING fence, not at a later body ---" {
  local a="$WD/a.md"
  printf -- '---\nhandoff:\n  stage: DV\n---\n\n# Body\n\n---\n\nnot frontmatter\n' > "$a"
  run bash -c ". '$PLUGIN_ROOT/$LIB'; corpflow_fm_block '$a'"
  assert_success
  [[ "$output" != *"not frontmatter"* ]] || fail "extractor ran past the closing fence: $output"
}

@test "block: an artifact with no frontmatter is rc 1 and silent" {
  local a="$WD/a.md"
  printf '# Just a heading\n' > "$a"
  run bash -c ". '$PLUGIN_ROOT/$LIB'; corpflow_fm_block '$a'"
  assert_failure
  [ -z "$output" ]
}

@test "field: a literal false is returned, never swallowed as absent" {
  # yq's `//` treats false as falsy. Using it here would turn a legitimate `false` into the
  # default, which is how a boolean contract field silently reads as unset.
  local fm="$WD/fm.yml"
  printf 'handoff:\n  stage: DV\n  test_suite_compiles: false\n' > "$fm"
  run bash -c ". '$PLUGIN_ROOT/$LIB'; corpflow_fm_field '$fm' test_suite_compiles MISSING"
  assert_success
  assert_output "false"
}

@test "field: a flat top-level key is NOT read as a handoff field" {
  # The whole correction: the old awk matcher was indentation-agnostic, so a flat artifact
  # yielded a stage and wrote a ledger row.
  local fm="$WD/fm.yml"
  printf 'stage: DV\nverdict: ok\n' > "$fm"
  run bash -c ". '$PLUGIN_ROOT/$LIB'; corpflow_fm_field '$fm' stage EMPTY"
  assert_success
  assert_output "EMPTY"
}

@test "has_handoff: present nested, absent flat" {
  local fm="$WD/fm.yml"
  printf 'handoff:\n  stage: DV\n' > "$fm"
  run bash -c ". '$PLUGIN_ROOT/$LIB'; corpflow_fm_has_handoff '$fm'"
  assert_success
  printf 'stage: DV\n' > "$fm"
  run bash -c ". '$PLUGIN_ROOT/$LIB'; corpflow_fm_has_handoff '$fm'"
  assert_failure
}

# --- parity: the two consumers must agree, which is the finding this closes --------------

@test "parity: a NESTED artifact is accepted by both tools" {
  cd "$WD"
  _artifact "$WD/.context/development-0.md" nested

  run bash "$PLUGIN_ROOT/$HARNESS" --validate-frontmatter .context/development-0.md
  assert_success

  run bash "$PLUGIN_ROOT/$PATCH" --stage DV --artifact .context/development-0.md
  assert_success
  run jq -r '.tasks.DV0.status' .context/state.json
  assert_output "completed"
}

@test "parity: a FLAT artifact is rejected by both tools (F-05)" {
  # Before the shared reader this artifact failed the harness and still wrote a healthy
  # ledger row — a stage passing its own bookkeeping while failing its boundary, with
  # nothing connecting the two.
  cd "$WD"
  _artifact "$WD/.context/development-0.md" flat

  run bash "$PLUGIN_ROOT/$HARNESS" --validate-frontmatter .context/development-0.md
  assert_failure

  run bash "$PLUGIN_ROOT/$PATCH" --stage DV --artifact .context/development-0.md
  assert_failure
  # And it wrote nothing: a refused shape must not half-land.
  run jq -r '.tasks.DV0.status' .context/state.json
  assert_output "in_progress"
}

@test "parity: an artifact with NO frontmatter keeps state-patch's F3 fallback" {
  # A missing block and a malformed block are different failures. Only the second is a
  # shape defect; F3 exists for the first and is deliberately unchanged.
  cd "$WD"
  printf '# Development\n\nno frontmatter here\n' > "$WD/.context/development-0.md"

  run bash "$PLUGIN_ROOT/$HARNESS" --validate-frontmatter .context/development-0.md
  assert_failure

  run bash "$PLUGIN_ROOT/$PATCH" --stage DV --artifact .context/development-0.md
  assert_success
  run jq -r '.tasks.DV0.status' .context/state.json
  assert_output "completed"
}

@test "parity: both consumers actually bind to the library, not to a private copy" {
  # Non-vacuity for every case above: a consumer that stopped sourcing the library would
  # still pass them by reimplementing the same behaviour, and drift again from there.
  run grep -c 'frontmatter-lib.sh' "$PLUGIN_ROOT/$HARNESS"
  assert_success
  [ "$output" -ge 1 ] || fail "handoff-harness.sh does not reference the library"
  run grep -c 'frontmatter-lib.sh' "$PLUGIN_ROOT/$PATCH"
  assert_success
  [ "$output" -ge 1 ] || fail "state-patch.sh does not reference the library"
  run grep -c 'corpflow_fm_has_handoff' "$PLUGIN_ROOT/$HARNESS"
  assert_success
  [ "$output" -ge 1 ] || fail "handoff-harness.sh does not call the shared shape gate"
  run grep -c 'corpflow_fm_has_handoff' "$PLUGIN_ROOT/$PATCH"
  assert_success
  [ "$output" -ge 1 ] || fail "state-patch.sh does not call the shared shape gate"
}
