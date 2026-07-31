#!/usr/bin/env bash
# DV comment-density gate — blocks a code-writing agent's SubagentStop when a
# changed source file is more comment than the standard allows (igrsoft
# worktask plugin).
#
# Closes the failure class where `skills/code-comment-standard` is stated but
# never verified: a worktask shipped 932 comment lines against 1938 added
# source lines (48%), with four files at 51-58%, and five DR passes reviewed
# correctness without once flagging density.
#
# Fires on SubagentStop (wired alongside audit-subagent.sh / dv-screenshot-gate.sh
# in .claude-plugin/plugin.json — no matcher; the hook self-filters).
#
# Agent filter — deliberately NOT the sibling's exact-match on
# "igrsoft:developer". A Conductor worktree waiver dispatches
# apple-developer:ios-developer directly, bypassing igrsoft:developer entirely;
# an exact-match gate catches none of that. This matches any code-writing agent
# (*developer*, *code-fixer*, *test-generator*) and stays silent for reviewers
# (technical-lead, qa-engineer, security-reviewer) so a reviewer is never
# blocked for the writer's bloat.
#
# Behavior:
#   - No-op (exit 0) for non-writer agents, or when no source file changed.
#   - Density = comment share of the file's ADDED lines (whole body for a new
#     file). Whole-file density was rejected: 85 of 341 files in a real repo are
#     already over the ceiling, so it would block an agent for inheriting bloat.
#     Files under MIN_ADDED_LINES are skipped — small edits are not the failure
#     mode, bulk-authored files are.
#   - Over IGRSOFT_COMMENT_DENSITY_MAX (default 40) -> emit
#     {"decision":"block", ..., "hookSpecificOutput":{...,"additionalContext":
#     "<remediation>"}} + comment_density_block row.
#     Under -> pass + comment_density_pass row (warns in the row over ..._WARN,
#     default 25, without blocking).
#   - Safe degrade: jq or git absent -> exit 0 (no block), like the siblings.
#   - Exit is ALWAYS 0; a block travels in the decision JSON, never the code.
#   - --self-test: bloated fixture must block, lean fixture must pass.
set -eu

# Measured against a real offending branch: added-line density ran 26-67% per
# file, and 40 catches every genuine offender while clearing the two files whose
# documentation was proportionate.
DENSITY_MAX="${IGRSOFT_COMMENT_DENSITY_MAX:-40}"
DENSITY_WARN="${IGRSOFT_COMMENT_DENSITY_WARN:-30}"
MIN_ADDED_LINES="${IGRSOFT_COMMENT_DENSITY_MIN_LINES:-40}"

SELF_TEST=0
[ "${1:-}" = "--self-test" ] && SELF_TEST=1

read_stdin() {
  if [ "$SELF_TEST" -eq 1 ]; then
    printf '%s' '{"agent_type":"apple-developer:ios-developer","agent_id":"agt_test","session_id":"sess_test"}'
  else
    cat
  fi
}

if ! command -v jq >/dev/null 2>&1; then
  echo "dv-comment-density-gate: jq not found, skipping" >&2
  exit 0
fi
if ! command -v git >/dev/null 2>&1; then
  echo "dv-comment-density-gate: git not found, skipping" >&2
  exit 0
fi

# ---------------------------------------------------------------------------
# comment_style_for <path>: the comment syntax family of a file, by extension.
#
# A single C-family regex scored every `#`-commented language at 0% comments, so
# a wholly-commented .py sailed through the gate it was supposed to trip. The
# style must track the extension, not the majority language in the repo.
# ---------------------------------------------------------------------------
comment_style_for() {
  case "${1##*.}" in
    py | sh | bash) printf 'hash' ;;
    *) printf 'cfamily' ;;
  esac
}

# ---------------------------------------------------------------------------
# density_of <file>: echoes the integer comment percentage, or nothing when the
# file has no countable body. Line-based on purpose — it must agree with the
# ratio a human gets from grep, not with a Swift parser.
#
# Python docstrings are deliberately NOT counted. Recognizing them needs a
# multi-line toggle, and the diff arm only ever sees added lines: one unpaired
# `"""` in a hunk would score every later line as comment and block an author
# for prose they did not write. A `#` undercount is the safe direction here.
#
# The leading contiguous comment block (license header) is skipped: counting it
# would push every short file over the ceiling for boilerplate nobody wrote.
# ---------------------------------------------------------------------------
added_density_of() {
  _root="$1"
  _file="$2"
  _style=$(comment_style_for "$_file")
  # Added lines only — the agent owns what it wrote, not what it inherited.
  # Whole-file density would block an agent for touching one of the many
  # pre-existing files already over the ceiling (measured: 85 of 341 in a real
  # repo, p90 = 50%), which punishes the wrong person and trains people to
  # avoid touching bloated files.
  #
  # An untracked file has no diff, so its whole body is "added" — correct: a
  # new file is entirely the author's.
  if git -C "$_root" ls-files --error-unmatch "$_file" >/dev/null 2>&1; then
    git -C "$_root" diff HEAD -- "$_file" 2>/dev/null | awk -v style="$_style" '
      BEGIN { pat = (style == "hash") ? "^#" : "^(//|/\\*|\\*/|\\*)" }
      /^\+\+\+/ { next }
      /^\+/ {
        line = substr($0, 2)
        sub(/^[ \t]+/, "", line)
        if (line == "") { next }
        total++
        if (line ~ pat) { comment++ }
      }
      END { if (total > 0) { printf "%d %d", (comment * 100) / total, total } }
    '
  else
    awk -v style="$_style" '
      BEGIN { pat = (style == "hash") ? "^#" : "^(//|/\\*|\\*/|\\*)" }
      {
        line = $0
        sub(/^[ \t]+/, "", line)
        if (line == "") { next }
        total++
        if (line ~ pat) { comment++ }
      }
      END { if (total > 0) { printf "%d %d", (comment * 100) / total, total } }
    ' "$_root/$_file" 2>/dev/null
  fi
}

# ---------------------------------------------------------------------------
# run_gate: core logic, parameterized over the .context/ root + repo + payload.
# Echoes the block decision on stdout when blocking; appends one audit row.
# Returns 0 always.
# ---------------------------------------------------------------------------
run_gate() {
  _payload="$1"
  _ctx="$2"
  _repo="$3"

  _agent=$(printf '%s' "$_payload" | jq -r '.agent_type // "unknown"' 2>/dev/null || echo unknown)
  case "$_agent" in
    *developer* | *code-fixer* | *test-generator*) ;;
    *) return 0 ;;
  esac

  _root=$(git -C "$_repo" rev-parse --show-toplevel 2>/dev/null) || return 0

  # Changed + untracked source files, NUL-safe against paths with spaces.
  _files=$(
    {
      git -C "$_root" diff --name-only --diff-filter=ACMR HEAD 2>/dev/null || true
      git -C "$_root" ls-files --others --exclude-standard 2>/dev/null || true
    } | sort -u
  )
  [ -n "$_files" ] || return 0

  _offenders=""
  _worst=0
  _checked=0
  while IFS= read -r _f; do
    [ -n "$_f" ] || continue
    # Vendored trees are exempt: on a dependency refresh the added lines ARE the
    # third-party code, so added-line scoping stops shielding the writer from
    # bloat it cannot slim.
    case "$_f" in
      vendor/* | */vendor/* | */node_modules/* | */Pods/* | */third_party/*) continue ;;
    esac
    case "${_f##*.}" in
      swift | h | m | mm | c | cc | cpp | ts | tsx | js | jsx | py | kt | java | go | rs | sh | bash) ;;
      *) continue ;;
    esac
    [ -f "$_root/$_f" ] || continue
    _m=$(added_density_of "$_root" "$_f")
    [ -n "$_m" ] || continue
    _d=${_m%% *}
    _added=${_m##* }
    # Small edits are not the failure mode; bulk-authored files are. Below the
    # floor a two-line doc on a three-line fix would read as 66% and block.
    [ "$_added" -ge "$MIN_ADDED_LINES" ] || continue
    _checked=$((_checked + 1))
    [ "$_d" -gt "$_worst" ] && _worst="$_d"
    if [ "$_d" -gt "$DENSITY_MAX" ]; then
      _offenders="${_offenders}${_offenders:+, }${_f} (${_d}% of ${_added} added)"
    fi
  done <<EOF
$_files
EOF

  [ "$_checked" -gt 0 ] || return 0

  _log_dir="$_ctx/logs"
  mkdir -p "$_log_dir" 2>/dev/null || true
  _ts=$(date -u +%FT%TZ)

  if [ -z "$_offenders" ]; then
    _res="ok"
    [ "$_worst" -gt "$DENSITY_WARN" ] && _res="warn"
    jq -cn --arg ts "$_ts" --arg agent "$_agent" --arg res "$_res" \
      --argjson worst "$_worst" --argjson checked "$_checked" --argjson max "$DENSITY_MAX" '
      {ts: $ts, actor: "hook:dv-comment-density-gate", action: "comment_density_pass",
       subject: $agent, result: $res,
       metadata: {worst_pct: $worst, files_checked: $checked, threshold: $max}}' \
      >>"$_log_dir/audit.jsonl" 2>/dev/null || true
    return 0
  fi

  _remedy="Comment-density gate: these changed files are over ${DENSITY_MAX}% comments — ${_offenders}. The igrsoft standard (skill: igrsoft:code-comment-standard) requires comment-to-code density well below 1:1; a file that is ~half prose is over-documented. Remove: multi-paragraph /// essays, defect/ticket history, before/after narration, AC-/REQ- IDs and issue tags as provenance, caller enumeration, QA runbooks and tuning instructions, prose restating the signature, and any justification written to answer a review finding. Keep: a one-line /// summary where the name is not self-evident, ONE terse WHY per non-obvious literal, and one-line invariants that prevent a regression. Rationale, threshold derivations and deviation justifications belong in .context/development-N.md and the PR — not in source. Re-run and return once every changed file is under the ceiling."

  jq -cn --arg ts "$_ts" --arg agent "$_agent" --arg off "$_offenders" \
    --argjson worst "$_worst" --argjson checked "$_checked" --argjson max "$DENSITY_MAX" '
    {ts: $ts, actor: "hook:dv-comment-density-gate", action: "comment_density_block",
     subject: $agent, result: "blocked",
     metadata: {worst_pct: $worst, files_checked: $checked, threshold: $max, offenders: $off}}' \
    >>"$_log_dir/audit.jsonl" 2>/dev/null || true

  jq -n --arg reason "$_remedy" '
    {decision: "block", reason: $reason,
     hookSpecificOutput: {hookEventName: "SubagentStop", additionalContext: $reason}}'
  return 0
}

if [ "$SELF_TEST" -eq 1 ]; then
  _tmp=$(mktemp -d)
  trap 'rm -rf "$_tmp"' EXIT
  git -C "$_tmp" init -q 2>/dev/null || { echo "dv-comment-density-gate: self-test SKIP (git init failed)"; exit 0; }
  # Real repos always have a HEAD; give the fixture one so the `git diff HEAD`
  # arm is exercised rather than silently falling through to ls-files.
  git -C "$_tmp" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init 2>/dev/null || true
  mkdir -p "$_tmp/.context/logs"

  # Both fixtures are new (untracked) files, so their whole body counts as
  # added, and both clear MIN_ADDED_LINES.
  # Bloated: 30 comment lines vs 18 code = 62%.
  {
    printf '/// Essay line %s narrating history the standard bans.\n' 1 2 3 4 5 6 7 8 9 10
    printf '/// Contract prose %s restating the signature.\n' 1 2 3 4 5 6 7 8 9 10
    printf '/// Provenance %s: AC-1, REQ-2, issue tag.\n' 1 2 3 4 5 6 7 8 9 10
    echo 'struct Bloated {'
    printf '    let field%s: Int\n' 1 2 3 4 5 6 7 8
    printf '    func calc%s() -> Int { field1 * %s }\n' 1 1 2 2 3 3 4 4 5 5 6 6 7 7 8 8
    echo '}'
  } >"$_tmp/Bloated.swift"

  # Lean: 6 comment lines vs 44 code = 12%.
  {
    printf '/// Terse WHY on a non-obvious literal %s.\n' 1 2 3 4 5 6
    echo 'struct Lean {'
    printf '    let field%s: Int\n' 1 2 3 4 5 6 7 8 9 10
    printf '    func calc%s() -> Int { field1 * %s }\n' 1 1 2 2 3 3 4 4 5 5 6 6 7 7 8 8 9 9 10 10
    printf '    var derived%s: Int { field1 + %s }\n' 1 1 2 2 3 3 4 4 5 5 6 6 7 7 8 8 9 9 10 10
    printf '    func extra%s() { }\n' 1 2 3
    echo '}'
  } >"$_tmp/Lean.swift"

  _fail=0

  # 1. Bloated present -> must block, with remediation text.
  _out=$(run_gate "$(read_stdin)" "$_tmp/.context" "$_tmp")
  printf '%s' "$_out" | jq -e '
    .decision == "block"
    and (.hookSpecificOutput.additionalContext | length > 0)
  ' >/dev/null 2>&1 || { echo "dv-comment-density-gate: self-test FAIL (bloated file did not block)"; _fail=1; }

  # 2. Lean only -> must pass silently.
  rm -f "$_tmp/Bloated.swift"
  _out=$(run_gate "$(read_stdin)" "$_tmp/.context" "$_tmp")
  [ -z "$_out" ] || { echo "dv-comment-density-gate: self-test FAIL (lean file blocked)"; _fail=1; }

  # 3. Reviewer agent with the bloated file back -> must stay silent (a reviewer
  #    is never blocked for the writer's bloat).
  printf '/// essay %s\n' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 >"$_tmp/Bloated.swift"
  printf 'struct B%s { let v: Int }\n' 1 2 3 4 5 >>"$_tmp/Bloated.swift"
  _out=$(run_gate '{"agent_type":"igrsoft:technical-lead"}' "$_tmp/.context" "$_tmp")
  [ -z "$_out" ] || { echo "dv-comment-density-gate: self-test FAIL (reviewer agent was blocked)"; _fail=1; }

  # 4. Small edit under the floor -> must stay silent even at high density.
  printf '/// doc %s\n' 1 2 3 >"$_tmp/Tiny.swift"
  echo 'struct Tiny { let v: Int }' >>"$_tmp/Tiny.swift"
  _out=$(run_gate "$(read_stdin)" "$_tmp/.context" "$_tmp")
  [ -z "$_out" ] || { echo "dv-comment-density-gate: self-test FAIL (small edit blocked)"; _fail=1; }

  rm -f "$_tmp/Bloated.swift" "$_tmp/Tiny.swift"

  # 5. Hash-comment language: a bloated .py must block. Under the C-family-only
  #    regex this file scored 0% and passed, which is the defect these two cases
  #    pin down.
  {
    printf '# Essay line %s narrating history the standard bans.\n' 1 2 3 4 5 6 7 8 9 10
    printf '# Contract prose %s restating the signature.\n' 1 2 3 4 5 6 7 8 9 10
    printf '# Provenance %s: AC-1, REQ-2, issue tag.\n' 1 2 3 4 5 6 7 8 9 10
    echo 'class Bloated:'
    printf '    field%s = 0\n' 1 2 3 4 5 6 7 8
    printf '    def calc%s(self): return self.field1 * %s\n' 1 1 2 2 3 3 4 4 5 5 6 6 7 7 8 8
  } >"$_tmp/bloated.py"
  _out=$(run_gate "$(read_stdin)" "$_tmp/.context" "$_tmp")
  printf '%s' "$_out" | jq -e '
    .decision == "block" and (.reason | test("bloated\\.py"))
  ' >/dev/null 2>&1 || { echo "dv-comment-density-gate: self-test FAIL (bloated .py did not block)"; _fail=1; }

  # 6. Lean .py -> must pass. Guards the other direction: Python code lines must
  #    not be miscounted as comments.
  rm -f "$_tmp/bloated.py"
  {
    printf '# Terse WHY on a non-obvious literal %s.\n' 1 2 3 4 5 6
    echo 'class Lean:'
    printf '    field%s = 0\n' 1 2 3 4 5 6 7 8 9 10
    printf '    def calc%s(self): return self.field1 * %s\n' 1 1 2 2 3 3 4 4 5 5 6 6 7 7 8 8 9 9 10 10
    printf '    def derived%s(self): return self.field1 + %s\n' 1 1 2 2 3 3 4 4 5 5 6 6 7 7 8 8 9 9 10 10
    printf '    def extra%s(self): pass\n' 1 2 3
  } >"$_tmp/lean.py"
  _out=$(run_gate "$(read_stdin)" "$_tmp/.context" "$_tmp")
  [ -z "$_out" ] || { echo "dv-comment-density-gate: self-test FAIL (lean .py blocked)"; _fail=1; }

  # 7. Shell: a bloated .sh must block. Shell fell to the C-family regex, so it
  #    scored 0% no matter how much of it was comment.
  {
    echo '#!/usr/bin/env bash'
    printf '# Essay line %s narrating history the standard bans.\n' 1 2 3 4 5 6 7 8 9 10
    printf '# Contract prose %s restating the signature.\n' 1 2 3 4 5 6 7 8 9 10
    printf '# Provenance %s: ticket id, review answer, issue tag.\n' 1 2 3 4 5 6 7 8 9 10
    echo 'set -euo pipefail'
    printf 'field%s=0\n' 1 2 3 4 5 6 7 8
    printf 'calc%s() { echo %s; }\n' 1 1 2 2 3 3 4 4 5 5 6 6 7 7 8 8
  } >"$_tmp/bloated.sh"
  _out=$(run_gate "$(read_stdin)" "$_tmp/.context" "$_tmp")
  printf '%s' "$_out" | jq -e '
    .decision == "block" and (.reason | test("bloated\\.sh"))
  ' >/dev/null 2>&1 || { echo "dv-comment-density-gate: self-test FAIL (bloated .sh did not block)"; _fail=1; }

  # 8. Lean .sh -> must pass. It carries a real shebang and a conventional header
  #    because shell's mandatory preamble is counted as comment: a fixture
  #    without one would overstate how much headroom a real script has.
  rm -f "$_tmp/bloated.sh"
  run_gate "$(read_stdin)" "$_tmp/.context" "$_tmp" >/dev/null
  _checked_before=$(tail -n 1 "$_tmp/.context/logs/audit.jsonl" | jq -r '.metadata.files_checked')
  {
    echo '#!/usr/bin/env bash'
    echo '# prune-artifacts — drop build artifacts past the retention window.'
    echo '#'
    echo '# Requires: find, date. Exits non-zero when the artifact root is absent.'
    echo '# Safe to re-run; deletion is idempotent.'
    echo 'set -euo pipefail'
    printf 'field%s=0\n' 1 2 3 4 5 6 7 8 9 10
    printf 'calc%s() { echo %s; }\n' 1 1 2 2 3 3 4 4 5 5 6 6 7 7 8 8 9 9 10 10
    echo '# Two retries: the artifact store 502s on a cold cache.'
    printf 'derived%s() { echo "derived %s"; }\n' 1 1 2 2 3 3 4 4 5 5 6 6 7 7 8 8 9 9 10 10
    printf 'extra%s() { :; }\n' 1 2 3 4 5 6 7 8
  } >"$_tmp/lean.sh"
  _out=$(run_gate "$(read_stdin)" "$_tmp/.context" "$_tmp")
  [ -z "$_out" ] || { echo "dv-comment-density-gate: self-test FAIL (lean .sh blocked)"; _fail=1; }
  # Silence alone cannot separate a measured pass from a file the extension
  # filter never looked at, so pin the count the audit row reports.
  _checked_after=$(tail -n 1 "$_tmp/.context/logs/audit.jsonl" | jq -r '.metadata.files_checked')
  [ "$_checked_after" -eq $((_checked_before + 1)) ] ||
    { echo "dv-comment-density-gate: self-test FAIL (lean .sh was never measured)"; _fail=1; }

  # 9. Vendored third-party shell must never block: on a dependency refresh the
  #    added lines are code the agent did not write.
  rm -f "$_tmp/lean.sh"
  _vendor_body=$(
    printf '# vendor essay %s\n' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20
    printf 'v%s=0\n' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25
  )
  # Control arm: the identical body outside vendor/ must block, so the pass below
  # is attributable to the path filter and not to the size floor.
  printf '%s\n' "$_vendor_body" >"$_tmp/dep.sh"
  _out=$(run_gate "$(read_stdin)" "$_tmp/.context" "$_tmp")
  printf '%s' "$_out" | jq -e '
    .decision == "block" and (.reason | test("dep\\.sh"))
  ' >/dev/null 2>&1 || { echo "dv-comment-density-gate: self-test FAIL (vendor control fixture did not block)"; _fail=1; }

  rm -f "$_tmp/dep.sh"
  mkdir -p "$_tmp/vendor"
  printf '%s\n' "$_vendor_body" >"$_tmp/vendor/dep.sh"
  _out=$(run_gate "$(read_stdin)" "$_tmp/.context" "$_tmp")
  [ -z "$_out" ] || { echo "dv-comment-density-gate: self-test FAIL (vendored .sh blocked)"; _fail=1; }

  [ "$_fail" -eq 0 ] || exit 1
  echo "dv-comment-density-gate: self-test OK"
  exit 0
fi

PAYLOAD=$(read_stdin)
CTX="${CLAUDE_PROJECT_DIR:-$PWD}/.context"
run_gate "$PAYLOAD" "$CTX" "${CLAUDE_PROJECT_DIR:-$PWD}"
exit 0
