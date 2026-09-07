#!/usr/bin/env bash
# comment-standard-context — PostToolUse hook injecting the corpflow
# comment-standard reminder into the transcript the first time a source file is
# touched, so DV agents see it without re-reading a skill file on every edit.
#
# Fires once per AGENT (sentinel in $TMPDIR) and only for known source
# extensions; every other input (non-source path, missing file_path, no jq,
# malformed stdin) is a silent exit 0 — this must NEVER block a tool call.
#
# The sentinel keys on transcript_path's basename, not session_id: subagents
# inherit the parent's session_id, so a session-keyed sentinel would fire once
# for a whole multi-agent worktask. session_id is the fallback.
#
# Injection safety: tool_input.file_path is untrusted. It is only ever read into
# a variable and pattern-matched for its extension — never eval'd, never
# expanded inside a command string, never passed to a subshell. session_id is
# stripped to [A-Za-z0-9_-] before building the sentinel path, so a crafted
# value cannot traverse directories.
#
# --self-test drives a synthetic fixture through the same path, asserts the JSON
# shape, and deletes its own sentinel so repeat runs stay deterministic.
set -eu

STANDARD_TEXT='corpflow code-comment-standard: comment the non-obvious WHY and the contract only — never the WHAT, the history, or design provenance. Budgets: function doc 1–3 lines (one is the norm, only when the name isn'"'"'t clear); var/const doc ≤1 sentence, only when needed; inline // = one short line per non-obvious literal; #Preview blocks are never commented; comment-to-code density well below 1:1 and ≤40% of a change'"'"'s added lines (enforced by dv-comment-density-gate.sh on SubagentStop). Never write: multi-paragraph /// essays, before/after or "the previous X" narration, Figma/hex provenance, caller enumeration, AC-/REQ- IDs, issue tags as provenance, prose restating the signature, QA tuning runbooks, or a justification written to answer a DR finding. Rationale — including threshold derivations and review answers — belongs in the PR / .context/development-N.md, not in source. Full standard: skill `corpflow:code-comment-standard`.'

SELF_TEST=0
[ "${1:-}" = "--self-test" ] && SELF_TEST=1

read_stdin() {
  if [ "$SELF_TEST" -eq 1 ]; then
    printf '%s' "{\"session_id\":\"sess_selftest_$$\",\"tool_input\":{\"file_path\":\"/tmp/Foo.swift\"}}"
  else
    cat
  fi
}

# Synthetic payload for the self-test: one session, a chosen agent transcript.
# shellcheck disable=SC2329 # called by lib/comment-standard-context-selftest.sh, sourced at the arm
selftest_payload() {
  printf '%s' "{\"session_id\":\"sess_selftest_$$\",\"transcript_path\":\"/tmp/tasks/$1.jsonl\",\"tool_input\":{\"file_path\":\"${2:-/tmp/Foo.swift}\"}}"
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

  _parsed=$(printf '%s' "$_payload" | jq -r '[(.session_id // "nosession"), (.tool_input.file_path // ""), (.transcript_path // "")] | @tsv' 2>/dev/null) || {
    echo "comment-standard-context: jq parse failed" >&2
    return 0
  }
  IFS=$'\t' read -r _sid _fp _tp <<<"$_parsed"

  [ -n "$_fp" ] || return 0

  _base="${_fp##*/}"
  _ext="${_base##*.}"
  case "$_ext" in
    swift | h | m | mm | c | cc | cpp | ts | tsx | js | jsx | py | kt | java | go | rs | sh | bash) ;;
    *) return 0 ;;
  esac

  # Per-agent key: transcript_path's basename (the agent id for a subagent),
  # falling back to session_id. Strip to a safe charset via bash pattern
  # substitution (no subprocess) so a crafted value cannot traverse directories.
  _key="${_tp##*/}"
  _key="${_key%.*}"
  _key="${_key//[^A-Za-z0-9_-]/}"
  [ -n "$_key" ] || _key="${_sid//[^A-Za-z0-9_-]/}"
  [ -n "$_key" ] || _key="nosession"
  _sentinel="${TMPDIR:-/tmp}/corpflow-comment-standard-${_key}"

  [ -e "$_sentinel" ] && return 0
  : >"$_sentinel" || return 0

  jq -n --arg ac "$STANDARD_TEXT" \
    '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $ac}}' || {
    echo "comment-standard-context: jq emit failed" >&2
    return 0
  }
  return 0
}

# Body lives in lib/ — test code, sourced only here and never on the dispatch
# path below. This arm fails CLOSED: a self-test that cannot find its cases must
# report a failure, never "OK".
if [ "$SELF_TEST" -eq 1 ]; then
  _selftest_body="$(dirname "$0")/lib/comment-standard-context-selftest.sh"
  if [ ! -f "$_selftest_body" ]; then
    echo "comment-standard-context: self-test body missing at $_selftest_body" >&2
    exit 1
  fi
  . "$_selftest_body"
fi

PAYLOAD=$(read_stdin)
run_hook "$PAYLOAD"
exit 0
