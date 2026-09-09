#!/usr/bin/env bash
# @description fn-preflight-cmds.sh — sourceable library holding every fn-preflight.sh
#   subcommand body and the four helpers they share. fn-preflight.sh keeps only the
#   documentation header (which `usage()` reads back out of its own `$0`), the sibling
#   resolution, argument parsing and dispatch.
#
#   Sourced by exactly one caller. The split is a size split, not a reuse seam: the
#   contract, the exit codes and the prose that documents them all live in
#   fn-preflight.sh, and every behaviour here is specified there.
#
#   Reads these globals from the caller, none of which it defines: STATE_PATH,
#   CONTEXT_DIR, BODY_FILE, SCRIPT_DIR, LIB_PATH. Also calls branch-lib.sh's
#   audit_fn, meta_json, fn_batch_scope and resolve_base_ref, so the caller must
#   source that library FIRST — fn-preflight.sh's exit-3 guard is what enforces it.
#
#   Symbols: resolve_issue, sanitise_stream, VE_ACTION, ve_row_result, resolve_git_ref,
#   cmd_attachments, cmd_staging, cmd_pr_body, cmd_validate_pr, cmd_continuity,
#   cmd_branch_divergence, cmd_issue_close_required, _bs_override_on,
#   _bs_fork_candidate, cmd_base_sanity.
#
# Minimum shell: bash 3.2+ (macOS default).

# Anti-execution guard — MUST be the first statement. Fires only when this file is
# run directly ($0 == BASH_SOURCE[0]); a sourcing caller always has a different $0.
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  printf >&2 'fn-preflight-cmds.sh: this is a library — source it, do not execute it directly\n'
  exit 2
fi

# ---------- Issue resolver (ranked, first-match-wins) ----------
# 1. state.json .metadata.github_issue_url  — trailing integer of /issues/<N>.
# 2. .context/gh-issue.json .url (trailing int) or .number — follow-up-run anchor.
# 3. state.json .metadata.github_issue_number — megatask per-issue mode.
# 4. branch parse: leading <type>/<NNN>-<slug> shape (externally-named-branch
#    fallback — the shape both branch generators actually produce), else first
#    #NNN in the last 5 commits. NOT a trailing integer: a ticket-less
#    `feature/<slug-ending-in-digit>` branch must not resolve a bogus issue number.
resolve_issue() {
  local n=""
  if command -v jq > /dev/null 2>&1; then
    n=$(jq -r '.metadata.github_issue_url // empty' "$STATE_PATH" 2> /dev/null \
      | grep -oE '[0-9]+$' || true)
    [[ -z "$n" ]] && n=$(jq -r 'if .url then .url elif .number then (.number|tostring) else empty end' \
      "${CONTEXT_DIR}/gh-issue.json" 2> /dev/null | grep -oE '[0-9]+$' || true)
    [[ -z "$n" ]] && n=$(jq -r '.metadata.github_issue_number // empty' "$STATE_PATH" 2> /dev/null || true)
  fi
  [[ -z "$n" ]] && n=$(git rev-parse --abbrev-ref HEAD 2> /dev/null \
    | sed -nE 's#^[a-zA-Z]+/([0-9]+)-.*#\1#p' || true)
  [[ -z "$n" ]] && n=$(git log --oneline -n 5 2> /dev/null | grep -oE '#[0-9]+' | head -1 | tr -d '#' || true)
  printf '%s' "$n"
}

# Parity with fn_batch_scope's shared signals is pinned by fn-preflight.bats "F14"
# and branch-lib.bats.

# ---------- sanitiser bridge ------------------------------------------------
# Reads a body on stdin, writes the sanitised body to stdout.
# The rule set is publish-pl-issue.sh's `sanitise_body`, reused verbatim — issue
# bodies and PR bodies must strip identically, and the fixture suite proves only
# that one implementation. Never reimplement or extend it here.
#
# The source happens in a subshell for three reasons: this script runs
# `set -euo pipefail` while the library is written for bare `set -u` (any non-zero
# status in its ~1600-line prologue would abort us); the library's globals stay out
# of our namespace; and its `exit`-capable `fatal`/`defer` cannot terminate the
# preflight. The dummy positional is required — the library iterates `"$@"`, which
# is an unbound-variable error on bash 3.2 when empty under `set -u`.
#
# Exit 97 = library unreachable or refused to source; 98 = symbol missing. Both are
# blocking: a working-folder path in a published body must be structurally
# impossible, and a fail-open degrade would turn that into "usually".
# Batch and incident runs do reach here, but treat both statuses as non-blocking,
# so a broken plugin cache still cannot wedge /megatask.
sanitise_stream() {
  (
    set +e +o pipefail
    # shellcheck disable=SC1090
    PUBLISH_LIB_ONLY=1 . "$LIB_PATH" --fn-preflight > /dev/null 2>&1 || exit 97
    command -v sanitise_body > /dev/null 2>&1 || exit 98
    sanitise_body
  )
}

# ---------- visual-evidence audit-row reader --------------------------------
VE_ACTION="visual_evidence_pr_emitted"
# $1 = worktask_id, $2 = run_index. Echoes ok|skipped, or empty when no row.
# Matching on the run's dedupe key (not the action alone) is what stops a row from
# an earlier run index satisfying the gate.
# The key grammar is emitted by attach-visual-evidence.sh `emit_pr` — keep in sync.
ve_row_result() {
  local dk="$1:$2:visual_evidence:pr" audit="${CONTEXT_DIR}/logs/audit.jsonl" r=""
  [[ -f "$audit" ]] || {
    printf ''
    return 0
  }
  if command -v jq > /dev/null 2>&1; then
    r=$(jq -r --arg a "$VE_ACTION" --arg dk "$dk" \
      'select(.action == $a) | select(.metadata.dedupe_key == $dk) | .result' \
      "$audit" 2> /dev/null | tail -1 || true)
  fi
  if [[ -z "$r" ]]; then
    # jq-less / malformed-line fallback: substring match on the same two fields.
    r=$(grep -F "\"$VE_ACTION\"" "$audit" 2> /dev/null |
      grep -F "\"dedupe_key\":\"$dk\"" |
      tail -1 | grep -oE '"result":"[a-z_]+"' | cut -d'"' -f4 || true)
  fi
  printf '%s' "$r"
}

# A base ref may be stored bare (`master`) or remote-qualified (`origin/release/v2`
# — the form workspace-modes.md documents). Map either onto something git resolves,
# which is what lets both stored shapes work without normalising the stored value.
#
# The REMOTE-TRACKING ref is preferred over a same-named local branch. Trying the bare
# name first resolved a stale local copy whenever one existed, and a stale base makes
# the diff measured against it wrong in the blocking direction: base-sanity reported a
# 70-file diff against a ledger claiming 18 and refused a finalization that was in fact
# correct, while the only escape it signposts is the override that would also mask a
# REAL wrong-base finding. Third patch to this resolution logic, so reordering alone
# was rejected: it trades one silent wrong answer for another. Divergence is announced
# on stderr with both names and both ahead-counts, and callers must not swallow it.
resolve_git_ref() {
  local name="$1" bare="${1#origin/}" c remote="" local_ref="" counts behind ahead upstream

  # The branch's own configured upstream is tried first, because `origin` is not always the
  # canonical remote. In a fork workflow — origin = fork, upstream = canonical — hardcoding
  # origin/ picks the stale fork ref, and base-sanity then measures the diff against it and
  # blocks a correctly-based PR. Falls through to origin/ when no upstream is set, so the
  # single-remote case resolves exactly as before.
  # Short branch name, not refs/heads/: `@{upstream}` rejects a full refname outright
  # ("fatal: no such branch"), which silently yielded no upstream and fell through to origin/.
  upstream=$(git rev-parse --verify --quiet --abbrev-ref "${bare}@{upstream}" 2> /dev/null || printf '')
  for c in ${upstream:+"$upstream"} "origin/$bare" "refs/remotes/origin/$bare"; do
    if git rev-parse --verify --quiet "$c" > /dev/null 2>&1; then remote="$c"; break; fi
  done
  git rev-parse --verify --quiet "refs/heads/$bare" > /dev/null 2>&1 && local_ref="refs/heads/$bare"

  if [[ -n "$remote" ]]; then
    if [[ -n "$local_ref" ]] &&
       [[ "$(git rev-parse "$remote" 2> /dev/null)" != "$(git rev-parse "$local_ref" 2> /dev/null)" ]]; then
      # --left-right --count on a symmetric range: left = remote-only, right = local-only.
      counts=$(git rev-list --left-right --count "${remote}...${local_ref}" 2> /dev/null || printf '')
      behind=${counts%%[!0-9]*}; ahead=${counts##*[!0-9-]}
      printf >&2 'WARNING: base ref %s is ambiguous — %s and %s have diverged.\n' \
        "$name" "$remote" "$local_ref"
      printf >&2 '  %s is ahead by %s commit(s); %s is ahead by %s commit(s).\n' \
        "$remote" "${behind:-?}" "$local_ref" "${ahead:-?}"
      printf >&2 '  Resolving to %s. Pass FN_BASE_REF=%s to force the local branch.\n' \
        "$remote" "$local_ref"
    fi
    printf '%s' "$remote"
    return 0
  fi

  # No remote-tracking ref: fall back exactly as before, so a purely local base,
  # a tag or a raw revision still resolves.
  for c in "$name" "$local_ref"; do
    [[ -n "$c" ]] || continue
    if git rev-parse --verify --quiet "$c" > /dev/null 2>&1; then
      printf '%s' "$c"
      return 0
    fi
  done
  return 1
}

# ---------- Commands ----------
# A file staged by an earlier stage and then edited again by a later one ships the STAGED
# bytes while every report describes the worktree: QA and DC routinely edit files FN already
# has in the index, and two of two observed runs hit it.
#
# The predicate is a set INTERSECTION of two name lists — index-vs-HEAD and worktree-vs-index
# — i.e. porcelain `XY` with X in [MARC] and Y in [MD]. A bare ` M` (unstaged only) is the
# NORMAL state of every run before FN's own `git add` and must never fire; matching it would
# block every finalization. Name lists also sidestep porcelain's rename and quoting grammar.
#
# Scoped to the cwd repository. Enumerating `git worktree list` would reach the sibling
# worktrees of a Conductor multi-workspace checkout and block this run on another worktask's
# dirt; that enumeration is a follow-up, not this check.
cmd_staging() {
  if ! git rev-parse --git-dir > /dev/null 2>&1; then
    printf 'staging: not a git repository — nothing to check\n'
    return 0
  fi
  local staged unstaged both
  staged=$(git diff --cached --name-only 2> /dev/null || printf '')
  unstaged=$(git diff --name-only 2> /dev/null || printf '')
  if [[ -z "$staged" || -z "$unstaged" ]]; then
    printf 'staging: no file is both staged and modified again\n'
    return 0
  fi
  both=$(printf '%s\n' "$staged" | grep -Fxf <(printf '%s\n' "$unstaged") 2> /dev/null || true)
  if [[ -n "$both" ]]; then
    printf >&2 'BLOCKED: staged then modified again — the PR would ship the staged bytes, not these:\n'
    printf >&2 '  %s\n' $both
    audit_fn staging blocked "$(meta_json files "$(printf '%s' "$both" | tr '\n' ' ')")"
    return 1
  fi
  printf 'staging: no file is both staged and modified again\n'
  return 0
}

cmd_attachments() {
  local pr="${CONTEXT_DIR}/attachments/PR instructions.md"
  local rr="${CONTEXT_DIR}/attachments/Review request.md"
  if [[ -f "$pr" && -f "$rr" ]]; then
    printf 'attachments: both present\n'
    return 0
  fi
  printf >&2 'BLOCKED: missing Conductor attachment(s):%s%s\n' \
    "$([[ -f "$pr" ]] || printf ' "PR instructions.md"')" \
    "$([[ -f "$rr" ]] || printf ' "Review request.md"')"
  return 1
}

cmd_pr_body() {
  [[ -n "$BODY_FILE" && -f "$BODY_FILE" ]] || {
    printf >&2 'pr-body requires --body <path> to an existing file\n'
    exit 2
  }
  # Batch (/megatask) and incident (--emergency) routing is exempt from this
  # command's BLOCKING checks, never from sanitisation — a working-folder path
  # must not reach a published body on any route. The exemption exists so an
  # unreachable sanitiser library cannot wedge those pipelines, so for them the
  # strip below degrades to a warning rather than returning 1.
  local batch=0
  if fn_batch_scope; then batch=1; fi

  local ri before after tmp rc=0
  ri=$(jq -r '.run_index // 0' "$STATE_PATH" 2> /dev/null || printf '0')
  before=$(wc -l < "$BODY_FILE" | tr -d ' ')
  tmp="${BODY_FILE}.sanitised.$$"
  sanitise_stream < "$BODY_FILE" > "$tmp" || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    rm -f "$tmp"
    if [[ "$batch" == 1 ]]; then
      printf >&2 'warn: PR-body sanitiser unavailable (rc=%s), not blocking under %s: %s\n' \
        "$rc" "$SCOPE_REASON" "$LIB_PATH"
      audit_fn pr_body_gate skipped \
        "$(meta_json reason sanitiser_unavailable scope "$SCOPE_REASON" lib "$LIB_PATH")"
      return 0
    fi
    printf >&2 'BLOCKED: PR-body sanitiser unavailable (rc=%s): %s\n' "$rc" "$LIB_PATH"
    audit_fn pr_body_gate blocked "$(meta_json reason sanitiser_unavailable lib "$LIB_PATH")"
    return 1
  fi
  if cmp -s "$tmp" "$BODY_FILE"; then
    rm -f "$tmp"
    audit_fn pr_body_sanitised unchanged "$(meta_json lines "$before")"
  else
    # Snapshot before overwriting: the strip rules are deliberately blunt, and a
    # reviewer needs the pre-sanitise text to judge an over-strip. Mirrors the
    # issue-body-<n>.aborted.tmp precedent in publish-pl-issue.sh.
    mkdir -p "${CONTEXT_DIR}/logs" 2> /dev/null || true
    cp "$BODY_FILE" "${CONTEXT_DIR}/logs/pr-body-${ri}.presanitise.md" 2> /dev/null || true
    mv -f "$tmp" "$BODY_FILE"
    after=$(wc -l < "$BODY_FILE" | tr -d ' ')
    printf 'pr-body: sanitised (%s -> %s lines)\n' "$before" "$after"
    audit_fn pr_body_sanitised ok "$(meta_json lines_before "$before" lines_after "$after" \
      snapshot "${CONTEXT_DIR}/logs/pr-body-${ri}.presanitise.md")"
  fi

  # Read back what the sanitiser actually produced. Sanitising without inspecting
  # the result is how a body that lost every image and kept a dead local path was
  # audited "ok". Runs here, after the rewrite, so it lints the byte-identical
  # body that reaches `gh pr create`. Warn-only by contract: it never changes this
  # gate's verdict, so it can land mid-flight — promote it with --strict.
  if [ -x "${SCRIPT_DIR}/pr-body-lint.sh" ]; then
    bash "${SCRIPT_DIR}/pr-body-lint.sh" --body "$BODY_FILE" --state "$STATE_PATH" \
      --context "$CONTEXT_DIR" || true
  fi

  # Composition requirements below are worktask-FN contracts; batch and incident
  # runs compose their bodies elsewhere and only needed the strip above.
  if [[ "$batch" == 1 ]]; then
    printf 'pr-body: sanitised; composition gate skipped (%s)\n' "$SCOPE_REASON"
    audit_fn pr_body_gate skipped "$(meta_json reason "$SCOPE_REASON")"
    return 0
  fi

  # Checked AFTER sanitising, so a heading the sanitiser removed reports as missing
  # — one diagnostic instead of two rules disagreeing about the same body.
  if ! grep -E -i -q '^#{1,6}[[:space:]]+Test plan[[:space:]]*$' "$BODY_FILE"; then
    printf >&2 'BLOCKED: PR body has no "## Test plan" heading (hand-authored body?)\n'
    audit_fn pr_body_gate blocked "$(meta_json reason missing_test_plan_heading)"
    return 1
  fi

  # Visual evidence, keyed on the audit row first: only the row proves the helper
  # ran THIS run, and only the heading proves its stdout reached the body. A row
  # reporting `skipped` legitimately produced nothing, so no heading is required.
  # Default mirrors attach-visual-evidence.sh state_requires_screenshots: absent
  # metadata means true.
  local req wid vres
  req=$(jq -r 'if (.metadata|type=="object") and (.metadata|has("requires_screenshots"))
               then (.metadata.requires_screenshots|tostring) else "true" end' \
    "$STATE_PATH" 2> /dev/null || printf 'true')
  if [[ "$req" != "false" ]]; then
    wid=$(jq -r '.worktask_id // "unknown"' "$STATE_PATH" 2> /dev/null || printf 'unknown')
    vres=$(ve_row_result "$wid" "$ri")
    if [[ -z "$vres" ]]; then
      printf >&2 'BLOCKED: no %s audit row for %s:%s — run attach-visual-evidence.sh --emit pr\n' \
        "$VE_ACTION" "$wid" "$ri"
      audit_fn pr_body_gate blocked "$(meta_json reason missing_visual_evidence_row)"
      return 1
    fi
    # "reused" is an idempotent replay of an earlier "ok" — same block on stdout, so
    # it carries the same obligation. ve_row_result returns the LAST row, so omitting
    # it would let a second --emit run silently retire the heading requirement.
    if [[ "$vres" == "ok" || "$vres" == "reused" ]] &&
      ! grep -E -i -q '^#{1,6}[[:space:]]+Visual evidence[[:space:]]*$' "$BODY_FILE"; then
      printf >&2 'BLOCKED: %s reported result=ok but the body has no "## Visual evidence" section\n' \
        "$VE_ACTION"
      audit_fn pr_body_gate blocked "$(meta_json reason missing_visual_evidence_section)"
      return 1
    fi
  fi

  printf 'pr-body: composition gate passed\n'
  audit_fn pr_body_gate ok "$(meta_json requires_screenshots "$req")"
  return 0
}

cmd_validate_pr() {
  [[ -n "$BODY_FILE" && -f "$BODY_FILE" ]] || {
    printf >&2 'validate-pr requires --body <path> to an existing file\n'
    exit 2
  }
  local issue_n
  issue_n=$(resolve_issue)

  if [[ -n "$issue_n" ]]; then
    if grep -E -i -q "^(Closes|Fixes|Resolves)[[:space:]]+#${issue_n}[[:space:]]*$" "$BODY_FILE"; then
      printf 'validate-pr: body closes #%s\n' "$issue_n"
      return 0
    fi
    printf >&2 'BLOCKED: PR body missing "Closes #%s" (resolved issue)\n' "$issue_n"
    return 1
  fi

  # No issue resolvable → audit-defer row, proceed WITHOUT a closing line.
  audit_fn pr_issue_link deferred "$(meta_json reason no_issue_resolved)"
  printf 'validate-pr: no issue resolved — audit-deferred, proceeding without closing line\n'
  return 0
}

cmd_continuity() {
  local wt_head int_branch ref
  wt_head=$(git rev-parse HEAD 2> /dev/null || printf '')
  int_branch=$(resolve_base_ref)
  if [[ -z "$int_branch" ]]; then
    printf >&2 'continuity: integration branch unresolvable (no metadata.base_ref, no workspace.json .git.base_branch, no origin/HEAD) — ancestor check skipped\n'
    audit_fn branch_continuity base_ref_unresolved "$(meta_json worktree_head "$wt_head")"
    return 0
  fi
  ref=$(resolve_git_ref "$int_branch" || printf '')
  if [[ -z "$ref" ]]; then
    printf >&2 'continuity: integration branch %s not present locally — ancestor check skipped\n' "$int_branch"
    audit_fn branch_continuity base_ref_unresolvable "$(meta_json integration_branch "$int_branch")"
    return 0
  fi

  # The printed name stays the resolved NAME, not the git ref it mapped to: that is
  # what an operator recognises, and what the existing contract test asserts.
  if [[ -n "$wt_head" ]] && git merge-base --is-ancestor "$wt_head" "$ref" 2> /dev/null; then
    printf 'continuity: worktree HEAD is an ancestor of %s (fast-forward safe)\n' "$int_branch"
    return 0
  fi

  printf >&2 'worktree branch diverged — falling back to cherry-pick; verify commits are complete.\n'
  local ts n
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  n=$(git rev-list --count "${ref}..${wt_head}" 2> /dev/null || printf '0')
  # --argjson below refuses anything that is not a JSON literal, and losing the whole
  # row to an unexpected count would be worse than reporting an honest zero.
  case "$n" in '' | *[!0-9]*) n=0 ;; esac
  mkdir -p "${CONTEXT_DIR}/logs" 2> /dev/null || true
  # Refuse a symlinked audit.jsonl: following it makes this append a write primitive
  # against an arbitrary target. A lost row never blocks the caller.
  if [ ! -L "${CONTEXT_DIR}/logs/audit.jsonl" ]; then
    # Built with jq, not printf: `git check-ref-format` accepts a double quote in a
    # refname, so a printf template interpolating $int_branch emits a line that no
    # later reader of audit.jsonl can parse. The row shape stays hand-written rather
    # than routed through audit_fn/meta_json because this row's contract is a bare
    # key set (no task_id/origin_stage/dedupe_key) and a NUMERIC commit_count.
    if command -v jq > /dev/null 2>&1; then
      if ! jq -cn --arg ts "$ts" --arg head "$wt_head" --arg branch "$int_branch" \
        --argjson n "$n" \
        '{ts: $ts, actor: "project-manager", action: "branch_continuity",
          subject: "FN0", result: "diverged_cherry_pick",
          metadata: {worktree_head: $head, integration_branch: $branch, commit_count: $n}}' \
        >> "${CONTEXT_DIR}/logs/audit.jsonl" 2> /dev/null; then
        printf >&2 'continuity: audit row NOT recorded (sink unwritable) — divergence still reported above\n'
      fi
    else
      printf >&2 'continuity: jq unavailable — divergence audit row skipped (diagnostic above stands)\n'
    fi
  fi
  return 0 # diverged is a documented fallback, not a hard block
}

# Has anything outside this pipeline renamed the local branch since the naming step?
#
# The comparison base is the `to` of the most recent `branch_renamed / ok` row, NOT
# `facts.branch`. That distinction is what makes the check useful: `facts.branch` is the
# PLANNED REMOTE name and is legitimately different from the local name on several arms, so
# comparing against it fires on every worktree run and gets ignored. It also makes R4
# structurally unable to trip this — R4 rewrites `facts.branch` and never touches git, so a
# refinement cannot look like an external rename.
#
# Read-only, exit 0 always, at most one row, never blocks: divergence is a legitimate
# designed state on the opt-out, upstream_tracked, target_exists and jq_unavailable arms.
cmd_branch_divergence() {
  local log="${CONTEXT_DIR}/logs/audit.jsonl" local_name ledger renamed_to class
  local_name=$(git rev-parse --abbrev-ref HEAD 2> /dev/null || printf '')
  if [[ "$local_name" == "HEAD" ]]; then local_name=""; fi

  if ! command -v jq > /dev/null 2>&1; then
    printf 'branch-divergence: jq unavailable — check skipped\n'
    return 0
  fi
  ledger=$(jq -r '.facts.branch // ""' "$STATE_PATH" 2> /dev/null || printf '')
  [[ "$ledger" == "null" ]] && ledger=""

  renamed_to=""
  if [[ -f "$log" ]]; then
    # `fromjson? | objects` — the first survives an unparsable line, the second a
    # well-formed NON-object one (`123`, `[1,2]`), which would otherwise abort the scan on
    # `.action` and silently suppress detection of a real third-party rename.
    # `last` takes the most recent ok row, so a re-run's row wins over an earlier one.
    renamed_to=$(jq -rs -R \
      '[ split("\n")[] | fromjson? | objects
         | select(.action == "branch_renamed" and .result == "ok") | .metadata.to ]
       | (last // "")' "$log" 2> /dev/null) || renamed_to=""
  fi

  # third_party requires an ok row to compare against; everything else is a designed
  # divergence (or none at all) and stays an audit row only.
  if [[ -n "$renamed_to" ]] && [[ -n "$local_name" ]] && [[ "$local_name" != "$renamed_to" ]]; then
    class="third_party"
  else
    class="expected"
  fi

  audit_fn branch_divergence_detected warn \
    "$(meta_json class "$class" ledger "$ledger" local "$local_name" \
      renamed_to "$renamed_to" source "${DIVERGENCE_SOURCE:-fn_preflight}")"

  if [[ "$class" == "third_party" ]]; then
    printf 'branch-divergence: local branch is %s but this run renamed it to %s — renamed by something outside the pipeline\n' \
      "$local_name" "$renamed_to"
  else
    printf 'branch-divergence: no external rename detected (class=expected)\n'
  fi
  return 0
}

# ---------- issue-close-required ----------
# GitHub only honours a `Closes #N` trailer when the PR merges into the DEFAULT branch.
# Merging into any other integration branch leaves the issue open with no signal at all,
# so FN has to close it explicitly. Read-only: it prints the command, never runs it.
#
# Unresolved base_ref or issue ⇒ report and return 0. A finalization gate that blocks on
# its own inability to introspect is worse than the open issue it is guarding against.
cmd_issue_close_required() {
  local base default_branch issue

  if ! command -v jq > /dev/null 2>&1; then
    printf 'issue-close-required: jq unavailable — check skipped\n'
    return 0
  fi

  base=$(resolve_base_ref)
  base="${base#origin/}"
  if [[ -z "$base" ]]; then
    audit_fn issue_close_required base_ref_unresolved "$(meta_json reason unresolved)"
    printf 'issue-close-required: integration branch unresolved — reporting, not guessing; verify the issue manually\n'
    return 0
  fi

  default_branch=$(git symbolic-ref --short refs/remotes/origin/HEAD 2> /dev/null || printf '')
  default_branch="${default_branch#origin/}"
  if [[ -z "$default_branch" ]]; then
    audit_fn issue_close_required default_branch_unresolved "$(meta_json base "$base")"
    printf 'issue-close-required: repository default branch unresolved — reporting, not guessing; verify the issue manually\n'
    return 0
  fi

  if [[ "$base" == "$default_branch" ]]; then
    audit_fn issue_close_required not_required \
      "$(meta_json base "$base" default_branch "$default_branch")"
    printf 'issue-close-required: no (integration branch %s IS the repository default — the merge trailer fires)\n' "$base"
    return 0
  fi

  issue=$(resolve_issue)
  if [[ -z "$issue" ]]; then
    audit_fn issue_close_required issue_unresolved \
      "$(meta_json base "$base" default_branch "$default_branch")"
    printf 'issue-close-required: yes, but no issue number resolved (integration branch %s is not the default %s).\nNo command can be printed — find the issue and close it manually.\n' \
      "$base" "$default_branch"
    return 0
  fi

  audit_fn issue_close_required required \
    "$(meta_json base "$base" default_branch "$default_branch" issue "$issue")"
  printf 'issue-close-required: yes — %s is not the repository default (%s), so the merge trailer will NOT fire.\nRun after the merge:\n  gh issue close %s --comment "Merged into %s."\n' \
    "$base" "$default_branch" "$issue" "$base"
  return 0
}

# ---------- base-sanity ----------
# The magnitude question no other check asks: does the diff a PR against the
# resolved base would carry resemble what this run says it changed? A branch
# stacked on another feature branch, opened against the shared integration
# branch, silently carries the whole intervening branch — 1008 files where the
# run itself recorded 27. Ancestry (`continuity`) cannot see that: divergence is
# the normal state of every feature branch about to merge. Magnitude can.
#
# The thresholds are WRONG-BASE heuristics, not diff-quality rules. The
# multiplier alone would trip a 3-file run that legitimately touched 9; the
# 20-file floor alone would trip any large-but-correct run. Only the conjunction
# describes the shape of a wrong base, which is why neither half may be tuned or
# relaxed on its own.

# Forgiving on purpose: an escape hatch that silently fails to engage on
# `=true` is a worse footgun than a loose parse. bash 3.2 has no ${v,,}.
_bs_override_on() {
  case "${FN_BASE_SANITY_OVERRIDE:-}" in
    '' | 0 | [Ff][Aa][Ll][Ss][Ee] | [Nn][Oo]) return 1 ;;
    *) return 0 ;;
  esac
}

# Fork-point evidence is optional here BY DESIGN: base-sanity blocks correctly
# without it, so an install lacking the Change-B helper degrades the candidate
# line to `unavailable` rather than losing the block.
_bs_fork_candidate() {
  local configured="$1" f=""
  command -v fork_base > /dev/null 2>&1 || {
    printf 'unavailable'
    return 0
  }
  f=$(fork_base "$configured" 2> /dev/null || printf '')
  [ -n "$f" ] || f="unavailable"
  printf '%s' "$f"
}

cmd_base_sanity() {
  local base ref src ahead pr_files ledger_files fork fork_ahead meta diff_out

  # Degrade ladder, evaluated BEFORE the rule and ordered most-fundamental first.
  # Each rung warns and exits 0: a blocking gate that fires on its own inability
  # to introspect is worse than the wrong base it guards against, and every rung
  # carries its own result token so a wrong-rung regression stays visible.
  if ! command -v jq > /dev/null 2>&1; then
    printf 'base-sanity: jq unavailable — check skipped\n'
    audit_fn base_sanity jq_unavailable "$(meta_json reason jq_unavailable)"
    return 0
  fi

  if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    printf 'base-sanity: not inside a git work tree — check skipped\n'
    audit_fn base_sanity no_git "$(meta_json reason no_git)"
    return 0
  fi

  # --with-fork-point: this is the one caller that can tell an inferred base from a
  # configured one (rung 5 below), so it is the one caller that may accept one.
  base=$(resolve_base_ref --with-fork-point)
  if [[ -z "$base" ]]; then
    printf 'base-sanity: integration branch unresolved — reporting, not guessing; verify the PR base manually\n'
    audit_fn base_sanity base_ref_unresolved "$(meta_json reason unresolved)"
    return 0
  fi

  # Via resolve_git_ref, never a literal `origin/$base`: the stored value may
  # already be remote-qualified, and a local-only clone has no remote at all.
  ref=$(resolve_git_ref "$base" || printf '')
  if [[ -z "$ref" ]]; then
    printf 'base-sanity: integration branch %s not present locally — magnitude comparison skipped\n' "$base"
    audit_fn base_sanity base_ref_unresolvable "$(meta_json base "$base")"
    return 0
  fi

  src=""
  if command -v base_ref_source > /dev/null 2>&1; then
    src=$(base_ref_source --with-fork-point 2> /dev/null || printf '')
  fi
  if [[ "$src" == "fork_point" ]]; then
    printf 'base-sanity: base %s is itself fork-point evidence rather than a configured target — blocking on a guess would be a false block; skipped\n' "$base"
    audit_fn base_sanity base_guessed "$(meta_json base "$base" base_source "$src")"
    return 0
  fi

  ledger_files=$(jq -r 'if (.facts.files_modified | type) == "array"
                        then (.facts.files_modified | length) else 0 end' \
    "$STATE_PATH" 2> /dev/null || printf '0')
  case "$ledger_files" in '' | *[!0-9]*) ledger_files=0 ;; esac
  # Cannot be folded into the rule: at ledger_files == 0 the multiplier clause is
  # satisfied by any non-empty diff, so the rule would degenerate to "every PR
  # touching 21+ files fails".
  if [[ "$ledger_files" -eq 0 ]]; then
    printf 'base-sanity: this run records no modified files — nothing to compare the PR diff against; skipped\n'
    audit_fn base_sanity ledger_unavailable "$(meta_json base "$base")"
    return 0
  fi

  # Eighth degrade rung. facts.files_modified is this rule's denominator and is known to
  # under-record — 18 recorded against 33 dirty in this release's own run. When the working
  # tree shows a gap of the same magnitude the rule itself treats as significant, the
  # denominator is demonstrably incomplete, and a block computed from it is a false block on a
  # correct base. Warn instead, like every other rung that cannot trust its inputs. A wrong
  # base does not dirty the working tree, so this cannot mask the topology being checked.
  local tree_files
  tree_files=$(git status --porcelain 2> /dev/null | grep -c . || printf '0')
  case "$tree_files" in '' | *[!0-9]*) tree_files=0 ;; esac
  if [[ "$tree_files" -gt $((ledger_files * 3)) ]] && [[ $((tree_files - ledger_files)) -gt 20 ]]; then
    printf 'base-sanity: the ledger records %s modified files but the working tree shows %s — the denominator is incomplete, so the magnitude comparison is unreliable; skipped\n' \
      "$ledger_files" "$tree_files"
    audit_fn base_sanity ledger_under_recording \
      "$(meta_json base "$base" ledger_files "$ledger_files" tree_files "$tree_files")"
    return 0
  fi

  # Ninth degrade rung. Under fan-out the payload is a MERGE of independently-staged
  # streams, and `facts.files_modified` is never their union: each stream records what it
  # knows, none records the assembly. So the denominator is incomplete BY CONSTRUCTION, not
  # by under-recording, and the rule blocks on every fan-out — observed at 140 PR files
  # against 19 ledger files, cleared only with the sanctioned override, which is a gate
  # teaching its own operators to bypass it.
  #
  # A merge parent is the mechanical signal: a single-stream payload has none. Same
  # direction as every rung above — an input the rule cannot trust degrades to a warn, and
  # a wrong base still shows up in `continuity`, which does not depend on this denominator.
  local merge_parents=0
  merge_parents=$(git rev-list --merges --count "${ref}..HEAD" 2> /dev/null || printf '0')
  case "$merge_parents" in '' | *[!0-9]*) merge_parents=0 ;; esac
  if [[ "$merge_parents" -gt 0 ]]; then
    printf 'base-sanity: this payload has %s merge commit(s) — facts.files_modified cannot be the union of independently-staged streams, so the magnitude comparison is unreliable; skipped
' \
      "$merge_parents"
    audit_fn base_sanity multi_parent_payload \
      "$(meta_json base "$base" ledger_files "$ledger_files" merge_parents "$merge_parents")"
    return 0
  fi

  # Captured, then counted — never `git diff | wc -l`: `wc` has already written `0`
  # by the time git fails, so the pipeline yields a plausible zero-file count and the
  # only trace of the failure is an exit status the pipeline then hides. A base sharing
  # no merge base with HEAD (git exit 128) is exactly that case, and it is the wrong-base
  # topology this check exists to catch.
  if ! diff_out=$(git diff --name-only "${ref}...HEAD" 2> /dev/null); then
    printf 'base-sanity: the diff against %s is unreadable — magnitude comparison skipped\n' "$base"
    audit_fn base_sanity diff_unreadable "$(meta_json base "$base" ledger_files "$ledger_files")"
    return 0
  fi
  # Guarded because an empty diff is one empty line to `wc`, not zero lines.
  pr_files=0
  if [[ -n "$diff_out" ]]; then
    pr_files=$(printf '%s\n' "$diff_out" | wc -l | tr -d ' ')
  fi

  ahead=$(git rev-list --count "${ref}..HEAD" 2> /dev/null || printf '0')
  case "$ahead" in '' | *[!0-9]*) ahead=0 ;; esac

  fork=$(_bs_fork_candidate "$base")
  fork_ahead=""
  if [[ "$fork" != "unavailable" ]]; then
    # Through resolve_git_ref, exactly like $base above: fork_base returns a BARE
    # branch name, and a remote-only branch does not resolve bare under git's
    # disambiguation ladder. That is the incident's own topology, so counting on
    # the bare name would blank the candidate precisely when it matters most.
    local fork_ref
    fork_ref=$(resolve_git_ref "$fork" || printf '')
    if [[ -n "$fork_ref" ]]; then
      fork_ahead=$(git rev-list --count "${fork_ref}..HEAD" 2> /dev/null || printf '')
    fi
  fi

  meta=$(meta_json base "$base" pr_files "$pr_files" ledger_files "$ledger_files" \
    ahead "$ahead" fork_candidate "$fork" base_source "${src:-unknown}")

  if [[ "$pr_files" -gt $((ledger_files * 3)) ]] && [[ $((pr_files - ledger_files)) -gt 20 ]]; then
    local candidate_line
    if [[ -n "$fork_ahead" ]]; then
      candidate_line=$(printf 'Closest fork-point candidate by commits-ahead: %s (%s ahead) vs %s (%s ahead).' \
        "$fork" "$fork_ahead" "$base" "$ahead")
    else
      candidate_line=$(printf 'Closest fork-point candidate by commits-ahead: unavailable vs %s (%s ahead).' \
        "$base" "$ahead")
    fi

    if _bs_override_on; then
      printf >&2 'WARNING: base-sanity: a PR against %s would carry %s files; this run'"'"'s ledger records %s.\n%s\nDowngraded to a warning by FN_BASE_SANITY_OVERRIDE — the bypass is audited.\n' \
        "$base" "$pr_files" "$ledger_files" "$candidate_line"
      audit_fn base_sanity override \
        "$(meta_json base "$base" pr_files "$pr_files" ledger_files "$ledger_files" \
          ahead "$ahead" fork_candidate "$fork" base_source "${src:-unknown}" \
          override "${FN_BASE_SANITY_OVERRIDE:-}")"
      return 0
    fi

    printf >&2 'BLOCKED: base-sanity: a PR against %s would carry %s files; this run'"'"'s ledger records %s.\nThat gap (over 3x and over 20 files) is the signature of a base branch this work never forked from.\n%s\nThese are WRONG-BASE heuristics, not diff-quality rules — do not tune them into a style gate.\nSet FN_BASE_SANITY_OVERRIDE=1 to downgrade this to a warning (audited).\n' \
      "$base" "$pr_files" "$ledger_files" "$candidate_line"
    audit_fn base_sanity blocked "$meta"
    return 1
  fi

  if [[ "$ahead" -gt 25 ]]; then
    printf 'base-sanity: WARNING — HEAD is %s commits ahead of %s (%s files vs %s recorded); unusual for one worktask, verify the base is right\n' \
      "$ahead" "$base" "$pr_files" "$ledger_files"
    audit_fn base_sanity warn_ahead "$meta"
    return 0
  fi

  printf 'base-sanity: pass — a PR against %s would carry %s files; this run'"'"'s ledger records %s\n' \
    "$base" "$pr_files" "$ledger_files"
  audit_fn base_sanity ok "$meta"
  return 0
}
