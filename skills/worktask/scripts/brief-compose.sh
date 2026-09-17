#!/usr/bin/env bash
# @description brief-compose.sh — composes a stage dispatch brief from contracts and the
#   ledger, never from hand-written prose. Every fact in the brief is a `file:line` ref, an
#   `artifact#anchor` ref, or a plain existing-file path ref the receiving agent resolves
#   itself (skills/worktask/references/handoff-protocol.md#cache-prefix). The orchestrator
#   is the only caller.
#
#   Section order mirrors the cache-prefix marker layout exactly, one marker per line:
#     <<<contract-reminder>>> <<<worktask-header>>> <<<state-json>>> <<<stage-contract>>>
#     <<<model-discipline>>> <<<task-description>>> <<<retry-hints>>> <<<stage-banners>>>
#
#   The whole brief is buffered before anything reaches stdout: a guard failure — an
#   absolute path outside the allowed roots, or a `ref:` line that does not resolve — must
#   never leak a partial brief, since a partial brief reads as verified when it is not.
#
# @arg <TASK_ID>            Ledger task id (e.g. DV0). Required unless --self-test or --help.
# @arg --state <path>       state.json path (default: corpflow_context_dir()/state.json,
#                            never the invoking cwd).
# @arg --orch-root <path>   Passed through to workspace-root-banner.sh.
# @arg --self-test          Run the built-in self-test and exit.
# @arg -h | --help          Show this header.
#
# @stdout The composed brief (exit 0 only). Empty on exit 1 and exit 2.
# @exitcode 0  Brief printed.
# @exitcode 1  Guard failure: an absolute path outside the allowed roots, or an unresolved
#              `ref:` line. One `brief-compose: <reason>: <token>` stderr line per finding.
# @exitcode 2  Usage error, malformed/unknown task id, unreadable ledger, missing jq, or a
#              canon source file/section absent.
#
# Minimum shell: bash 3.2+ (macOS default).

set -euo pipefail

# Stdout, exit 0: help is a normal invocation, not a failure; usage_error/die2
# below are the stderr, exit-2 paths for an actual error.
print_help() {
  sed -n '2,32s/^# \{0,1\}//p' "$0"
  exit 0
}

usage_error() {
  printf >&2 'brief-compose: %s\n' "$1"
  exit 2
}

die2() {
  printf >&2 'brief-compose: %s\n' "$1"
  exit 2
}

# Two uppercase letters and a run-scoped index — the only ids the ledger mints
# (mirrors workspace-root-banner.sh's valid_task_id; [[ =~ ]] anchors the whole value).
valid_task_id() {
  [[ "$1" =~ ^[A-Z]{2}[0-9]+$ ]]
}

# Resolved from BASH_SOURCE, physically, never from cwd or CLAUDE_PLUGIN_ROOT: a brief
# assembled against the wrong plugin checkout would cite canon lines that do not exist
# in the one the receiving agent reads.
plugin_root() {
  (cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)
}

# Sourced by both the default --state resolver and the allowed-root list: corpflow_context_dir
# must be reachable even when --state was passed explicitly, since it is one of the
# allowed-root sources regardless of how the ledger path was resolved.
source_state_lib() {
  local lib
  lib="$(dirname "${BASH_SOURCE[0]}")/../../shared/lib/state-read-lib.sh"
  [[ -r "$lib" ]] || die2 "state-read-lib.sh unreachable at $lib — plugin install broken"
  # shellcheck source=SCRIPTDIR/../../shared/lib/state-read-lib.sh
  . "$lib" || die2 "failed to source $lib"
}

resolve_state() {
  local ctx rc=0
  source_state_lib
  ctx=$(corpflow_context_dir) || rc=$?
  [[ "$rc" -eq 0 && -n "$ctx" ]] || die2 "no .context/state.json resolved; pass --state"
  printf '%s/state.json' "$ctx"
}

# Quotes a literal for safe use inside a grep -E anchor pattern. Anchors are ledger-supplied
# (metadata.context_refs, elsewhere) and must never be read as regex syntax.
regex_escape() {
  printf '%s' "$1" | sed -e 's/[][\\.^$*+?(){}|]/\\&/g'
}

# --- guard state -------------------------------------------------------------------
# Newline-delimited strings, not arrays: bash 3.2 raises "unbound variable" on
# "${arr[@]}" for an array that never received an element, under `set -u`. A string
# iterated with `while read` has no empty-case pitfall.
ROOTS_STR=""
ISSUES=""

add_root() {
  local r="${1%/}" phys
  [[ -n "$r" ]] || return 0
  ROOTS_STR="${ROOTS_STR}${r}"$'\n'
  # macOS aliases /var and /private/var: a root passed in logical form must also
  # register its physical form, else a token the OS resolved through the symlink
  # reads as off-root even though it names the same directory. `if`, not `&&`: phys == r
  # is the common case and must not become the function's status under set -e.
  phys=$(cd "$r" 2> /dev/null && pwd -P) || phys=""
  if [[ -n "$phys" && "$phys" != "$r" ]]; then
    ROOTS_STR="${ROOTS_STR}${phys}"$'\n'
  fi
  return 0
}

# is_allowed_path <token> — rc 0 when token equals a root or sits under one (root or
# root + "/" is the only pass condition; a sibling that merely shares a prefix must not).
is_allowed_path() {
  local tok="$1" r
  while IFS= read -r r; do
    [[ -n "$r" ]] || continue
    if [[ "$tok" == "$r" || "$tok" == "$r"/* ]]; then return 0; fi
  done <<< "$ROOTS_STR"
  return 1
}

record_issue() {
  ISSUES="${ISSUES}brief-compose: $1: $2"$'\n'
}

# scan_abs_paths <buffer-file> — flags every absolute-path token in the whole brief
# (section [3] included) that is not under an allowed root. A token opens at start-of-line
# or after one of: space, double-quote, single-quote, backtick, "(", "=", ":", tab, "[",
# ",", "<", "*", "|", "{" — the shapes a path is actually introduced by in prose, JSON and
# fenced YAML — and is a run of path characters starting with "/". A bare "/dev/null" is
# never flagged, and a single-segment "/name" or "/plugin:cmd" token that does not exist on
# disk reads as a slash command, not a path. URLs are stripped first so "https://" is never
# read as a filesystem path (its scheme colon would otherwise satisfy the boundary class);
# "file://" loses only its scheme, so its path is still scanned. Allowed roots are masked
# out first (literal match, longest first, whole path components only) so a root holding a
# space or "@" is never cut into a false off-root prefix.
scan_abs_paths() {
  local buf="$1" scrubbed masked roots_file dq sq bt tb cls boundary pattern lineno match token
  scrubbed=$(mktemp)
  masked=$(mktemp)
  roots_file=$(mktemp)
  dq='"'; sq="'"; bt='`'; tb=$'\t'
  cls="[^[:space:]${dq}${sq}${bt})]"
  # file:// names a local path, not a network resource: drop only the scheme so the
  # path itself, and the boundary character before it, survive into the scan.
  sed -E "s#(^|[^A-Za-z0-9+.-])file://#\\1#g" "$buf" \
    | sed -E "s#[A-Za-z][A-Za-z0-9+.-]*://${cls}*##g" > "$scrubbed"

  cp "$scrubbed" "$masked"
  printf '%s' "$ROOTS_STR" | awk 'NF { print length($0) "\t" $0 }' \
    | sort -t "$tb" -k1,1nr | cut -f2- > "$roots_file"
  if [[ -s "$roots_file" ]]; then
    awk -v rf="$roots_file" '
      BEGIN {
        n = 0
        while ((getline r < rf) > 0) { n++; roots[n] = r }
        close(rf)
      }
      {
        line = $0
        for (k = 1; k <= n; k++) {
          r = roots[k]
          rlen = length(r)
          if (rlen == 0) continue
          out = ""; rest = line
          while ((i = index(rest, r)) > 0) {
            before = (i > 1) ? substr(rest, i - 1, 1) : substr(out, length(out), 1)
            after = substr(rest, i + rlen, 1)
            okbefore = (before == "" || before !~ /[A-Za-z0-9_.+~%\/-]/)
            okafter = (after == "" || after == "/" || after !~ /[A-Za-z0-9_.+~%-]/)
            if (okbefore && okafter) {
              out = out substr(rest, 1, i - 1) "\001ROOT\001"
              rest = substr(rest, i + rlen)
            } else {
              out = out substr(rest, 1, i)
              rest = substr(rest, i + 1)
            }
          }
          line = out rest
        }
        print line
      }
    ' "$masked" > "${masked}.tmp" || die2 "root-masking awk failed"
    mv "${masked}.tmp" "$masked" || die2 "root-masking temp swap failed"
  fi
  rm -f "$roots_file"

  boundary="[ ${dq}${sq}${bt}(=:,[<*|{${tb}]"
  pattern="(^|${boundary})/[A-Za-z0-9_.+~%-]+(/[A-Za-z0-9_.+~%-]*)*"
  while IFS=: read -r lineno match; do
    [[ -n "$match" ]] || continue
    case "$match" in
      /*) token="$match" ;;
      ?*) token="${match#?}" ;;
      *) continue ;;
    esac
    if [[ "$token" == "/dev/null" ]]; then continue; fi
    if [[ "${token#/}" != */* && "$token" =~ ^/[a-z][a-z0-9-]*(:[a-z][a-z0-9-]*)?$ && ! -e "$token" ]]; then
      continue
    fi
    if is_allowed_path "$token"; then continue; fi
    record_issue "absolute path outside allowed roots" "$token"
  done < <(grep -noE "$pattern" "$masked" || true)
  rm -f "$scrubbed" "$masked"
}

# plain_path_exists <path> — rc 0 when a plain-path ref names an existing file:
# plugin-root-relative, under any ledger workspace_path, under the ledger's .context dir,
# or under that dir's parent (a path written as ".context/...").
plain_path_exists() {
  local path="$1" wp
  if [[ -f "$PROOT/$path" ]]; then return 0; fi
  while IFS= read -r wp; do
    [[ -n "$wp" ]] || continue
    if [[ -f "$wp/$path" ]]; then return 0; fi
  done <<< "$WSPATHS_STR"
  if [[ -f "$CTX_DIR/$path" ]]; then return 0; fi
  if [[ -f "$(dirname "$CTX_DIR")/$path" ]]; then return 0; fi
  return 1
}

# check_ref_resolves <ref> — "path:line" resolves when the file exists
# (plugin-root-relative, else under a ledger workspace_path) and 1<=line<=line count.
# "artifact#anchor" resolves when the artifact exists under the ledger's .context dir and
# carries a "## <anchor>" heading. Anything else is a plain path (plain_path_exists).
# Explicit returns only: a bare false `[[ ]]` or `grep` would trip errexit first.
check_ref_resolves() {
  local ref="$1" file lineno fpath n wp anchor art apath
  if [[ "$ref" =~ ^(.+):([0-9]+)$ ]]; then
    file="${BASH_REMATCH[1]}"; lineno="${BASH_REMATCH[2]}"
    fpath="$PROOT/$file"
    if [[ ! -f "$fpath" ]]; then
      fpath=""
      while IFS= read -r wp; do
        [[ -n "$wp" ]] || continue
        if [[ -f "$wp/$file" ]]; then fpath="$wp/$file"; break; fi
      done <<< "$WSPATHS_STR"
      if [[ -z "$fpath" ]]; then return 1; fi
    fi
    n=$(wc -l < "$fpath" | tr -d ' ')
    if [[ "$lineno" -ge 1 && "$lineno" -le "$n" ]]; then return 0; fi
    return 1
  elif [[ "$ref" == *"#"* ]]; then
    art="${ref%%#*}"; anchor="${ref#*#}"
    apath="$CTX_DIR/$art"
    if [[ ! -f "$apath" ]]; then return 1; fi
    if grep -qE "^## $(regex_escape "$anchor")[[:space:]]*\$" "$apath"; then return 0; fi
    return 1
  else
    if plain_path_exists "$ref"; then return 0; fi
    return 1
  fi
}

# --- canon extraction -----------------------------------------------------------

# The fenced ```text block under "## <alias>" in model-prompting.md, exactly as
# cache-lint.sh's own canon check reads it — a second extraction that disagreed with the
# lint would make a byte-identical brief fail the very lint it exists to pass. Empty
# output for an alias with a heading but no block (haiku); the caller checks the heading
# exists separately to tell that apart from an unknown alias.
model_block_extract() {
  local alias="$1" canon="$2"
  awk -v a="$alias" '
    $0 ~ "^## " a "($| )" { inalias = 1; next }
    /^## / { inalias = 0 }
    inalias && $0 == "```text" { infence = 1; next }
    infence && $0 == "```" { exit }
    infence { print }
  ' "$canon"
}

# The "### #tpl-<stage> — …" block, heading through the line before the next "## " or
# "### " heading (or EOF) — "####"/"#####" sub-headings stay inside, since they belong to
# it. The "## " stop keeps the last block before a new H2 from swallowing that section.
tpl_block_extract() {
  local start="$1" canon="$2"
  awk -v start="$start" '
    NR == start { c = 1 }
    c && NR > start && /^###? / { exit }
    c { print }
  ' "$canon"
}

# --- render --------------------------------------------------------------------------

cmd_render() {
  local task="$1" state="$2" orch="$3"
  valid_task_id "$task" || die2 "malformed task id: $task (expected e.g. DV1)"
  command -v jq > /dev/null 2>&1 || die2 "jq is required"
  source_state_lib
  [[ -n "$state" ]] || state="$(resolve_state)"
  [[ -r "$state" ]] || die2 "ledger unreadable: $state"

  PROOT="$(plugin_root)"
  local STATE="$state" TASK_ID="$task"
  local CTX_DIR
  CTX_DIR="$(cd "$(dirname "$STATE")" && pwd -P)" || die2 "ledger directory unreadable: $STATE"
  # The ledger's own .context root: section [3] inlines the ledger verbatim, so its
  # directory must be allowed even when no workspace_path row and no --orch-root
  # happen to cover it.
  add_root "$CTX_DIR"

  local known
  known=$(jq -r --arg id "$TASK_ID" '.tasks[$id] != null' "$STATE" 2> /dev/null) \
    || die2 "ledger is not valid JSON: $STATE"
  [[ "$known" == "true" ]] || die2 "unknown task id: $TASK_ID"

  local SC="$PROOT/skills/shared/stage-contracts.md"
  local MP="$PROOT/skills/shared/model-prompting.md"
  local CL="$PROOT/skills/worktask/scripts/cache-lint.sh"
  [[ -f "$SC" ]] || die2 "canon source missing: skills/shared/stage-contracts.md"
  [[ -f "$MP" ]] || die2 "canon source missing: skills/shared/model-prompting.md"
  [[ -f "$CL" ]] || die2 "canon source missing: skills/worktask/scripts/cache-lint.sh"

  local STAGE MODEL AGENT
  STAGE=$(jq -r --arg id "$TASK_ID" '.tasks[$id].metadata.stage // empty' "$STATE")
  [[ "$STAGE" =~ ^[A-Z]{2}$ ]] || die2 "tasks.$TASK_ID.metadata.stage is missing or malformed"
  MODEL=$(jq -r --arg id "$TASK_ID" '.tasks[$id].metadata.model // empty' "$STATE")
  [[ "$MODEL" =~ ^[a-z][a-z0-9_-]*$ ]] || die2 "tasks.$TASK_ID.metadata.model is missing or malformed"
  AGENT=$(jq -r --arg id "$TASK_ID" '.tasks[$id].metadata.agent // empty' "$STATE")

  local allow_row AGENT_BASENAME ARTIFACT_BASENAME
  allow_row=$(bash "$CL" --allow-list --stage "$STAGE" 2> /dev/null | head -1) || true
  [[ -n "$allow_row" ]] || die2 "unknown stage: $STAGE (cache-lint.sh --allow-list has no row)"
  AGENT_BASENAME=$(printf '%s' "$allow_row" | cut -f2)
  ARTIFACT_BASENAME=$(printf '%s' "$allow_row" | cut -f3)

  local AGENT_FILE="agents/${AGENT_BASENAME}.md"
  [[ -f "$PROOT/$AGENT_FILE" ]] || die2 "canon source missing: $AGENT_FILE"
  local MARKER_LINE
  MARKER_LINE=$(grep -n -m1 -F -- "<!-- output-sections:begin stage=${STAGE} -->" "$PROOT/$AGENT_FILE" \
    | cut -d: -f1) || true
  [[ -n "$MARKER_LINE" ]] || die2 "canon section absent: $AGENT_FILE#output-sections:begin stage=${STAGE}"

  local ARTIFACT
  ARTIFACT=$(jq -r --arg id "$TASK_ID" '.tasks[$id].artifact // .tasks[$id].metadata.artifact // empty' "$STATE")
  if [[ -z "$ARTIFACT" ]]; then
    local n
    n=$(jq -r --arg id "$TASK_ID" '.tasks[$id].metadata.run_index // .run_index // 0' "$STATE")
    ARTIFACT=".context/${ARTIFACT_BASENAME}-${n}.md"
  fi

  local SUBJECT
  SUBJECT=$(jq -r --arg id "$TASK_ID" '.tasks[$id].metadata.subject // .tasks[$id].subject // empty' "$STATE")

  local WORKTASK_ID PLAN_FILE PLAN_BASENAME
  WORKTASK_ID=$(jq -r '.worktask_id // .metadata.worktask_id // "unknown"' "$STATE")
  PLAN_FILE=$(jq -r '.plan_file // .metadata.plan_file // empty' "$STATE")
  [[ -n "$PLAN_FILE" ]] || die2 "ledger has no plan_file"
  PLAN_BASENAME="${PLAN_FILE##*/}"

  # Every declared workspace tree, gathered across ALL rows (not just this task's own) —
  # a DR brief inlines a multi-stream ledger whose OTHER trees are ledger facts the guard
  # must still allow.
  WSPATHS_STR=""
  while IFS= read -r wp; do
    [[ -n "$wp" ]] || continue
    WSPATHS_STR="${WSPATHS_STR}${wp}"$'\n'
    add_root "$wp"
  done < <(jq -r '.tasks[]?.metadata.workspace_path // empty' "$STATE" 2> /dev/null)

  local banner_out WORKSPACE_ROOT
  if [[ -n "$orch" ]]; then
    banner_out=$(bash "$PROOT/skills/worktask/scripts/workspace-root-banner.sh" \
      --task "$TASK_ID" --state "$STATE" --orch-root "$orch") \
      || die2 "workspace-root-banner.sh failed for task $TASK_ID"
  else
    banner_out=$(bash "$PROOT/skills/worktask/scripts/workspace-root-banner.sh" \
      --task "$TASK_ID" --state "$STATE") \
      || die2 "workspace-root-banner.sh failed for task $TASK_ID"
  fi
  WORKSPACE_ROOT="${banner_out#WORKSPACE_ROOT=}"
  add_root "$WORKSPACE_ROOT"

  local rr_out
  rr_out=$(bash "$PROOT/skills/shared/scripts/resolve-root.sh" 2> /dev/null) || rr_out=""
  add_root "$rr_out"
  local ctx_out
  ctx_out=$(WORKSPACE_ROOT="$WORKSPACE_ROOT" corpflow_context_dir 2> /dev/null) || ctx_out=""
  add_root "$ctx_out"

  # ---- Section [1]: contract-reminder — byte-identical for every stage ----
  local req_in_line req_out_line
  req_in_line=$(grep -n -m1 -E '^## Required Inputs \(handoff-protocol\)$' "$SC" | cut -d: -f1) || true
  [[ -n "$req_in_line" ]] || die2 "canon section absent: skills/shared/stage-contracts.md#Required Inputs"
  req_out_line=$(grep -n -m1 -E '^## Required Outputs \(handoff-protocol\)$' "$SC" | cut -d: -f1) || true
  [[ -n "$req_out_line" ]] || die2 "canon section absent: skills/shared/stage-contracts.md#Required Outputs"

  # ---- Section [4]: this stage's contract block ----
  local stage_lc tpl_line tpl_block
  stage_lc=$(printf '%s' "$STAGE" | tr '[:upper:]' '[:lower:]')
  tpl_line=$(grep -n -m1 -E "^### #tpl-${stage_lc} " "$SC" | cut -d: -f1) || true
  [[ -n "$tpl_line" ]] || die2 "canon section absent: skills/shared/stage-contracts.md#tpl-${stage_lc}"
  tpl_block=$(tpl_block_extract "$tpl_line" "$SC")

  # ---- Section [4b]: this task's model discipline block ----
  grep -q -E "^## ${MODEL}(\$| )" "$MP" || die2 "canon section absent: skills/shared/model-prompting.md##${MODEL}"
  local model_block
  model_block=$(model_block_extract "$MODEL" "$MP")

  # ---- Section [5]: refs.dev, one ref per DV ledger row, DR/SR/QA/DC/RE only ----
  local DEV_REFS_STR="" r base
  case "$STAGE" in
    DR | SR | QA | DC | RE)
      while IFS= read -r r; do
        [[ -n "$r" ]] || continue
        base="${r%%#*}"
        [[ -f "$CTX_DIR/$base" ]] || continue
        DEV_REFS_STR="${DEV_REFS_STR}${r}"$'\n'
      done < <(jq -r '
        .tasks | to_entries
        | map(select(.value.metadata.stage == "DV" and (.key | test("^DV[0-9]+$"))))
        | sort_by(.key | ltrimstr("DV") | tonumber)
        | .[] | ((.value.artifact // .value.metadata.artifact // empty) | split("/") | last) + "#files-changed"
      ' "$STATE")
      ;;
  esac

  local AR_REF=""
  local ar_exists
  ar_exists=$(jq -r '.tasks.AR0 != null' "$STATE")
  if [[ "$ar_exists" == "true" ]]; then
    local ar_n ar_file
    ar_n=$(jq -r '.tasks.AR0.metadata.run_index // .run_index // 0' "$STATE")
    ar_file="architecture-${ar_n}.md"
    if [[ -f "$CTX_DIR/$ar_file" ]]; then AR_REF="${ar_file}#decisions"; fi
  fi

  # ---- metadata.context_refs: a JSON array, or (state-ledger.md's preferred shape) a
  # JSON-encoded string holding that array; anything else is a ledger defect, not a ref
  # to drop silently. Decoded per row since the two shapes can mix across a ledger. ----
  local RAW_CTXREFS_STR="" ctxrefs_type
  ctxrefs_type=$(jq -r --arg id "$TASK_ID" '.tasks[$id].metadata.context_refs | type' "$STATE")
  case "$ctxrefs_type" in
    null) : ;;
    array)
      while IFS= read -r r; do
        if [[ -n "$r" ]]; then RAW_CTXREFS_STR="${RAW_CTXREFS_STR}${r}"$'\n'; fi
      done < <(jq -r --arg id "$TASK_ID" '.tasks[$id].metadata.context_refs[]' "$STATE")
      ;;
    string)
      local ctxrefs_raw ctxrefs_decoded
      ctxrefs_raw=$(jq -r --arg id "$TASK_ID" '.tasks[$id].metadata.context_refs' "$STATE")
      ctxrefs_decoded=$(printf '%s' "$ctxrefs_raw" | jq -r \
        'if type == "array" then .[] else error("not a JSON array") end' 2> /dev/null) \
        || die2 "tasks.$TASK_ID.metadata.context_refs is a string but not a JSON array: $ctxrefs_raw"
      while IFS= read -r r; do
        if [[ -n "$r" ]]; then RAW_CTXREFS_STR="${RAW_CTXREFS_STR}${r}"$'\n'; fi
      done <<< "$ctxrefs_decoded"
      ;;
    *) die2 "tasks.$TASK_ID.metadata.context_refs has unexpected type: $ctxrefs_type" ;;
  esac

  # A plain-path entry is emitted only when its file exists, the same gate refs.dev and
  # AR_REF apply; file:line and artifact#anchor entries always emit, so an unresolved one
  # fails the guard below.
  local CONTEXT_REFS_STR="" cr
  while IFS= read -r cr; do
    if [[ -z "$cr" ]]; then continue; fi
    if [[ "$cr" =~ ^.+:[0-9]+$ || "$cr" == *"#"* ]]; then
      CONTEXT_REFS_STR="${CONTEXT_REFS_STR}${cr}"$'\n'
    elif plain_path_exists "$cr"; then
      CONTEXT_REFS_STR="${CONTEXT_REFS_STR}${cr}"$'\n'
    fi
  done <<< "$RAW_CTXREFS_STR"

  # ---- Assemble: buffer the whole brief before anything reaches stdout ----
  BUF=$(mktemp)
  # shellcheck disable=SC2064  # expand now: BUF is a plain path, gone by EXIT time otherwise
  trap "rm -f '$BUF'" EXIT
  emit() { printf '%s\n' "$1" >> "$BUF"; }

  emit "<<<contract-reminder>>>"
  emit "Every \`ref:\` line below is a fact this brief did not verify for you. Resolve a"
  emit "file:line ref by opening the file at that line; resolve an artifact#anchor ref by"
  emit "opening the artifact and finding the \"## <anchor>\" heading; resolve a plain path"
  emit "ref by opening that file directly. Act on it only after you have checked it"
  emit "yourself."
  emit ""
  emit "Required Inputs: skills/shared/stage-contracts.md:${req_in_line}"
  emit "Required Outputs: skills/shared/stage-contracts.md:${req_out_line}"

  emit "<<<worktask-header>>>"
  emit "worktask_id: ${WORKTASK_ID}"
  emit "plan_file: ${PLAN_FILE}"

  emit "<<<state-json>>>"
  emit '```json'
  jq '.' "$STATE" >> "$BUF"
  emit '```'

  emit "<<<stage-contract>>>"
  printf '%s\n' "$tpl_block" >> "$BUF"

  emit "<<<model-discipline>>>"
  if [[ -n "$model_block" ]]; then printf '%s\n' "$model_block" >> "$BUF"; fi

  emit "<<<task-description>>>"
  emit "task_id: ${TASK_ID}"
  emit "stage: ${STAGE}"
  if [[ -n "$AGENT" ]]; then emit "agent: ${AGENT}"; fi
  emit "model: ${MODEL}"
  emit "artifact: ${ARTIFACT}"
  if [[ -n "$SUBJECT" ]]; then emit "subject: ${SUBJECT}"; fi
  emit "ref: ${PLAN_BASENAME}#requirements"
  emit "ref: ${PLAN_BASENAME}#acceptance-criteria"
  emit "ref: skills/shared/stage-contracts.md:${tpl_line}"
  emit "ref: ${AGENT_FILE}:${MARKER_LINE}"
  while IFS= read -r r; do
    if [[ -n "$r" ]]; then emit "ref: $r"; fi
  done <<< "$DEV_REFS_STR"
  while IFS= read -r r; do
    if [[ -n "$r" ]]; then emit "ref: $r"; fi
  done <<< "$CONTEXT_REFS_STR"
  if [[ -n "$AR_REF" ]]; then emit "ref: ${AR_REF}"; fi

  emit "<<<retry-hints>>>"

  emit "<<<stage-banners>>>"
  emit "WORKSPACE_ROOT=${WORKSPACE_ROOT}"

  # ---- Guard: buffered content only, never partial ----
  while IFS= read -r r; do
    case "$r" in
      'ref: '*)
        local refval="${r#ref: }"
        check_ref_resolves "$refval" || record_issue "unresolved ref" "$refval"
        ;;
    esac
  done < "$BUF"
  scan_abs_paths "$BUF"

  if [[ -n "$ISSUES" ]]; then
    printf '%s' "$ISSUES" >&2
    exit 1
  fi
  cat "$BUF"
}

main() {
  local cmd="render" task="" state="" orch=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --state) [[ $# -ge 2 ]] || usage_error "--state requires a value"; state="$2"; shift 2 ;;
      --orch-root) [[ $# -ge 2 ]] || usage_error "--orch-root requires a value"; orch="$2"; shift 2 ;;
      --self-test) cmd="self-test"; shift ;;
      -h | --help) print_help ;;
      --) shift ;;
      -*) usage_error "unknown argument: $1" ;;
      *)
        [[ -z "$task" ]] || usage_error "unexpected argument: $1"
        task="$1"; shift ;;
    esac
  done
  case "$cmd" in
    self-test)
      local selftest_lib
      selftest_lib="$(dirname "${BASH_SOURCE[0]}")/brief-compose-selftest.sh"
      if [[ -r "$selftest_lib" ]]; then
        # shellcheck source=SCRIPTDIR/brief-compose-selftest.sh
        . "$selftest_lib"
      else
        printf >&2 'brief-compose: self-test harness unreachable at %s — plugin install broken\n' "$selftest_lib"
        exit 2
      fi
      self_test
      ;;
    render)
      [[ -n "$task" ]] || usage_error "usage: brief-compose.sh <TASK_ID> [--state <path>] [--orch-root <path>]"
      cmd_render "$task" "$state" "$orch"
      ;;
  esac
}

main "$@"
