#!/usr/bin/env bats
# plugin-data-lib.sh — the one resolver for the self-improvement label dataset path,
# sourced by pipeline-counts.sh and append-labels.
#
# The load-bearing block is the four-rung precedence ladder (explicit → plugin-data → env →
# fallback) together with what each rung refuses. A ladder that silently skips a rung sends
# labels to a path nothing reads, and the caller cannot tell because stdout stays clean.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

LIB="skills/self-improvement/scripts/plugin-data-lib.sh"
BASENAME="failure-labels.jsonl"

setup() {
  WD="$(mk_tmpworkdir)"
}

# _resolve <dataset> <plugin_data> <env_value> — runs the resolver under the callers' strict
# mode and prints "<source>\t<path>" so both globals are asserted from one run.
_resolve() {
  run --separate-stderr bash -c \
    "set -euo pipefail; . '$PLUGIN_ROOT/$LIB'; \
     si_resolve_dataset \"\$1\" \"\$2\" \"\$3\" '$BASENAME'; \
     printf '%s\t%s\n' \"\$SI_DATASET_SOURCE\" \"\$SI_DATASET_PATH\"" \
    _ "$1" "$2" "$3" < /dev/null
}

@test "executing the library directly is refused; it is source-only" {
  run bash "$PLUGIN_ROOT/$LIB"
  [ "$status" -eq 2 ]
  [[ "$output" == *"source it, do not execute it directly"* ]]
}

@test "rung 1: an explicit dataset wins over every other rung and is used verbatim" {
  _resolve "/given/path.jsonl" "$WD/pd" "$WD/env"
  [ "$status" -eq 0 ]
  [ "$output" = "explicit	/given/path.jsonl" ]
  [ ! -d "$WD/pd" ] || fail "an explicit dataset must not create a plugin-data dir"
}

@test "rung 2: an absolute --plugin-data resolves under self-improvement/ and creates it 0700" {
  _resolve "" "$WD/pd" ""
  [ "$status" -eq 0 ]
  [ "$output" = "plugin-data	$WD/pd/self-improvement/$BASENAME" ]
  [ -d "$WD/pd/self-improvement" ]
  local mode
  mode="$(stat -f '%Lp' "$WD/pd/self-improvement" 2> /dev/null || stat -c '%a' "$WD/pd/self-improvement")"
  [ "$mode" = "700" ]
}

@test "rung 2: a trailing slash on --plugin-data does not double the separator" {
  _resolve "" "$WD/pd/" ""
  [ "$status" -eq 0 ]
  [ "$output" = "plugin-data	$WD/pd/self-improvement/$BASENAME" ]
}

@test "rung 2: a relative --plugin-data is an error, never a silent fallback" {
  _resolve "" "relative/dir" ""
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"--plugin-data must be an absolute path"* ]]
}

@test "rung 3: the env value resolves the same way once --plugin-data is absent" {
  _resolve "" "" "$WD/env"
  [ "$status" -eq 0 ]
  [ "$output" = "env	$WD/env/self-improvement/$BASENAME" ]
  [ -d "$WD/env/self-improvement" ]
}

@test "rung 3: an unsubstituted placeholder is not an error; it falls through to the fallback" {
  # A literal '$' means the host never substituted the value, which is the documented
  # absent-from-the-env case rather than a caller mistake.
  CLAUDE_PROJECT_DIR="$WD/proj" _resolve "" "" '${CLAUDE_PLUGIN_DATA}'
  [ "$status" -eq 0 ]
  [[ "$output" == fallback* ]]
}

@test "rung 4: the fallback lands under the project dir and warns on stderr" {
  CLAUDE_PROJECT_DIR="$WD/proj" _resolve "" "" ""
  [ "$status" -eq 0 ]
  [ "$output" = "fallback	$WD/proj/evals/$BASENAME" ]
  [[ "$stderr" == *"plugin data dir unavailable"* ]]
}

@test "sourcing twice is idempotent and re-sourcing does not reset a resolved path" {
  run --separate-stderr bash -c \
    "set -euo pipefail; . '$PLUGIN_ROOT/$LIB'; \
     si_resolve_dataset '' '$WD/pd' '' '$BASENAME'; \
     . '$PLUGIN_ROOT/$LIB'; printf '%s\n' \"\$SI_DATASET_PATH\"" < /dev/null
  [ "$status" -eq 0 ]
  [ "$output" = "$WD/pd/self-improvement/$BASENAME" ]
}
