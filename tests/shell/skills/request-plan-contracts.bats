#!/usr/bin/env bats
# Cross-surface contracts for the request-plan rule set.
#
# The request-plan rules live across five files, and three of the four graded
# contradictions in the 0.0.1 capture were two of those files answering the same
# question differently. Most of that cross-read needs a human. These are the parts
# that reduce to a predicate, so the contradiction cannot silently come back.
#
# Contracts:
#   No rule surface names a slash command that does not resolve to commands/*.md
#     (or a Claude Code built-in).
#   commands/request-plan.md makes no "no exception" claim and cites SKILL.md § 4
#     as the authority for the trigger rule.
#   references/plan-template.md carries the required Surface-check line inside its
#     Recommended-next-step block.
#
# Every candidate set gets a non-vacuity guard: these files genuinely contain slash
# commands and headings, so an empty match means the collector regressed rather than
# that the repo is clean.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

COMMAND_FILE="commands/request-plan.md"
TEMPLATE="skills/request-plan/references/plan-template.md"

# Claude Code ships these; they resolve to no file in commands/ and never will.
BUILTIN_COMMANDS="/clear /compact /config /context /cost /help /init /model /plugins /agents"

# Every rule surface that states request-plan policy. evals.json is deliberately out:
# it holds eval PROMPTS, so a stale command named there is a corpus fact, not a rule.
rule_surfaces() {
  printf '%s\n' \
    "${PLUGIN_ROOT}/${COMMAND_FILE}" \
    "${PLUGIN_ROOT}/skills/estimation-methodology/SKILL.md"
  find "${PLUGIN_ROOT}/skills/request-plan" -type f -name '*.md' | sort
}

# A `/name` token: at least 3 chars (so the `/x` placeholder in SKILL.md § 2 is not
# read as a command), not preceded by anything that makes it a path segment.
slash_tokens() {
  local f
  while IFS= read -r f; do
    grep -hoE '(^|[^A-Za-z0-9/._*!-])/[a-z][a-z0-9-]{2,}' "$f" 2>/dev/null || true
  done < <(rule_surfaces) | grep -oE '/[a-z][a-z0-9-]{2,}' | sort -u
}

# --- no surface names a command that does not exist --------------------------

# Prints every token from stdin that names neither a commands/*.md nor a built-in.
unresolved_commands() {
  local t
  while read -r t; do
    [ -n "$t" ] || continue
    case " $BUILTIN_COMMANDS " in *" $t "*) continue ;; esac
    [ -f "${PLUGIN_ROOT}/commands/${t#/}.md" ] || printf '%s\n' "$t"
  done
}

@test "commands named in the rule surfaces all resolve" {
  # This is the check that would have caught /pm-prioritize surviving in SKILL.md § 4
  # and /pm-requirements in three files after they were renamed. Until now only a
  # manual grep found those.
  local tokens; tokens="$(slash_tokens)"
  local n; n="$(printf '%s' "$tokens" | grep -c . || true)"
  [ "$n" -ge 3 ] || fail "only $n /command token(s) collected; the collector regressed"

  local bad; bad="$(printf '%s\n' "$tokens" | unresolved_commands)"
  [ -z "$bad" ] || fail "named in a rule surface but no such command:
$bad"
}

@test "the command-existence check can actually fail" {
  # Non-vacuity for the PREDICATE, not just the candidate set: a resolver that accepts
  # everything would pass the test above no matter what the surfaces say.
  local bad
  bad="$(printf '%s\n' /worktask /pm-prioritize | unresolved_commands)"
  [ "$bad" = "/pm-prioritize" ] \
    || fail "resolver did not single out the absent command; got: ${bad:-<nothing>}"
}

# --- the command file does not restate the trigger rule's exception count -----

@test "the command file makes no 'no exception' claim of its own" {
  # § 1b: the file claimed "always exactly one, with no exception" while SKILL.md § 4
  # had acquired exactly one. Two surfaces, opposite answers, no trace to catch it
  # because the wording predated the exception.
  run grep -niE 'no exception|without exception|never an exception' \
    "${PLUGIN_ROOT}/${COMMAND_FILE}"
  assert_failure
}

@test "the command file cites SKILL.md § 4 as the trigger-rule authority" {
  run grep -cE 'SKILL\.md.{0,4}§ ?4' "${PLUGIN_ROOT}/${COMMAND_FILE}"
  assert_success
  [ "$output" -ge 1 ] || fail "commands/request-plan.md never points at SKILL.md § 4"
}

# --- the template carries the surface-check line ------------------------------

@test "the plan template requires a Surface check line before the trigger" {
  # § 3's whole mechanism is that the tier check produces visible output. If the line
  # can be dropped from the template without a test going red, it is advisory again.
  run grep -c '\*\*Surface check:\*\*' "${PLUGIN_ROOT}/${TEMPLATE}"
  assert_success
  [ "$output" -ge 1 ] || fail "plan-template.md carries no **Surface check:** line"
}

@test "the Surface check line sits inside the Recommended next step block" {
  # Placement is the contract: before the trigger, not in a note further down where a
  # plan renderer copying the template block would never see it.
  local block
  block="$(awk '/^## Recommended next step/ {inside=1} inside {print} inside && /^```$/ {exit}' \
             "${PLUGIN_ROOT}/${TEMPLATE}")"
  [ -n "$block" ] || fail "no '## Recommended next step' block in the template — collector regressed"
  printf '%s\n' "$block" | grep -q '\*\*Surface check:\*\*' \
    || fail "the **Surface check:** line is outside the Recommended-next-step block"
}
