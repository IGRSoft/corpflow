#!/usr/bin/env bats
# effort-ladder.sh — the effort tier ladder and the Step C.0a resolver's tier/model clamp.
#
# The load-bearing block is the parity check against model-selection.md: the library is the
# executable copy of a ladder whose canonical statement is prose, and only a comparison of
# the two catches a rung added on one side alone.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

LIB="skills/worktask/scripts/effort-ladder.sh"
MODEL_SELECTION="skills/shared/model-selection.md"
STATE_LEDGER="skills/shared/state-ledger.md"
STAGE_CODES="skills/shared/stage-codes.md"

# Every assertion sources the library; this keeps the boilerplate in one place.
ladder() { # <shell body>
  bash -c "set -euo pipefail; . '$PLUGIN_ROOT/$LIB'; $1"
}

# --- library authoring rules -------------------------------------------------

@test "the library defines its three constants" {
  run ladder "printf '%s|%s|%s' \"\$EFFORT_ENUM\" \"\$EFFORT_NON_OPUS_CEILING\" \"\$EFFORT_OPUS_FAMILY_RE\""
  assert_success
  assert_output 'low medium high xhigh max|high|^(opus|fable)$'
}

@test "executing the library directly is refused" {
  run bash "$PLUGIN_ROOT/$LIB"
  assert_failure 2
  assert_output --partial "source it, do not execute it directly"
}

@test "a double source is a no-op, not a re-assignment failure" {
  run ladder ". '$PLUGIN_ROOT/$LIB'; printf ok"
  assert_success
  assert_output "ok"
}

# --- the ladder --------------------------------------------------------------

@test "effort_plus_one walks every rung" {
  run ladder 'for e in low medium high xhigh; do printf "%s " "$(effort_plus_one $e)"; done'
  assert_success
  assert_output "medium high xhigh max "
}

@test "effort_plus_one saturates at max rather than erroring" {
  run ladder 'effort_plus_one max'
  assert_success
  assert_output "max"
}

@test "effort_plus_one refuses a tier that is not on the ladder" {
  run ladder 'effort_plus_one ultra'
  assert_failure 2
  assert_output ""
}

@test "an empty effort is refused, never silently treated as low" {
  run ladder 'effort_plus_one ""'
  assert_failure 2
  assert_output ""
}

@test "the ladder survives a caller's non-default IFS" {
  # state-patch.sh runs under IFS=$'\n\t'. A bare `for t in $EFFORT_ENUM` there splits into
  # ONE word, so every tier reads as off-ladder and every stamped effort is rejected — which
  # is exactly how this shipped the first time.
  run bash -c "set -euo pipefail
    IFS=\$'\\n\\t'
    . '$PLUGIN_ROOT/$LIB'
    printf '%s %s %s' \"\$(effort_plus_one high)\" \"\$(effort_rank max)\" \
      \"\$(effort_for_resolver high sonnet)\""
  assert_success
  assert_output "xhigh 4 high"
}

@test "effort_rank orders the ladder ascending" {
  run ladder 'for e in low medium high xhigh max; do printf "%s" "$(effort_rank $e)"; done'
  assert_success
  assert_output "01234"
}

# --- the tier/model clamp ----------------------------------------------------
#
# xhigh requires Opus 5 or Fable 5; Sonnet silently downgrades the thinking budget rather
# than failing. The clamp is what keeps a resolver from running two rungs below what its
# audit row claims.

@test "opus carries every bumped rung uncapped" {
  run ladder 'printf "%s %s %s" "$(effort_for_resolver high opus)" \
    "$(effort_for_resolver xhigh opus)" "$(effort_for_resolver max opus)"'
  assert_success
  assert_output "xhigh max max"
}

@test "fable is opus-family for clamp purposes" {
  run ladder 'effort_for_resolver xhigh fable'
  assert_success
  assert_output "max"
}

@test "sonnet at high clamps to high instead of dispatching an evaporating xhigh" {
  run ladder 'effort_for_resolver high sonnet'
  assert_success
  assert_output "high"
}

@test "the clamp lowers only — a sonnet stage below the ceiling still gets its bump" {
  run ladder 'printf "%s %s" "$(effort_for_resolver low sonnet)" \
    "$(effort_for_resolver medium sonnet)"'
  assert_success
  assert_output "medium high"
}

@test "haiku is clamped on the same ceiling as sonnet" {
  run ladder 'printf "%s %s" "$(effort_for_resolver low haiku)" \
    "$(effort_for_resolver high haiku)"'
  assert_success
  assert_output "medium high"
}

@test "an unrecognized model alias clamps rather than assuming opus" {
  # The safe direction: a full model id or a typo must not buy an uncarryable tier.
  run ladder 'effort_for_resolver high claude-opus-5'
  assert_success
  assert_output "high"
}

@test "effort_for_resolver propagates an off-ladder tier as a failure" {
  run ladder 'effort_for_resolver ultra opus'
  assert_failure 2
}

# --- parity with the prose and frontmatter that own these values -------------

# Both stage-codes.md tables, normalized to `agent<TAB>model<TAB>effort`. They carry
# DIFFERENT column orders (Primary: Stage,Agent,Model,Effort — Support: Agent,Model,Effort,
# InvokedBy), so the header line selects the mapping. A single column-index guess reads the
# Support table's Model column as an agent name and passes vacuously.
stage_table_rows() {
  awk -F'|' '
    # A table ends at the first non-table line; without this reset the mapping leaks into
    # every later `| XX |` table in the file (the artifact map matched, silently).
    !/^\|/ { t = 0 }
    /^\| Code \| Stage \| Agent \| Model \| Effort \|/ { t = 1; next }
    /^\| Code \| Agent \| Model \| Effort \| Invoked By \|/ { t = 2; next }
    t && /^\| [A-Z][A-Z] \|/ {
      for (i = 1; i <= NF; i++) gsub(/^ +| +$/, "", $i)
      if (t == 1) print $4 "\t" $5 "\t" $6
      else if (t == 2) print $3 "\t" $4 "\t" $5
    }
  ' "$PLUGIN_ROOT/$STAGE_CODES" | sort -u
}

# The value the agent actually ships, for one frontmatter key.
agent_frontmatter() { # <agent> <key>
  awk -v k="^$2:" '/^---$/ { n++ } n == 1 && $0 ~ k { print $2; exit }' \
    "$PLUGIN_ROOT/agents/$1.md"
}

@test "the extractor sees both stage-codes tables and nothing else" {
  # Guards the guard twice over: a column-order change that empties either table would make
  # every parity assertion below pass without comparing anything, and a missing table-scope
  # reset pulls in unrelated `| XX |` tables whose columns are not agents at all.
  run stage_table_rows
  assert_success
  assert_line "developer	opus	high"        # Primary Stages mapping
  assert_line "workflow-engineer	sonnet	medium"  # Support Agents mapping
  [ "${#lines[@]}" -eq 16 ]
}

@test "every effort in stage-codes.md is a rung the ladder knows" {
  # Guards the direction that actually bites: a stage table gaining a tier the resolver
  # cannot bump, which would fail at dispatch rather than here.
  . "$PLUGIN_ROOT/$LIB"
  while IFS="$(printf '\t')" read -r _agent _model effort; do
    run effort_rank "$effort"
    assert_success
  done < <(stage_table_rows)
}

@test "stage-codes.md model and effort match the agents' shipped frontmatter" {
  # This parity is what the RE row lost: the table said haiku for seven months after the
  # agent shipped sonnet. The lookup is only authoritative if it tracks what actually runs.
  while IFS="$(printf '\t')" read -r agent model effort; do
    [ -f "$PLUGIN_ROOT/agents/$agent.md" ] || fail "no agent file for '$agent'"
    [ "$(agent_frontmatter "$agent" model)" = "$model" ] \
      || fail "$agent: table model '$model' != frontmatter '$(agent_frontmatter "$agent" model)'"
    [ "$(agent_frontmatter "$agent" effort)" = "$effort" ] \
      || fail "$agent: table effort '$effort' != frontmatter '$(agent_frontmatter "$agent" effort)'"
  done < <(stage_table_rows)
}

@test "EFFORT_ENUM matches the ladder model-selection.md documents" {
  # § Effort Levels states the rungs with their glyphs; the library must not add or drop one.
  run grep -qF '`low` ○, `medium` ◐, `high` ●, `xhigh` ⬣, `max` ⬛' "$PLUGIN_ROOT/$MODEL_SELECTION"
  assert_success
}

@test "the non-opus ceiling is the tier model-selection.md says Sonnet downgrades from" {
  run grep -q 'xhigh` requires \*\*Opus 5 or Fable 5\*\*' "$PLUGIN_ROOT/$MODEL_SELECTION"
  assert_success
}

@test "the task.metadata schema pins the same enum the ladder defines" {
  # state-ledger.md carries the tiers a third time, as a JSON enum the orchestrator validates
  # against. Three copies, so the drift has two chances to happen.
  . "$PLUGIN_ROOT/$LIB"
  # NOT `paste -sd', '`: BSD paste cycles through the delimiter LIST, so a two-char
  # delimiter alternates ',' and ' ' and the join comes out malformed on macOS.
  want=$(printf '%s' "$EFFORT_ENUM" | sed 's/[a-z][a-z]*/"&"/g; s/ /, /g')
  run grep -qF "\"enum\": [$want]" "$PLUGIN_ROOT/$STATE_LEDGER"
  assert_success
}

@test "effort is a required task.metadata field, not an optional dispatch flag" {
  run grep -qF '"required": ["stage", "agent", "model", "effort", "error_file"]' \
    "$PLUGIN_ROOT/$STATE_LEDGER"
  assert_success
  # And it must be gone from the optional set it used to live in.
  run bash -c "awk '/^### Dispatch metadata \\(optional\\)/{f=1;next} /^###/{f=0} f' \
    '$PLUGIN_ROOT/$STATE_LEDGER' | grep -c '\`effort\`'"
  assert_output "0"
}
