#!/usr/bin/env bash
# @description frontmatter-lib.sh — the one reader of a stage artifact's `handoff:` block.
#   Two tools parsed it two ways: handoff-harness.sh required strictly nested
#   `.handoff.<field>`, while state-patch.sh fell back to an indentation-agnostic awk
#   matcher (`^[[:space:]]*stage:`) that also accepted a FLAT top-level shape. An artifact
#   written flat was therefore unreadable to the harness and still wrote a healthy ledger
#   row — a stage that passed its own bookkeeping and failed its boundary, with nothing
#   connecting the two.
#
#   One block extractor, one shape gate, one field reader. Both tools bind to these.
#
#   Symbols: corpflow_fm_block, corpflow_fm_has_handoff, corpflow_fm_field.
#
# Minimum shell: bash 3.2+ (macOS default).

# Anti-execution guard — MUST be the first statement.
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  printf >&2 'frontmatter-lib.sh: this is a library — source it, do not execute it directly\n'
  exit 2
fi

# Include guard: a double source is a no-op rather than a re-definition.
[ -n "${_CORPFLOW_FRONTMATTER_LIB:-}" ] && return 0
_CORPFLOW_FRONTMATTER_LIB=1

# Not `readonly`: consumer bats suites source this file twice per process, and a second
# readonly assignment is rc 1, which kills a `set -e` caller.

# corpflow_fm_block <artifact> -> the YAML between the first two `^---$` fences, on stdout.
#
# rc 0 with output when a block is present, rc 1 and no output otherwise. The two callers
# previously used different awk programs for this — one stopped at the closing fence, the
# other did not — so an artifact with a second `---` later in the body was sliced
# differently by each. This is the harness's stricter form, which is the correct one.
corpflow_fm_block() {
  local _art="${1:-}" _out
  [ -r "$_art" ] || return 1
  _out=$(awk '/^---[[:space:]]*$/ { c++; if (c == 1) next; if (c == 2) exit } c == 1' \
    "$_art" 2> /dev/null) || return 1
  [ -n "$_out" ] || return 1
  printf '%s\n' "$_out"
}

# corpflow_fm_has_handoff <block-file> -> rc 0 when the block carries a top-level
# `handoff:` key.
#
# This is the shape gate both tools now share. A block WITHOUT it is malformed, not merely
# unusual: every per-stage template in stage-contracts.md nests under `handoff:`, and the
# flat shape only ever existed because one reader tolerated it.
corpflow_fm_has_handoff() {
  local _fm="${1:-}"
  [ -r "$_fm" ] || return 1
  grep -qE '^handoff:[[:space:]]*$' "$_fm"
}

# corpflow_fm_field <block-file> <field> [default] -> the scalar at `.handoff.<field>`.
#
# Always rc 0: absence is a value here, and the required-field check is the caller's, not
# this reader's. Prefers yq; the awk fallback is NESTING-AWARE — it reads only keys indented
# beneath a column-0 `handoff:` — which is the whole correction. `// ""` is deliberately NOT
# used: yq's alternative operator treats a literal `false` as falsy and would hand back the
# default for a legitimately false field.
corpflow_fm_field() {
  local _fm="${1:-}" _field="${2:-}" _default="${3:-}" _val=""
  [ -r "$_fm" ] && [ -n "$_field" ] || { printf '%s' "$_default"; return 0; }

  if command -v yq > /dev/null 2>&1; then
    _val=$(yq eval ".handoff.${_field}" "$_fm" 2> /dev/null) || _val=""
  else
    _val=$(awk -v key="$_field" '
      /^handoff:[[:space:]]*$/ { inblk = 1; next }
      inblk && /^[^[:space:]#]/ { inblk = 0 }
      inblk {
        line = $0
        if (match(line, "^[[:space:]]+" key ":")) {
          sub("^[[:space:]]+" key ":[[:space:]]*", "", line)
          gsub(/^"|"$/, "", line)
          gsub(/[[:space:]]+$/, "", line)
          print line
          exit
        }
      }
    ' "$_fm" 2> /dev/null) || _val=""
  fi

  [ "$_val" = "null" ] && _val=""
  [ -n "$_val" ] || _val="$_default"
  printf '%s' "$_val"
}
