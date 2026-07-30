#!/usr/bin/env bash
# @description branch-lib.sh — sourceable library shared by branch-name.sh (PL-stage
#   rename entry point) and fn-preflight.sh (surviving FN validator commands).
#
#   Dependency-free by construction: sources nothing, sets no shell options, does no
#   jq/git probing at load time, and has no side effects at load beyond idempotent
#   variable init. Its only failure mode is absence, which callers detect and report
#   loudly — see each caller's own guard.
#
#   Symbols: BRANCH_TYPES, branch_type_regex, branch_is_conventional, resolve_goal,
#   derive_type, derive_slug, target_branch_name, meta_json, audit_fn, fn_batch_scope,
#   resolve_base_ref.
#
# Minimum shell: bash 3.2+ (macOS default).

# Anti-execution guard — MUST be the first statement. Fires only when this file is
# run directly ($0 == BASH_SOURCE[0]); a sourcing caller always has a different $0.
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  printf >&2 'branch-lib.sh: this is a library — source it, do not execute it directly\n'
  exit 2
fi

# Idempotent carve-out: a `set -u` caller reading this before fn_batch_scope runs
# must not explode on an unset variable.
: "${SCOPE_REASON:=}"

# ---------- Branch type vocabulary — the only regex site in the repo ----------
# Newline-delimited, NOT an array and NOT `readonly`: a second `readonly` assignment
# is rc 1 and kills a `set -e` caller (this file's own bats source it twice), and a
# space-delimited list yields one token under a caller's `IFS=$'\n\t'`. Accept list
# (12) is deliberately wider than what derive_type ever emits (10): `feat` and `style`
# are accepted so an existing short-form/style branch is never churned, but neither
# is ever generated. Canonical prose: skills/shared/git-conventions.md § Branch Naming.
BRANCH_TYPES='feat
feature
fix
refactor
perf
docs
chore
test
ci
build
style
revert'

# Builds the `type1|type2|...` alternation from BRANCH_TYPES, skipping any blank
# entry (a blank entry would produce `^(feat||fix)/…`, which BSD grep rejects with
# rc 2 — indistinguishable from "no match" inside a bare `if grep -Eq`).
branch_type_regex() {
  local line first=1 regex=""
  local IFS=$'\n'
  for line in $BRANCH_TYPES; do
    [ -n "$line" ] || continue
    if [ "$first" -eq 1 ]; then
      regex="$line"
      first=0
    else
      regex="$regex|$line"
    fi
  done
  printf '%s' "$regex"
}

# Predicate: is <name> a conventional `<type>/<slug>` branch? The sole matching site
# — nobody else greps this pattern. 0 = yes, 1 = no (documented exemption: a predicate
# that cannot say "no" is useless), 2 = internal regex fault (empty vocabulary).
branch_is_conventional() {
  local name="${1:-}" regex rc=0
  regex=$(branch_type_regex)
  if [ -z "$regex" ]; then
    printf >&2 'branch-lib: empty type vocabulary — cannot evaluate\n'
    return 2
  fi
  printf '%s' "$name" | grep -Eq "^(${regex})/[a-z0-9._-]+\$" && rc=0 || rc=$?
  case "$rc" in
    0) return 0 ;;
    1) return 1 ;;
    *) return 2 ;;
  esac
}

# ---------- Goal resolution ----------
# Ranked, first-non-empty-wins: explicit argument, then the ledger goal, then the
# worktask id. Shell `-z` semantics deliberately rank PAST an empty string (unlike
# jq's `//`, which treats "" as truthy and stops there) — the ranked fallbacks are
# the point of this function, not a corner case to special-case away.
resolve_goal() {
  local g="${1:-}"
  if [ -z "$g" ] && command -v jq > /dev/null 2>&1; then
    g=$(jq -r '.facts.goal // ""' "${STATE_PATH:-.context/state.json}" 2> /dev/null || printf '')
    [ "$g" = "null" ] && g=""
  fi
  if [ -z "$g" ] && command -v jq > /dev/null 2>&1; then
    g=$(jq -r '.worktask_id // ""' "${STATE_PATH:-.context/state.json}" 2> /dev/null || printf '')
    [ "$g" = "null" ] && g=""
  fi
  printf '%s' "$g"
}

# ---------- Pure derivation (no state, no git) ----------
# Conventional-commit type from a free-text goal. Unmatched goals fall back to
# `feature` — the long form is now the canonical generated default (Q3); `feat` is
# never emitted, only accepted for pre-existing short-form branches.
derive_type() {
  local g t="feature"
  g=$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')
  case "$g" in
    *revert*) t="revert" ;;
    *"fix "* | *bug* | *defect* | *hotfix* | *crash*) t="fix" ;;
    *refactor*) t="refactor" ;;
    *perf* | *optimi*) t="perf" ;;
    *docs* | *document*) t="docs" ;;
    *test* | *coverage*) t="test" ;;
    *ci\ * | *pipeline*) t="ci" ;;
    *build* | *packaging*) t="build" ;;
    *chore* | *bump* | *dependency*) t="chore" ;;
    *) t="feature" ;;
  esac
  printf '%s' "$t"
}

# Kebab slug from a free-text goal, <=48 chars, no leading/trailing '-'. `tr '\n' ' '`
# runs before the collapse: a multi-line task description (this function's caller may
# now pass one, unlike the old goal-only source) would otherwise survive as embedded
# newlines through `sed`/`cut`'s line-oriented view and yield a two-line slug, which
# then fails `git branch -m` outright.
derive_slug() {
  printf '%s' "${1:-}" |
    tr '\n' ' ' |
    tr '[:upper:]' '[:lower:]' |
    sed -e 's/[^a-z0-9]\{1,\}/-/g' -e 's/^-*//' -e 's/-*$//' |
    cut -c1-48 | sed -e 's/-*$//'
}

# `<type>/<slug>`. No ticket: the naming path never resolves an issue (R6). Returns 1
# (no output) when the slug is empty — callers treat that as a no-op.
target_branch_name() {
  local t="${1:-}" s="${2:-}"
  [ -n "$s" ] || return 1
  printf '%s/%s' "$t" "$s"
}

# ---------- Audit helpers ----------
# meta_json k v k v … -> compact JSON object. Values are always strings. The
# <2-argument guard is not cosmetic: bash 3.2 errors on an empty array expansion
# under `set -u`, so the array must never reach jq empty.
meta_json() {
  command -v jq > /dev/null 2>&1 || {
    printf '{}'
    return 0
  }
  if [ $# -lt 2 ]; then
    printf '{}'
    return 0
  fi
  local args=() prog="{}" i=1
  while [ $# -gt 1 ]; do
    args+=(--arg "k$i" "$1" --arg "v$i" "$2")
    prog="$prog + {(\$k$i): \$v$i}"
    shift 2
    i=$((i + 1))
  done
  jq -cn "${args[@]}" "$prog"
}

# One audit row per outcome. Identity is read from the environment AT CALL TIME
# rather than set through a setter: an order-dependent global would silently write
# the wrong actor on a missed call, and a jq path built from a variable is dynamic
# program construction (rules/security.md). Defaults reproduce the FN-stage rows
# byte-for-byte; branch-name.sh overrides all three knobs for its PL-stage rows.
# Never fails the caller: an audit row is evidence, not a gate.
audit_fn() {
  local action="$1" result="$2" meta="${3:-}"
  local actor="${AUDIT_ACTOR:-project-manager}"
  local subj="${AUDIT_SUBJECT:-FN0}"
  local stage="${AUDIT_STAGE:-FN}"
  case "$stage" in
    [A-Z][A-Z]) ;;
    *) stage="FN" ;;
  esac
  [ -n "$meta" ] || meta='{}'
  local ts wid ri tid dk
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  wid=$(jq -r '.worktask_id // "unknown"' "${STATE_PATH:-.context/state.json}" 2> /dev/null || printf 'unknown')
  ri=$(jq -r '.run_index // 0' "${STATE_PATH:-.context/state.json}" 2> /dev/null || printf '0')
  tid=$(jq -r --arg s "$stage" '.stages[$s].task_id // ($s + "0")' \
    "${STATE_PATH:-.context/state.json}" 2> /dev/null || printf '%s0' "$stage")
  dk="$wid:$ri:$action"
  mkdir -p "${CONTEXT_DIR:-.context}/logs" 2> /dev/null || true
  if command -v jq > /dev/null 2>&1; then
    jq -cn --arg ts "$ts" --arg a "$action" --arg subj "$subj" --arg r "$result" \
      --arg t "$tid" --arg dk "$dk" --arg actor "$actor" --arg origin "$stage" --argjson m "$meta" \
      '{ts:$ts, actor:$actor, action:$a, subject:$subj, result:$r, task_id:$t,
        metadata:($m + {origin_stage:$origin, dedupe_key:$dk})}' \
      >> "${CONTEXT_DIR:-.context}/logs/audit.jsonl" 2> /dev/null || true
  fi
  return 0
}

# ---------- batch / incident scope guard ------------------------------------
# Re-derived, not mirrored: this file's only failure mode is absence (no jq probe,
# no fallible prologue at load time), so the "unreachable library cannot fail the
# guard that exempts batch runs" property holds without a partial local copy.
# Signals (any hit => self-disable):
#   1. MILESTONE_MODE=1        env override (tests, /megatask)
#   2. INCIDENT_MODE=1         env override (tests, incident runners)
#   3. state.json .metadata.milestone non-empty
#   4. state.json .stages.IR present — the emergency pipeline's marker stage
#   5. workspace.json present at $WORKSPACE_ROOT or $PWD
fn_batch_scope() {
  if [ "${MILESTONE_MODE:-0}" = "1" ]; then
    SCOPE_REASON="milestone_mode_env"
    return 0
  fi
  if [ "${INCIDENT_MODE:-0}" = "1" ]; then
    SCOPE_REASON="incident_mode_env"
    return 0
  fi
  if command -v jq > /dev/null 2>&1 && [ -f "${STATE_PATH:-.context/state.json}" ]; then
    local m
    m=$(jq -r '.metadata.milestone // ""' "${STATE_PATH:-.context/state.json}" 2> /dev/null || printf '')
    if [ -n "$m" ] && [ "$m" != "null" ]; then
      SCOPE_REASON="milestone_metadata"
      return 0
    fi
    if jq -e '.stages | has("IR")' "${STATE_PATH:-.context/state.json}" > /dev/null 2>&1; then
      SCOPE_REASON="incident_pipeline"
      return 0
    fi
  fi
  if [ -n "${WORKSPACE_ROOT:-}" ] && [ -f "${WORKSPACE_ROOT}/workspace.json" ]; then
    SCOPE_REASON="workspace_record"
    return 0
  fi
  if [ -f "${PWD}/workspace.json" ]; then
    SCOPE_REASON="workspace_record"
    return 0
  fi
  return 1
}

# ---------- integration-branch resolution -----------------------------------
# Single source of truth for "what is the integration branch", ranked:
#   1. $FN_BASE_REF                          explicit operator/test override
#   2. state.json .metadata.base_ref         stamped by PL0, mirrors task metadata
#   3. state.json .git.base_branch           legacy ledger field, orchestrator seed
#   4. workspace.json .git.base_branch       /megatask per-issue record
#   5. git symbolic-ref refs/remotes/origin/HEAD
#   -  unresolved                            reported, never guessed
# There is deliberately NO hardcoded literal. Callers degrade non-blocking.
resolve_base_ref() {
  local v="${FN_BASE_REF:-}"
  if [ -z "$v" ] && command -v jq > /dev/null 2>&1; then
    v=$(jq -r '.metadata.base_ref // empty' "${STATE_PATH:-.context/state.json}" 2> /dev/null || printf '')
    if [ -z "$v" ]; then
      v=$(jq -r '.git.base_branch // empty' "${STATE_PATH:-.context/state.json}" 2> /dev/null || printf '')
    fi
    if [ -z "$v" ]; then
      local ws="${WORKSPACE_ROOT:-$PWD}/workspace.json"
      if [ -f "$ws" ]; then
        v=$(jq -r '.git.base_branch // empty' "$ws" 2> /dev/null || printf '')
      fi
    fi
  fi
  if [ -z "$v" ]; then
    v=$(git symbolic-ref --short refs/remotes/origin/HEAD 2> /dev/null || printf '')
  fi
  [ "$v" = "null" ] && v=""
  printf '%s' "$v"
}
