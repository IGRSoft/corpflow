#!/usr/bin/env bash
# dedupe-lib — redundant-run suppression: the key, and the sentinel store it
# names. Sourced by hooks/test-execution-gate.sh (PreToolUse, marks a run
# pending) and, transitively, by hooks/test-execution-promote.sh (PostToolUse,
# promotes or discards that marker).
#
# ONE copy is the point: two hooks deriving the key independently would orphan
# every marker the moment either drifted, disabling suppression silently.
# Anything both hooks must agree on byte-for-byte belongs here.
#
# The two names are deliberately different shapes. The sentinel is keyed on the
# tree, but the `.pending` marker is NOT: the tool runs between the two hooks and
# a run that drops an un-ignored artifact (.pytest_cache, coverage output,
# .build) moves the tree under it, so a fingerprinted marker name would be
# unfindable afterwards and nothing would ever be recorded. The pre-run
# fingerprint travels inside the marker instead of in its name.
#
# Sourced, never executed. Fail-open throughout — an empty answer anywhere means
# "cannot tell", and every caller allows on empty.

# dedupe_dir <ctx> -> the sentinel directory. Defined here so the store location
# and the `.pending` suffix have a single owner.
dedupe_dir() {
  printf '%s/logs/.test-runs' "$1"
}

# dedupe_root <payload> -> the directory `git` is invoked in for the tree
# fingerprint: the payload's own `cwd`, else WORKSPACE_ROOT, else
# CLAUDE_PROJECT_DIR, else the hook process cwd.
#
# A linked worktree keeps its own index, so a root resolved from the hook's cwd
# cannot see a stage's edits at all and the deny's stated remedy ("any
# modification re-enables this") becomes unreachable from an isolated stage.
#
# Resolved more widely than CTX deliberately, and it cannot widen authority: the
# fingerprint feeds suppression only, suppression is asked on the allow path
# alone, and a wrong root matches no prior run — an allow.
dedupe_root() {
  local _payload="$1" _cand
  if command -v jq > /dev/null 2>&1; then
    _cand=$(printf '%s' "$_payload" | jq -r '.cwd // .tool_input.cwd // empty' 2> /dev/null)
    if [ -n "$_cand" ] && [ -d "$_cand" ]; then printf '%s' "$_cand"; return 0; fi
  fi
  for _cand in "${WORKSPACE_ROOT:-}" "${CLAUDE_PROJECT_DIR:-}"; do
    if [ -n "$_cand" ] && [ -d "$_cand" ]; then printf '%s' "$_cand"; return 0; fi
  done
  printf '.'
}

# tree_fingerprint [<root>] -> digest of HEAD plus the uncommitted delta, or
# empty. <root> defaults to the process cwd.
tree_fingerprint() {
  local _root="${1:-.}" _head _delta
  command -v git > /dev/null 2>&1 || return 0
  command -v shasum > /dev/null 2>&1 || return 0
  _head=$(git -C "$_root" rev-parse HEAD 2> /dev/null) || return 0
  [ -n "$_head" ] || return 0
  # `git diff HEAD` as well as `--porcelain`: porcelain reports only NAMES and
  # status letters, so editing one file twice leaves it `M` both times and the
  # digests would match — the second retest would be denied after a real fix.
  # Diff content is what makes the fingerprint track edits rather than filenames.
  # Gap, deliberately accepted: content edits to a never-added untracked file
  # move neither output. Its creation does, and CORPFLOW_TEST_DEDUPE=off covers
  # the rest; hashing untracked contents costs an unbounded walk on every call.
  _delta=$({ git -C "$_root" status --porcelain 2> /dev/null; git -C "$_root" diff HEAD 2> /dev/null; } \
    | shasum 2> /dev/null | cut -d' ' -f1) || return 0
  printf '%s' "$_head$_delta" | shasum 2> /dev/null | cut -d' ' -f1
}

# run_index_of <ctx> -> the ledger's run_index, or empty on any other shape.
run_index_of() {
  local _state="$1/state.json"
  [ -f "$_state" ] || return 0
  jq -r 'if (.run_index | type) == "number" then (.run_index | tostring) else empty end' \
    "$_state" 2> /dev/null
}

# dedupe_key <class> <invocation> <fingerprint> <run_index> -> digest, or empty.
# The invocation is hashed, never stored: a full command can carry a secret, and
# only the digest reaches the filesystem.
#
# Stage is deliberately NOT a component: two stages issuing the same invocation
# against the same tree are a duplicate, and cross-stage suppression within one
# run_index is the documented behaviour.
dedupe_key() {
  command -v shasum > /dev/null 2>&1 || return 0
  printf '%s\n%s\n%s\n%s' "$1" "$2" "$3" "$4" | shasum 2> /dev/null | cut -d' ' -f1
}

# dedupe_pending_key <class> <invocation> <run_index> -> digest, or empty. The
# name both hooks can compute on their own side of the tool call; see the header
# for why the fingerprint is excluded. Domain-separated so it can never collide
# with a dedupe_key whose fingerprint happened to be empty.
dedupe_pending_key() {
  command -v shasum > /dev/null 2>&1 || return 0
  printf 'pending\n%s\n%s\n%s' "$1" "$2" "$3" | shasum 2> /dev/null | cut -d' ' -f1
}

# dedupe_invocation <payload> <tool> <fallback head> -> the string the key
# hashes. Shared because the promoting hook must reproduce it exactly; a second
# derivation is the key-drift failure this library exists to prevent.
dedupe_invocation() {
  local _payload="$1" _tool="$2" _fallback="$3" _v=""
  case "$_tool" in
    Bash)
      _v=$(printf '%s' "$_payload" | jq -r '.tool_input.command // empty' 2> /dev/null)
      ;;
    Skill)
      _v=$(printf '%s' "$_payload" | jq -r '
        [(.tool_input.command // .tool_input.skill // empty), (.tool_input.args // empty)]
        | map(if type == "array" then (map(tostring) | join(" ")) else tostring end)
        | map(select(length > 0)) | join(" ") | select(length > 0)
      ' 2> /dev/null)
      ;;
  esac
  [ -n "$_v" ] || _v="$_fallback"
  printf '%s' "$_v"
}

# dedupe_lookup <ctx> <key> -> "<stage> <ts>" of the recorded run, or empty.
#
# Reads <key>, never <key>.pending: a marker whose PostToolUse never fired must
# deny nothing, so an orphan is inert by construction rather than by cleanup.
dedupe_lookup() {
  local _f
  _f="$(dedupe_dir "$1")/$2"
  [ -f "$_f" ] || return 0
  [ ! -L "$_f" ] || return 0
  head -c 200 "$_f" 2> /dev/null
}

# dedupe_mark_pending <ctx> <pending_key> <full_key> <stage> — record the INTENT
# to run, carrying the pre-run <full_key> the promotion will rename to.
# Best-effort; a failure just means the next identical run is allowed, the safe
# direction.
dedupe_mark_pending() {
  local _d _ts
  _d="$(dedupe_dir "$1")"
  mkdir -p "$_d" 2> /dev/null || return 0
  [ ! -L "$_d/$2.pending" ] || return 0
  _ts=$(date -u +%FT%TZ 2> /dev/null) || _ts="unknown"
  printf '%s %s %s\n' "$4" "$_ts" "$3" > "$_d/$2.pending" 2> /dev/null || return 0
  dedupe_prune_pending "$1"
}

# dedupe_promote <ctx> <pending_key> — turn the intent into a durable sentinel
# under the full key the marker recorded before the tool ran.
#
# The sentinel appears by an atomic rename within one directory, so
# dedupe_lookup's `head -c 200` can never observe a torn write, and its content
# is trimmed back to "<stage> <ts>" — the shape that contract returns. Both names
# are re-checked for a symlink immediately before the move, matching the writer's
# own guard: the window between marking and promoting is exactly where a swap
# would be planted.
dedupe_promote() {
  local _d _line _rest _stage _ts _full
  _d="$(dedupe_dir "$1")"
  [ -f "$_d/$2.pending" ] || return 0
  [ ! -L "$_d/$2.pending" ] || return 0
  IFS= read -r _line < "$_d/$2.pending" 2> /dev/null || return 0
  _stage="${_line%% *}"
  _rest="${_line#* }"
  _ts="${_rest%% *}"
  _full="${_rest#* }"
  [ "$_full" != "$_rest" ] || return 0
  # A key is a hex digest by construction; anything holding a separator did not
  # come from this library and must not steer the rename.
  case "$_full" in ''|*/*|.|..) return 0 ;; esac
  [ ! -L "$_d/$_full" ] || return 0
  printf '%s %s\n' "$_stage" "$_ts" > "$_d/$2.pending" 2> /dev/null || return 0
  mv -f "$_d/$2.pending" "$_d/$_full" 2> /dev/null || return 0
}

# dedupe_discard <ctx> <pending_key> — the run produced nothing; leave no claim
# behind.
dedupe_discard() {
  local _d
  _d="$(dedupe_dir "$1")"
  rm -f "$_d/$2.pending" 2> /dev/null || return 0
}

# dedupe_prune_pending <ctx> — bound the directory, nothing more. Orphans block
# no run (dedupe_lookup never reads them), so this is housekeeping and is
# allowed to fail silently.
dedupe_prune_pending() {
  local _d
  _d="$(dedupe_dir "$1")"
  [ -d "$_d" ] || return 0
  find "$_d" -name '*.pending' -type f -mmin +360 -exec rm -f {} + 2> /dev/null || true
  return 0
}
