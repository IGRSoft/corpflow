#!/usr/bin/env bash
# anchor-preflight — PreToolUse and PostToolUse (Write|Edit) hook, one script for both events.
#
# Usage: anchor-preflight.sh [--event pre|post] | --self-test
#
# The manifest names the event in argv (`--event pre` on the PreToolUse registration) because
# stdin cannot be trusted to say it: without jq the payload is unreadable, and a Pre call that
# fell through to the Post checks would exit 2 on the not-yet-written file's old contents and
# block the write. With no --event the payload's hook_event_name decides, then Post.
#
# PreToolUse: denies a write to a canonical .context/<stage>-N.md artifact (DV also its
# development-N-<stream>.md) whose content adds an H2 outside that stage's allow-list
# (cache-lint.sh --anchor-diff). A missing required H2
# never denies: artifacts are built in steps, and the stage-boundary harness owns that check.
# An Edit is judged on new_string, minus the H2s old_string already carries. Fails open
# (allows) without jq, without a state.json beside the artifact, or without a plugin root.
#
# PostToolUse: a write under a .context/ that holds a state.json, whose extension is on the
# control-byte-lib text allowlist, is scanned for raw C0 control bytes (a form feed in a project's
# own source is not the plugin's business);
# a path matching the canonical .context/<stage>-N.md regex also runs cache-lint.sh
# --anchor-lint, so a bad H2 anchor surfaces at the producing write rather than at the DR gate.
#
# Post reads tool_input.file_path from the hook stdin JSON, falling back to
# CLAUDE_TOOL_INPUT_FILE_PATH without jq. Exit 2 on any Post finding: in PostToolUse only
# exit 2 routes stderr to the model, and continueOnBlock keeps the turn going. Pre always
# exits 0; a deny travels as JSON on stdout.
#
# Plugin root is env-first ($CLAUDE_PLUGIN_ROOT), else self-located from $0. An empty root
# skips both lints. --self-test asserts the gating regex, the control-byte scan, the Pre deny
# arm and the no-jq `--event pre` exit.
set -eu

SELF_TEST=0
EVENT=""
case "${1:-}" in
  --self-test) SELF_TEST=1 ;;
  --event)
    EVENT="${2:-}"
    # An unknown event is a manifest typo; a blocking hook fails open on it rather than guess.
    case "$EVENT" in pre | post) ;; *) exit 0 ;; esac
    ;;
esac

# Canonical artifact basenames (mirrors handoff-protocol.md#stage-artifact-map).
#
# DV also matches the per-stream development-N-<stream>.md: under handoff-protocol.md
# § DV fan-out — ledger tasks each stream file IS its row's DV handoff, read directly by
# DR/QA through refs.dev, so it carries the same anchor contract as development-N.md.
# The stream arm is the S1 slug grammar; its 40-char cap cannot be said in one ERE, so
# STREAM_TOO_LONG_RE subtracts over-long slugs. Other stages have no stream suffix.
ARTIFACT_RE='\.context/((planning|architecture|coordination|development|developer-review|security-review|testing|documentation|release|complete-summary|retrospective|incident|ethics-review)-[0-9]+|development-[0-9]+-[a-z0-9]+(-[a-z0-9]+)*)\.md$'
STREAM_TOO_LONG_RE='\.context/development-[0-9]+-[a-z0-9-]{41,}\.md$'

# is_artifact <path> — true when <path> is a lintable stage artifact name.
is_artifact() {
  printf '%s' "$1" | grep -qE "$ARTIFACT_RE" || return 1
  ! printf '%s' "$1" | grep -qE "$STREAM_TOO_LONG_RE"
}

if [ "$SELF_TEST" -eq 1 ]; then
  ok=0
  for p in \
    ".context/development-0.md" \
    ".context/development-0-swift-app.md" \
    ".context/development-2-backend.md" \
    ".context/development-0-a234567890123456789012345678901234567890.md" \
    ".context/developer-review-12.md" \
    "/abs/path/.context/planning-3.md"; do
    is_artifact "$p" || { echo "anchor-preflight: self-test FAIL (should match: $p)"; exit 1; }
  done
  for p in \
    "skills/worktask/SKILL.md" \
    ".context/state.json" \
    ".context/development.md" \
    ".context/development-0-.md" \
    ".context/development-0-Stream.md" \
    ".context/development-0--web.md" \
    ".context/development-0-web-.md" \
    ".context/development-N-web.md" \
    ".context/development-0-a2345678901234567890123456789012345678901.md" \
    ".context/planning-0-stream.md" \
    ".context/developer-review-0-web.md" \
    ".context/worktask-comms.md"; do
    is_artifact "$p" && { echo "anchor-preflight: self-test FAIL (should NOT match: $p)"; exit 1; }
    ok=$((ok + 1))
  done

  # An unreachable library is a FAIL here, never a vacuous OK: the hook itself fails open.
  _ST_LIB="${CLAUDE_PLUGIN_ROOT:-$(dirname -- "$0")/..}/skills/worktask/scripts/control-byte-lib.sh"
  if [ ! -r "$_ST_LIB" ]; then
    echo "anchor-preflight: self-test FAIL (control-byte-lib.sh unreachable at $_ST_LIB)"
    exit 1
  fi
  # shellcheck source=skills/worktask/scripts/control-byte-lib.sh
  . "$_ST_LIB"
  _st_td=$(mktemp -d "${TMPDIR:-/tmp}/anchor-preflight-selftest.XXXXXX")
  # shellcheck disable=SC2064  # the path is fixed at set time on purpose
  trap "rm -rf '$_st_td'" EXIT
  # shellcheck disable=SC2016  # the backticks are fixture text, not a command substitution
  printf 'escape spellings `\\0` then a raw \000 byte\n' > "$_st_td/nul.md"
  printf 'tab\tcr\r\nliteral \\0 \\x00 ^@\n' > "$_st_td/clean.md"
  _st_rc=0
  _st_out=$(cb_scan_file "$_st_td/nul.md" nul.md) || _st_rc=$?
  [ "$_st_rc" -eq 1 ] && [ "$_st_out" = "nul.md:33:0x00" ] \
    || { echo "anchor-preflight: self-test FAIL (NUL not flagged: rc=$_st_rc out=$_st_out)"; exit 1; }
  _st_rc=0
  cb_scan_file "$_st_td/clean.md" clean.md > /dev/null || _st_rc=$?
  [ "$_st_rc" -eq 0 ] || { echo "anchor-preflight: self-test FAIL (clean file flagged: rc=$_st_rc)"; exit 1; }

  if command -v jq > /dev/null 2>&1; then
    mkdir -p "$_st_td/.context"
    : > "$_st_td/.context/state.json"
    _st_pre() {  # <file_path> -> the hook's stdout for a PreToolUse Write adding `## Approach`
      jq -cn --arg p "$1" '{hook_event_name: "PreToolUse", tool_name: "Write",
        tool_input: {file_path: $p, content: "## files-changed\n## Approach\n"}}' \
        | CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname -- "$0")/..}" bash "$0"
    }
    _st_out=$(_st_pre "$_st_td/.context/development-0.md") || _st_out=""
    case "$_st_out" in
      *'"permissionDecision":"deny"'*'## Approach'*) ;;
      *) echo "anchor-preflight: self-test FAIL (bad H2 on an artifact path not denied: $_st_out)"; exit 1 ;;
    esac
    _st_out=$(_st_pre "$_st_td/notes-0.md") || _st_out="rc!=0"
    [ -z "$_st_out" ] || { echo "anchor-preflight: self-test FAIL (non-artifact write denied: $_st_out)"; exit 1; }
  else
    echo "anchor-preflight: self-test SKIP pre-write deny arm (jq unavailable; the arm fails open)"
  fi

  # The farm carries the control-byte scan's tools but no jq, so the NUL file would exit 2 if
  # --event pre ever reached the Post path. The same run without --event proves the fixture bites.
  mkdir -p "$_st_td/bin"
  for _st_tool in awk grep od tr; do
    _st_src=$(command -v "$_st_tool" 2> /dev/null) || continue
    case "$_st_src" in /*) ln -s "$_st_src" "$_st_td/bin/$_st_tool" ;; esac
  done
  _st_nojq() {  # [--event pre] -> the hook's exit status with jq hidden
    _st_rc=0
    env PATH="$_st_td/bin" CLAUDE_TOOL_INPUT_FILE_PATH="$_st_file" \
      CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname -- "$0")/..}" \
      "$BASH" "$0" "$@" < /dev/null > /dev/null 2>&1 || _st_rc=$?
  }
  # The Post scan covers only a ledger's .context/, so the biting fixture lives in one.
  mkdir -p "$_st_td/.context"
  : > "$_st_td/.context/state.json"
  cp "$_st_td/nul.md" "$_st_td/.context/nul.md"
  _st_file="$_st_td/.context/nul.md"
  _st_nojq
  [ "$_st_rc" -eq 2 ] || { echo "anchor-preflight: self-test FAIL (no-jq Post fixture exited $_st_rc, want 2)"; exit 1; }
  _st_file="$_st_td/nul.md"
  _st_nojq
  [ "$_st_rc" -eq 0 ] || { echo "anchor-preflight: self-test FAIL (NUL outside any .context/ exited $_st_rc, want 0)"; exit 1; }
  _st_file="$_st_td/.context/nul.md"
  _st_nojq --event pre
  [ "$_st_rc" -eq 0 ] || { echo "anchor-preflight: self-test FAIL (no-jq --event pre exited $_st_rc)"; exit 1; }

  echo "anchor-preflight: self-test OK"
  exit 0
fi

# An explicitly set env var always wins; otherwise derive the root from the shared
# resolver, which validates the .claude-plugin/plugin.json marker.
resolve_plugin_root() {
  PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
  [ -z "$PLUGIN_ROOT" ] || return 0
  # A TRUNCATED library is worse than an absent one: a syntax error in a sourced file is
  # fatal under `set -e` and `||` does not rescue it. Drop -e across the source and probe
  # for the symbol afterwards, so an unusable library degrades this preflight to a no-op
  # instead of turning it into a hard block on every artifact write.
  _LIB="$(dirname -- "$0")/lib/corpflow-base.sh"
  _cf_opts=$-
  set +e
  # shellcheck source=hooks/lib/corpflow-base.sh
  [ -f "$_LIB" ] && . "$_LIB"
  case "$_cf_opts" in *e*) set -e ;; esac
  if command -v corpflow_plugin_root > /dev/null 2>&1; then
    PLUGIN_ROOT="$(corpflow_plugin_root)" || PLUGIN_ROOT=""
  fi
  return 0
}

# The deny reason names the stage's whole allowed set, because an agent outside corpflow
# writing a canonical artifact name sees the contract nowhere else.
pre_allowed_set() {
  bash "$1" --allow-list 2> /dev/null | awk -F'\t' -v b="$2" '
    function add(l, h) { return l (l == "" ? "" : ", ") "## " h }
    $3 == b && ($4 == "required" || $4 == "universal") { req = add(req, $5); st = $1 }
    $3 == b && $4 == "optional" { opt = add(opt, $5) }
    $1 == "*" { any = add(any, $5) }
    END {
      if (st == "") exit 1
      printf "%s\n%s%s%s", st, req, (opt == "" ? "" : "; optional: " opt), (any == "" ? "" : "; any stage: " any)
    }'
}

pre_tool_use_arm() {
  FILE_PATH=$(printf '%s' "$PAYLOAD" | jq -r '.tool_input.file_path // empty' 2> /dev/null) || return 0
  [ -n "$FILE_PATH" ] || return 0
  is_artifact "$FILE_PATH" || return 0
  # The ledger beside the artifact, not a resolved root: a megatask worktree's .context is
  # not the main checkout's.
  [ -f "$(dirname -- "$FILE_PATH")/state.json" ] || return 0
  resolve_plugin_root
  [ -n "$PLUGIN_ROOT" ] || return 0
  _lint="$PLUGIN_ROOT/skills/worktask/scripts/cache-lint.sh"
  [ -r "$_lint" ] || return 0

  # Model-authored text reaches the lint only as file contents, never as argv.
  _pre_td=$(mktemp -d "${TMPDIR:-/tmp}/anchor-preflight.XXXXXX") || return 0
  # shellcheck disable=SC2064  # the path is fixed at set time on purpose
  trap "rm -rf '$_pre_td'" EXIT
  printf '%s' "$PAYLOAD" | jq -r 'if (.tool_input.content | type) == "string" then .tool_input.content
    else (.tool_input.new_string // "") end' > "$_pre_td/new" 2> /dev/null || return 0
  printf '%s' "$PAYLOAD" | jq -r '.tool_input.old_string // ""' > "$_pre_td/old" 2> /dev/null || return 0

  _rc=0
  _rows=$(bash "$_lint" --anchor-diff --for-path "$FILE_PATH" --baseline "$_pre_td/old" "$_pre_td/new" 2> /dev/null) || _rc=$?
  [ "$_rc" -eq 1 ] || return 0
  _bad=$(printf '%s\n' "$_rows" | awk -F'\t' '$1 == "unexpected" { printf "%s## %s", (n++ ? ", " : ""), $2 }')
  [ -n "$_bad" ] || return 0

  _base="${FILE_PATH##*/}"
  # Strip the run index and any DV stream suffix: the allow-list keys rows by canonical basename.
  _canon=$(printf '%s' "${_base%.md}" | sed -E 's/-[0-9]+(-[a-z0-9-]+)?$//')
  _set=$(pre_allowed_set "$_lint" "$_canon") || return 0
  _nl='
'
  _reason="anchor-preflight: $_base (stage=${_set%%"$_nl"*}) adds H2 outside the allow-list: $_bad. Allowed: ${_set#*"$_nl"}. Nest other headings as H3."
  _doc=$(jq -cn --arg reason "$_reason" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}' \
    2> /dev/null) || return 0
  printf '%s\n' "$_doc"
  return 0
}

# Resolve the written file path: prefer hook stdin JSON, fall back to env.
FILE_PATH=""
PAYLOAD=""
if [ "$EVENT" = pre ] && ! command -v jq > /dev/null 2>&1; then
  exit 0
fi
if command -v jq >/dev/null 2>&1; then
  PAYLOAD=$(cat 2>/dev/null || true)
  if [ "$EVENT" = pre ]; then
    [ -z "$PAYLOAD" ] || pre_tool_use_arm
    exit 0
  fi
  if [ -n "$PAYLOAD" ]; then
    if [ -z "$EVENT" ] \
      && [ "$(printf '%s' "$PAYLOAD" | jq -r '.hook_event_name // empty' 2> /dev/null || true)" = "PreToolUse" ]; then
      pre_tool_use_arm
      exit 0
    fi
    FILE_PATH=$(printf '%s' "$PAYLOAD" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null || true)
  fi
fi
[ -z "$FILE_PATH" ] && FILE_PATH="${CLAUDE_TOOL_INPUT_FILE_PATH:-}"
[ -n "$FILE_PATH" ] || exit 0

resolve_plugin_root
# Never fall back to `.`: an empty root would load skills/ out of the user's project (CWE-427).
[ -n "$PLUGIN_ROOT" ] || exit 0

# in_ledger_context <path> — rc 0 when the nearest ancestor directory named .context holds a
# state.json; rc 1 otherwise, including a path under no .context at all.
in_ledger_context() {
  local d="${1%/*}"
  [ "$d" != "$1" ] || return 1
  while [ -n "$d" ]; do
    case "$d" in
      */.context | .context)
        [ -f "$d/state.json" ]
        return
        ;;
    esac
    case "$d" in
      */*) d="${d%/*}" ;;
      *) return 1 ;;
    esac
  done
  return 1
}

cbrc=0
CB_LIB="$PLUGIN_ROOT/skills/worktask/scripts/control-byte-lib.sh"
if [ -f "$FILE_PATH" ] && [ -r "$CB_LIB" ] && in_ledger_context "$FILE_PATH"; then
  _cf_opts=$-
  set +e
  # shellcheck source=skills/worktask/scripts/control-byte-lib.sh
  . "$CB_LIB"
  case "$_cf_opts" in *e*) set -e ;; esac
  if command -v cb_scan_file > /dev/null 2>&1 && cb_is_lintable "$FILE_PATH"; then
    cbhits=$(cb_scan_file "$FILE_PATH" "$FILE_PATH") || cbrc=$?
    if [ "$cbrc" -eq 1 ]; then
      printf >&2 'anchor-preflight: control bytes in %s — a typed escape was decoded into a raw byte; rewrite each named byte\n' "$FILE_PATH"
      printf >&2 '%s\n' "$cbhits"
    else
      cbrc=0
    fi
  fi
fi

if ! is_artifact "$FILE_PATH" || [ ! -f "$FILE_PATH" ]; then
  [ "$cbrc" -eq 0 ] || exit 2
  exit 0
fi

arc=0
LINT="$PLUGIN_ROOT/skills/worktask/scripts/cache-lint.sh"
if [ -f "$LINT" ]; then
  bash "$LINT" --anchor-lint "$FILE_PATH" || arc=$?
fi
[ "$cbrc" -eq 0 ] && [ "$arc" -eq 0 ] || exit 2
exit 0
