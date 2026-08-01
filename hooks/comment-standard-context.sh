#!/usr/bin/env bash
# PostToolUse hook: injects the company-workflow comment-standard reminder into the
# transcript the first time a source file is touched in a session, so DV
# agents see it without re-reading a skill file every edit.
#
# Fires once per AGENT (sentinel in $TMPDIR) and only for a known set of
# source extensions; every other input (non-source file, missing file_path,
# missing jq, malformed stdin) is a silent no-op exit 0 — this hook must
# NEVER block a tool call.
#
# The sentinel is keyed on transcript_path's basename, not session_id: every
# subagent inherits the parent's session_id, so a session-keyed sentinel fired
# once for an entire multi-agent worktask and left every later DV agent without
# the standard. transcript_path is per-agent; session_id is the fallback.
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

STANDARD_TEXT='company-workflow code-comment-standard: comment the non-obvious WHY and the contract only — never the WHAT, the history, or design provenance. Budgets: function doc 1–3 lines (one is the norm, only when the name isn'"'"'t clear); var/const doc ≤1 sentence, only when needed; inline // = one short line per non-obvious literal; #Preview blocks are never commented; comment-to-code density well below 1:1 and ≤40% of a change'"'"'s added lines (enforced by dv-comment-density-gate.sh on SubagentStop). Never write: multi-paragraph /// essays, before/after or "the previous X" narration, Figma/hex provenance, caller enumeration, AC-/REQ- IDs, issue tags as provenance, prose restating the signature, QA tuning runbooks, or a justification written to answer a DR finding. Rationale — including threshold derivations and review answers — belongs in the PR / .context/development-N.md, not in source. Full standard: skill `company-workflow:code-comment-standard`.'

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
  _sentinel="${TMPDIR:-/tmp}/company-workflow-comment-standard-${_key}"

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
  _agent_a="agentA_selftest_$$"
  _agent_b="agentB_selftest_$$"
  _agent_c="agentC_selftest_$$"
  trap 'rm -f "${TMPDIR:-/tmp}/company-workflow-comment-standard-${_agent_a}" "${TMPDIR:-/tmp}/company-workflow-comment-standard-${_agent_b}" "${TMPDIR:-/tmp}/company-workflow-comment-standard-${_agent_c}"' EXIT

  _emits_context() {
    printf '%s' "$1" | jq -e '
      .hookSpecificOutput.hookEventName == "PostToolUse"
      and (.hookSpecificOutput.additionalContext | length > 0)
    ' >/dev/null 2>&1
  }

  # 1. First touch by agent A injects.
  _emits_context "$(run_hook "$(selftest_payload "$_agent_a")")" || {
    echo "comment-standard-context: self-test FAIL (agent A got no injection)"
    exit 1
  }

  # 2. Agent B — SAME session_id, different transcript — must ALSO inject.
  #    Regression guard: a session-keyed sentinel silently skipped every
  #    subagent after the first, so one worktask got one reminder.
  _emits_context "$(run_hook "$(selftest_payload "$_agent_b")")" || {
    echo "comment-standard-context: self-test FAIL (agent B suppressed by agent A's sentinel)"
    exit 1
  }

  # 3. Agent A again — same transcript — stays silent (once per agent).
  if _emits_context "$(run_hook "$(selftest_payload "$_agent_a")")"; then
    echo "comment-standard-context: self-test FAIL (agent A injected twice)"
    exit 1
  fi

  # 4. A shell path must inject: shell sat outside the extension gate. Fresh
  #    agent key — injection fires once per agent.
  _emits_context "$(run_hook "$(selftest_payload "$_agent_c" /tmp/deploy.sh)")" || {
    echo "comment-standard-context: self-test FAIL (shell path got no injection)"
    exit 1
  }

  echo "comment-standard-context: self-test OK"
  exit 0
fi

PAYLOAD=$(read_stdin)
run_hook "$PAYLOAD"
exit 0
