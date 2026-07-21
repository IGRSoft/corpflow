#!/usr/bin/env bash
# PostToolUse hook: injects the igrsoft comment-standard reminder into the
# transcript the first time a source file is touched in a session, so DV
# agents see it without re-reading a skill file every edit.
#
# Fires once per session_id (sentinel in $TMPDIR) and only for a known set of
# source extensions; every other input (non-source file, missing file_path,
# missing jq, malformed stdin) is a silent no-op exit 0 — this hook must
# NEVER block a tool call.
#
# Injection safety: tool_input.file_path is untrusted, attacker-influenceable
# content. It is only ever read into a bash variable and pattern-matched
# (case/parameter-expansion) for its extension — never eval'd, never expanded
# inside a command string, never passed to ls/stat/cat or any subshell.
# session_id is similarly stripped to [A-Za-z0-9_-] via bash pattern
# substitution (no external process) before it is used to build the sentinel
# path, so a crafted session_id cannot traverse directories.
#
# --self-test feeds a synthetic source-file fixture through the same code
# path and asserts the emitted JSON shape; it uses a throwaway session id and
# deletes its own sentinel so repeated runs stay deterministic.
set -eu

STANDARD_TEXT='igrsoft code-comment-standard: comment the non-obvious WHY and the contract only — never the WHAT, the history, or design provenance. Budgets: function doc 1–3 lines (one is the norm, only when the name isn'"'"'t clear); var/const doc ≤1 sentence, only when needed; inline // = one short line per non-obvious literal; #Preview blocks are never commented; comment-to-code density well below 1:1. Never write: multi-paragraph /// essays, before/after or "the previous X" narration, Figma/hex provenance, caller enumeration, AC-/REQ- IDs, issue tags as provenance, prose restating the signature. Rationale belongs in the PR / .context/development-N.md, not in source. Full standard: skill `igrsoft:code-comment-standard`.'

SELF_TEST=0
[ "${1:-}" = "--self-test" ] && SELF_TEST=1

read_stdin() {
  if [ "$SELF_TEST" -eq 1 ]; then
    printf '%s' "{\"session_id\":\"sess_selftest_$$\",\"tool_input\":{\"file_path\":\"/tmp/Foo.swift\"}}"
  else
    cat
  fi
}

if ! command -v jq >/dev/null 2>&1; then
  echo "comment-standard-context: jq not found, skipping" >&2
  exit 0
fi

# ---------------------------------------------------------------------------
# run_hook: core logic. Echoes the additionalContext JSON to stdout on a
# first-touch source-file edit; echoes nothing on every other path. Always
# returns 0 (never blocks).
# ---------------------------------------------------------------------------
run_hook() {
  _payload="$1"

  _parsed=$(printf '%s' "$_payload" | jq -r '[(.session_id // "nosession"), (.tool_input.file_path // "")] | @tsv' 2>/dev/null) || {
    echo "comment-standard-context: jq parse failed" >&2
    return 0
  }
  IFS=$'\t' read -r _sid _fp <<<"$_parsed"

  [ -n "$_fp" ] || return 0

  _base="${_fp##*/}"
  _ext="${_base##*.}"
  case "$_ext" in
    swift | h | m | mm | c | cc | cpp | ts | tsx | js | jsx | py | kt | java | go | rs) ;;
    *) return 0 ;;
  esac

  # Strip to a safe charset via bash pattern substitution (no subprocess).
  _sid="${_sid//[^A-Za-z0-9_-]/}"
  [ -n "$_sid" ] || _sid="nosession"
  _sentinel="${TMPDIR:-/tmp}/igrsoft-comment-standard-${_sid}"

  [ -e "$_sentinel" ] && return 0
  : >"$_sentinel" || return 0

  jq -n --arg ac "$STANDARD_TEXT" \
    '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $ac}}' || {
    echo "comment-standard-context: jq emit failed" >&2
    return 0
  }
  return 0
}

if [ "$SELF_TEST" -eq 1 ]; then
  _test_sid="sess_selftest_$$"
  _test_sentinel="${TMPDIR:-/tmp}/igrsoft-comment-standard-${_test_sid}"
  trap 'rm -f "$_test_sentinel"' EXIT

  _out=$(run_hook "$(read_stdin)")
  printf '%s' "$_out" | jq -e '
    .hookSpecificOutput.hookEventName == "PostToolUse"
    and (.hookSpecificOutput.additionalContext | length > 0)
  ' >/dev/null 2>&1 || {
    echo "comment-standard-context: self-test FAIL"
    exit 1
  }
  echo "comment-standard-context: self-test OK"
  exit 0
fi

PAYLOAD=$(read_stdin)
run_hook "$PAYLOAD"
exit 0
