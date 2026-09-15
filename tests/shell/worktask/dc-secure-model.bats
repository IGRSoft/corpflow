#!/usr/bin/env bats
# DC model tier under --secure, and the DC gate prose that names doc-option-check.sh.
#
# PL0 stamps stage models from tables, not from a runtime resolver, so these tables are the
# resolver: resolve() below reads them exactly as PL0 is told to.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

STAGE_CODES="skills/shared/stage-codes.md"
PL0="skills/worktask/references/pl0-procedure.md"
AGENT="agents/technical-writer.md"
CONTRACTS="skills/shared/stage-contracts.md"
SCRIPT="skills/worktask/scripts/doc-option-check.sh"

# Same reset rule as effort-ladder.bats: a table ends at the first non-table line.
override_rows() {
  awk -F'|' '
    !/^\|/ { t = 0 }
    /^\| Code \| Condition \| Model \| Effort \|/ { t = 1; next }
    t && /^\| [A-Z][A-Z] \|/ {
      for (i = 1; i <= NF; i++) gsub(/^ +| +$/, "", $i)
      print $2 "\t" $4 "\t" $5
    }
  ' "$PLUGIN_ROOT/$STAGE_CODES"
}

primary_rows() {
  awk -F'|' '
    !/^\|/ { t = 0 }
    /^\| Code \| Stage \| Agent \| Model \| Effort \|/ { t = 1; next }
    t && /^\| [A-Z][A-Z] \|/ {
      for (i = 1; i <= NF; i++) gsub(/^ +| +$/, "", $i)
      print $2 "\t" $5 "\t" $6
    }
  ' "$PLUGIN_ROOT/$STAGE_CODES"
}

resolve() { # <code> <secure|default> -> "model<TAB>effort"
  local hit=""
  if [ "$2" = secure ]; then
    hit="$(override_rows | awk -F'\t' -v c="$1" '$1 == c { print $2 "\t" $3; exit }')"
  fi
  [ -n "$hit" ] || hit="$(primary_rows | awk -F'\t' -v c="$1" '$1 == c { print $2 "\t" $3; exit }')"
  printf '%s' "$hit"
}

model_rank() {
  case "$1" in
    haiku) printf 1 ;;
    sonnet) printf 2 ;;
    opus) printf 3 ;;
    fable) printf 4 ;;
    *) printf 0 ;;
  esac
}

agent_frontmatter() { # <key>
  awk -v k="^$1:" '/^---$/ { n++ } n == 1 && $0 ~ k { print $2; exit }' "$PLUGIN_ROOT/$AGENT"
}

# The value cell of a PL0 default-writer row for <key> whose trigger names Stage `DC`.
pl0_dc_writer_value() { # <key>
  awk -F'|' -v k="\`$1\`" '
    { for (i = 1; i <= NF; i++) gsub(/^ +| +$/, "", $i) }
    $2 == k && $3 ~ /Stage is `DC`/ && $3 ~ /--secure/ { v = $4; gsub(/[`"]/, "", v); print v; exit }
  ' "$PLUGIN_ROOT/$PL0"
}

@test "the secure-override table parses and holds the DC row" {
  run override_rows
  assert_success
  assert_line "DC	sonnet	medium"
}

@test "every override row names a primary stage, a known model and a ladder effort" {
  . "$PLUGIN_ROOT/skills/worktask/scripts/effort-ladder.sh"
  local n=0 code model effort
  while IFS="$(printf '\t')" read -r code model effort; do
    n=$((n + 1))
    [ -n "$(primary_rows | awk -F'\t' -v c="$code" '$1 == c')" ] || fail "$code is not a primary stage"
    [ "$(model_rank "$model")" -gt 0 ] || fail "$code: unknown model '$model'"
    run effort_rank "$effort"
    assert_success
  done < <(override_rows)
  # An empty table would pass every loop assertion above without comparing anything.
  [ "$n" -ge 1 ]
}

@test "DC under --secure ranks strictly above the default DC model" {
  local secure default
  secure="$(resolve DC secure)"
  default="$(resolve DC default)"
  [ "$(model_rank "${secure%%	*}")" -gt "$(model_rank "${default%%	*}")" ] \
    || fail "secure DC '${secure%%	*}' does not outrank default '${default%%	*}'"
  [ "$secure" = "sonnet	medium" ]
}

@test "DC without --secure is haiku/low and equals the technical-writer frontmatter" {
  [ "$(resolve DC default)" = "haiku	low" ]
  [ "$(agent_frontmatter model)" = haiku ]
  [ "$(agent_frontmatter effort)" = low ]
}

@test "stages absent from the override table resolve unchanged under --secure" {
  local code model effort n=0
  while IFS="$(printf '\t')" read -r code model effort; do
    [ -z "$(override_rows | awk -F'\t' -v c="$code" '$1 == c')" ] || continue
    n=$((n + 1))
    [ "$(resolve "$code" secure)" = "$model	$effort" ] || fail "$code changed under --secure"
  done < <(primary_rows)
  [ "$n" -ge 10 ]
}

@test "the PL0 default-writer rows stamp the same DC model and effort as the override table" {
  local row
  row="$(override_rows | awk -F'\t' '$1 == "DC" { print $2 "\t" $3 }')"
  [ "$(pl0_dc_writer_value model)" = "${row%%	*}" ]
  [ "$(pl0_dc_writer_value effort)" = "${row#*	}" ]
}

@test "the technical-writer grant names the gate script, and the script exists" {
  run grep -E '^tools:.*Bash\(bash skills/worktask/scripts/doc-option-check\.sh:\*\)' "$PLUGIN_ROOT/$AGENT"
  assert_success
  [ -f "$PLUGIN_ROOT/$SCRIPT" ]
}

@test "both prose surfaces name the gate, the correction kind and all four detail keys" {
  local f key
  for f in "$AGENT" "$CONTRACTS"; do
    grep -q 'doc-option-check\.sh' "$PLUGIN_ROOT/$f" || fail "$f does not name the script"
    grep -q 'kind: correction' "$PLUGIN_ROOT/$f" || fail "$f lacks kind: correction"
    for key in target_task finding evidence_ref severity; do
      grep -q "$key" "$PLUGIN_ROOT/$f" || fail "$f lacks detail key $key"
    done
  done
}

@test "the agent's invocation uses only flags the script accepts" {
  local invocation flag
  invocation="$(grep -E '^bash skills/worktask/scripts/doc-option-check\.sh ' "$PLUGIN_ROOT/$AGENT")"
  [ -n "$invocation" ]
  for flag in $(printf '%s\n' "$invocation" | grep -oE -- '--[a-z][a-z-]+'); do
    grep -qE -- "(^ +|\| )${flag}( \||\))" "$PLUGIN_ROOT/$SCRIPT" || fail "script has no $flag arm"
  done
}

@test "the exit codes the agent promises are the ones the script header declares" {
  local code
  for code in 0 1 2 3; do
    grep -qE "^\| $code \|" "$PLUGIN_ROOT/$AGENT" || fail "agent exit table lacks $code"
    grep -qE "^# @exitcode $code " "$PLUGIN_ROOT/$SCRIPT" || fail "script header lacks exit $code"
  done
}
