#!/usr/bin/env bash
# attachments-preseed.sh — renders the two Conductor-convention attachments
# (`.context/attachments/PR instructions.md` and `Review request.md`).
#
# Canonical template source: skills/worktask/references/conductor-attachments.md
# (§ Template — `PR instructions.md`, § Template — `Review request.md`). The
# bodies below are the concatenation of that file's `Template part N` fenced
# blocks in order, verbatim; the placeholder tokens are the ones its
# § Data sources table defines. Keep the two in sync — this script is Writer 1
# (orchestrator pre-gate, skills/worktask/references/fn-gate.md) and the FN
# agent's Writer 2 renders from the same document.
#
# Usage:
#   attachments-preseed.sh [--workdir DIR] [--worktask-id ID] [--branch NAME]
#                          [--base-branch NAME] [--run-index N]
#                          [--commit-type TYPE] [--issue-ref N]
#                          [--uncommitted N] [--upstream NAME|--no-upstream]
#                          [--ts ISO8601]
#   attachments-preseed.sh --self-test
#
# Exit codes: 0 written, 2 usage, 3 base branch unresolved.
#
# Every input is auto-resolved from git / .context/state.json when the flag is
# omitted, so the orchestrator can invoke it with no arguments from the
# worktask root.

set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

WORKDIR="."
WORKTASK_ID=""
BRANCH=""
BASE_BRANCH=""
RUN_INDEX=""
COMMIT_TYPE=""
ISSUE_REF=""
UNCOMMITTED=""
UPSTREAM=""
UPSTREAM_SET=0
ISO_TS=""
MODE="write"

usage() {
  cat >&2 <<'USAGE'
usage: attachments-preseed.sh [--workdir DIR] [--worktask-id ID] [--branch NAME]
                              [--base-branch NAME] [--run-index N]
                              [--commit-type TYPE] [--issue-ref N]
                              [--uncommitted N] [--upstream NAME|--no-upstream]
                              [--ts ISO8601]
       attachments-preseed.sh --self-test
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workdir)      WORKDIR="${2:?--workdir needs a value}"; shift 2 ;;
    --worktask-id)  WORKTASK_ID="${2:?--worktask-id needs a value}"; shift 2 ;;
    --branch)       BRANCH="${2:?--branch needs a value}"; shift 2 ;;
    --base-branch)  BASE_BRANCH="${2:?--base-branch needs a value}"; shift 2 ;;
    --run-index)    RUN_INDEX="${2:?--run-index needs a value}"; shift 2 ;;
    --commit-type)  COMMIT_TYPE="${2:?--commit-type needs a value}"; shift 2 ;;
    --issue-ref)    ISSUE_REF="${2:?--issue-ref needs a value}"; shift 2 ;;
    --uncommitted)  UNCOMMITTED="${2:?--uncommitted needs a value}"; shift 2 ;;
    --upstream)     UPSTREAM="${2:?--upstream needs a value}"; UPSTREAM_SET=1; shift 2 ;;
    --no-upstream)  UPSTREAM=""; UPSTREAM_SET=1; shift ;;
    --ts)           ISO_TS="${2:?--ts needs a value}"; shift 2 ;;
    --self-test)    MODE="self-test"; shift ;;
    -h|--help)      usage; exit 2 ;;
    *) printf >&2 'attachments-preseed.sh: unknown arg: %s\n' "$1"; usage; exit 2 ;;
  esac
done

# ---------------------------------------------------------------- audit ----

# The one audit-row appender for the plugin (skills/shared/lib/audit-lib.sh). `[ -r ]`
# before the `.`: a bare `.` on a missing file is a special-builtin error that exits the
# shell immediately, bypassing an `if !` guard.
_AUDIT_LIB="$SELF_DIR/../../shared/lib/audit-lib.sh"
if [ ! -r "$_AUDIT_LIB" ]; then
  printf >&2 'attachments-preseed: plugin install broken — audit-lib.sh not found\n'
  exit 2
fi
# shellcheck source=../../shared/lib/audit-lib.sh
. "$_AUDIT_LIB"

# The row gains a `ts` and carries `reason` under `metadata`, which is where every other
# emitter in the plugin puts it. This was the one row in the plugin with no timestamp —
# an audit row with no time is evidence that cannot be ordered against any other.
#
# `--meta-kv`, not `--meta`: the library drops an arbitrary JSON literal on a jq-less host
# (it cannot be made injection-safe without a parser) but renders a flat pair under the
# same sanitiser, so the reason survives the degradation that the FN refusal path needs.
audit_failed() {
  corpflow_audit_row --file "$WORKDIR/.context/logs/audit.jsonl" --actor orchestrator \
    --action fn_attachments_preseed_failed --subject "FN${RUN_INDEX:-0}" \
    --result error --meta-kv "reason=$1"
}

# ------------------------------------------------------------ resolvers ----

json_str() {
  # $1 = file, $2..= jq path segments. Prints the value or nothing. jq is a
  # hard prerequisite of the suite, but the writer must still degrade to its
  # documented defaults on a host without it rather than abort the FN gate.
  [[ -f "$1" ]] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  jq -r "$2 // empty" "$1" 2>/dev/null || return 0
}

first_match() {
  # $1 = file, $2 = grep -E pattern. Prints the first matching whole line.
  [[ -f "$1" ]] || return 0
  grep -m1 -E "$2" "$1" 2>/dev/null || return 0
}

section_bullets() {
  # $1 = file, $2 = heading text. Emits the section's non-blank lines as `- `
  # bullets, or nothing when the file or section is absent/empty.
  [[ -f "$1" ]] || return 0
  awk -v h="$2" '
    $0 ~ "^## " h {found=1; next}
    found && /^## / {found=0}
    found && NF {print "- " $0}
  ' "$1"
}

STATE="$WORKDIR/.context/state.json"

if [[ -z "$RUN_INDEX" ]]; then
  RUN_INDEX="$(json_str "$STATE" '.run_index')"
  RUN_INDEX="${RUN_INDEX:-0}"
fi

if [[ -z "$WORKTASK_ID" ]]; then
  WORKTASK_ID="$(json_str "$STATE" '.worktask_id')"
  WORKTASK_ID="${WORKTASK_ID:-unknown}"
fi

if [[ -z "$BRANCH" ]]; then
  BRANCH="$(git -C "$WORKDIR" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  [[ -n "$BRANCH" ]] || BRANCH="$(json_str "$STATE" '.facts.branch')"
  BRANCH="${BRANCH:-HEAD}"
fi

# Base-branch resolution order is conductor-attachments.md § Git & branch state,
# highest first. There is deliberately NO literal fallback: an unresolved base
# would silently target the wrong branch in the rendered `gh pr create` command.
if [[ -z "$BASE_BRANCH" ]]; then
  BASE_BRANCH="${FN_BASE_REF:-}"
  [[ -n "$BASE_BRANCH" ]] || BASE_BRANCH="$(json_str "$STATE" '.metadata.base_ref')"
  [[ -n "$BASE_BRANCH" ]] || BASE_BRANCH="$(json_str "$STATE" '.git.base_branch')"
  [[ -n "$BASE_BRANCH" ]] || BASE_BRANCH="$(json_str "$WORKDIR/workspace.json" '.git.base_branch')"
  if [[ -z "$BASE_BRANCH" ]]; then
    BASE_BRANCH="$(git -C "$WORKDIR" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null || true)"
    BASE_BRANCH="${BASE_BRANCH#refs/remotes/origin/}"
  fi
fi
if [[ -z "$BASE_BRANCH" ]] && [[ "$MODE" != "self-test" ]]; then
  printf >&2 'attachments-preseed.sh: base branch unresolved — pass --base-branch\n'
  audit_failed "base_branch_unresolved"
  exit 3
fi

if [[ -z "$COMMIT_TYPE" ]]; then
  # conductor-attachments.md § Plan, issue & verdict fields: the type comes from
  # facts.goal via branch-lib's derive_type, NOT from the plan file.
  GOAL="$(json_str "$STATE" '.facts.goal')"
  if [[ -n "$GOAL" && -r "$SELF_DIR/branch-lib.sh" ]]; then
    # shellcheck source=/dev/null
    . "$SELF_DIR/branch-lib.sh"
    COMMIT_TYPE="$(derive_type "$GOAL")"
  fi
  COMMIT_TYPE="${COMMIT_TYPE:-feature}"
fi

if [[ -z "$ISSUE_REF" ]]; then
  ISSUE_REF="$(json_str "$WORKDIR/workspace.json" '.issue_number')"
  [[ -n "$ISSUE_REF" ]] || ISSUE_REF="$(json_str "$STATE" '.metadata.issue_ref')"
fi
ISSUE_REF="${ISSUE_REF#\#}"

if [[ -z "$UNCOMMITTED" ]]; then
  UNCOMMITTED="$(git -C "$WORKDIR" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
  UNCOMMITTED="${UNCOMMITTED:-0}"
fi

if [[ "$UPSTREAM_SET" -eq 0 ]]; then
  UPSTREAM="$(git -C "$WORKDIR" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
fi
if [[ -n "$UPSTREAM" ]]; then
  UPSTREAM_LINE="Upstream tracking: origin/${BRANCH}."
else
  UPSTREAM_LINE="No upstream branch yet — use \`git push -u origin ${BRANCH}\`."
fi

ISO_TS="${ISO_TS:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"

CTX="$WORKDIR/.context"
DR_FILE="$CTX/developer-review-${RUN_INDEX}.md"
QA_FILE="$CTX/testing-${RUN_INDEX}.md"

DR_VERDICT="$(first_match "$DR_FILE" 'Approval Status')"
DR_VERDICT="${DR_VERDICT:-unknown}"
QA_VERDICT="$(first_match "$QA_FILE" 'GO/NO-GO')"
QA_VERDICT="${QA_VERDICT:-unknown}"

DR_CONCERNS="$(section_bullets "$DR_FILE" 'Issues Found')"
DR_CONCERNS="${DR_CONCERNS:-(none flagged)}"
QA_NOTES="$(section_bullets "$QA_FILE" 'Results')"
QA_NOTES="${QA_NOTES:-(none)}"

if [[ -n "$ISSUE_REF" ]]; then
  ISSUE_LINE="- Issue: #${ISSUE_REF} — include \`Closes #${ISSUE_REF}\` in the PR body to auto-close on merge."
else
  ISSUE_LINE=""
fi

# ----------------------------------------------------------- rendering ----

substitute() {
  # Reads $1, resolves every placeholder, writes back. The `X` sentinel keeps
  # command substitution from eating the template's trailing newlines, which
  # the byte-equivalence contract in conductor-attachments.md depends on.
  local f="$1" c
  c="$(cat "$f"; printf 'X')"
  c="${c%X}"

  # `<N>` is overloaded in the source template — it is the uncommitted count in
  # part 1/part 3 and the ISSUE number in part 7's `Closes #<N>` checklist row.
  # Substituting it globally would rewrite the checklist, so both intended
  # sites are matched with their surrounding text instead.
  c="${c//- Uncommitted changes: <N>/- Uncommitted changes: ${UNCOMMITTED}}"
  c="${c//The worktask reports \`<N>\`/The worktask reports \`${UNCOMMITTED}\`}"

  if [[ -n "$ISSUE_LINE" ]]; then
    c="${c//<ISSUE_LINE>/${ISSUE_LINE}}"
  else
    c="${c//<ISSUE_LINE>$'\n'/}"
  fi
  if [[ -n "$ISSUE_REF" ]]; then
    c="${c//<ISSUE>/${ISSUE_REF}}"
  fi

  c="${c//<WORKTASK_ID>/${WORKTASK_ID}}"
  c="${c//<ISO_TS>/${ISO_TS}}"
  c="${c//<BASE_BRANCH>/${BASE_BRANCH}}"
  c="${c//<BRANCH>/${BRANCH}}"
  c="${c//<UPSTREAM_LINE>/${UPSTREAM_LINE}}"
  c="${c//<TYPE>/${COMMIT_TYPE}}"
  c="${c//<DR_VERDICT>/${DR_VERDICT}}"
  c="${c//<QA_VERDICT>/${QA_VERDICT}}"
  c="${c//<DR_CONCERNS_BULLETS>/${DR_CONCERNS}}"
  c="${c//<QA_NOTES_BULLETS>/${QA_NOTES}}"

  printf '%s' "$c" > "$f"
}

write_pr_instructions() {
  local out="$1"
  cat > "$out" <<'PRESEED_EOF'
<!-- Generated by corpflow FN stage. worktask_id: <WORKTASK_ID>, ts: <ISO_TS> -->

The corpflow worktask has finished and is ready to ship.

- Branch: <BRANCH>  →  Target: origin/<BASE_BRANCH>
- Uncommitted changes: <N>
- Upstream: <UPSTREAM_LINE>
- Suggested commit type: **<TYPE>** (per `rules/git-conventions.md`, Conventional Commits 1.0.0)
- Worktask summary: `.context/complete-summary-N.md` (N = `run_index`; fallback newest `.context/complete-summary-*.md`)
<ISSUE_LINE>
<!-- If issue ref present: "- Issue: #<ISSUE> — include `Closes #<ISSUE>` in the PR body to auto-close on merge." -->

The user requested a PR. Follow the steps below.

## 0. Skill precedence

If you have any skill related to creating PRs, invoke it now. Instructions there take precedence over this file.

## 1. Pre-flight (don't skip)

- Check for an existing PR: `gh pr view --json url,state -q '"\(.state) \(.url)"' 2>/dev/null`. If one exists and is **OPEN**, push new commits to its branch and **stop** — do not open a duplicate. Report the existing URL.
- `git fetch origin <BASE_BRANCH>` and confirm no merge conflicts: `git merge-tree $(git merge-base HEAD origin/<BASE_BRANCH>) HEAD origin/<BASE_BRANCH>` (empty output = clean).
- Self-review the diff with `mcp__conductor__GetWorkspaceDiff` (start `stat: true`, then drill into hot files). Look for: debug prints, commented-out code, hardcoded secrets/keys, unintended large binaries, unrelated formatting churn. If any are found, fix them and add a follow-up commit before continuing — do not push junk.
- Confirm working tree is clean: `git status --porcelain` should be empty (or only intentional WIP). The worktask reports `<N>` uncommitted changes; reconcile any drift before pushing.
- The branch was already named once, at the start of planning (`skills/shared/git-conventions.md § Branch Naming`) — nothing renames it here.

## 2. Push

- Validate `facts.branch` (`^[A-Za-z0-9._/-]+$`; empty/failed → plain push), then push under the ledger name: `git push -u origin HEAD:refs/heads/<facts.branch>`. Otherwise, if upstream is already set to that name, plain `git push`.
- Do **NOT** amend or squash existing commits unless the user explicitly asks. The worktask's commit boundaries carry stage context.

## 3. Open the PR

Run `gh pr create --base <BASE_BRANCH>` with:

- **Title** ≤ 72 chars, format `<TYPE>[scope]: <Summary>` (matches commit subject style; see `rules/git-conventions.md`). Suggested type: **<TYPE>**.
- **Body** via HEREDOC (preserves formatting). Use this skeleton — fill from `.context/complete-summary-N.md`:

  ```markdown
  ## Motivation
  <Why this change exists — link to the user need / bug / requirement>

  ## Changes
  - <Change 1, user-visible language>
  - <Change 2>

  ## Test plan
  - [ ] <How a reviewer can verify locally — commands, URLs, screenshots>

  <!-- ## Visual evidence — inserted here when UI changed (see below) -->

  ## Notes
  <Risks, follow-ups, deliberate non-goals. Omit section if empty.>

  Closes #<ISSUE>
  ```

  **Visual evidence section** (between `## Test plan` and `## Notes`): on a UI-change run, run `skills/worktask/scripts/attach-visual-evidence.sh --emit pr` and insert its stdout verbatim. The helper self-gates — it prints the `## Visual evidence` block (hosted image refs + manifest reference) when `metadata.requires_screenshots == true` AND captures exist, and prints **nothing** otherwise (flag false / no captures). Insert the block only when stdout is non-empty; never hand-author the section. Image hosting reuses the publish-helper host tiers; the manifest reference is path-free, so no `.context/` path reaches the body. Invoke it unconditionally; the empty-stdout case omits the section. `fn-preflight.sh pr-body` verifies the helper's `visual_evidence_pr_emitted` row for **this** run and blocks a body that dropped the block — a hand-authored body will not pass, and it then runs `pr-body-lint.sh` (warn-only) over the sanitised body.

  **If captures exist but none embedded**, the helper prints a `NOTICE` on stderr and writes a `visual_evidence_degraded` audit row carrying `captured`, `embedded` and a `reason`. Surface that row at the FN gate — it means reviewers will see no images. `reason=probe_timeout` or `token_invalid` is fixed by exporting **`GH_SESSION_TOKEN`**, which lets the `gh image` uploader skip browser-cookie extraction (slow, and blocking on a Keychain prompt when non-interactive).

  The trailing `Closes #<ISSUE>` line is **REQUIRED** on its own line whenever an issue number is resolvable (see FN validator in `agents/project-manager.md § FN Stage`). Multiple closes lines (`Closes #A`, `Closes #B`) are permitted for PRs that close several issues. Omit ONLY when no issue number can be resolved from any source — in that case the FN audit writes one `pr_issue_link: deferred` row and the PR proceeds without the line.

- Cover **all** commits in the workspace diff vs. `origin/<BASE_BRANCH>`, not just the most recent commit.
- Keep the body grounded in observable facts from the diff/summary — no speculation, no marketing language.

### PR-body checklist (must hold before `gh pr create`)

- [ ] Title ≤ 72 chars, `<TYPE>[scope]: <Summary>` format
- [ ] `## Motivation`, `## Changes`, `## Test plan` sections present
- [ ] **`Closes #<N>` line present on its own line when issue number is resolvable** (regex match: `(?im)^(?:Closes|Fixes|Resolves)\s+#\d+\s*$`)
- [ ] Body reflects ALL workspace-diff commits, not only HEAD

## 4. Failure escape hatches

- `gh: command not found` or `gh auth status` failure → stop and ask the user to authenticate; do not fall back to `git request-pull` or web URLs.
- Push rejected (non-fast-forward) → run `git fetch && git log HEAD..@{u} --oneline`; ask the user before force-pushing.
- `gh pr create` exits non-zero with an unfamiliar error → capture the stderr verbatim in your reply and ask the user.

If any other step fails, ask the user — do not improvise destructive recovery.
PRESEED_EOF
  substitute "$out"
}

write_review_request() {
  local out="$1"
  cat > "$out" <<'PRESEED_EOF'
<!-- Generated by corpflow FN stage. worktask_id: <WORKTASK_ID>, ts: <ISO_TS> -->

# Review guidelines

You are reviewing code produced by an automated multi-stage worktask that
already passed an internal Developer Review (DR) and QA. Your job is to
catch what those stages missed — not to re-do their work.

## Worktask context

- Worktask ID: <WORKTASK_ID>
- Branch: <BRANCH>  →  Target: origin/<BASE_BRANCH>
- DR verdict: <DR_VERDICT>   (`.context/developer-review-N.md`)
- QA verdict: <QA_VERDICT>   (`.context/testing-N.md`)
- Summary: `.context/complete-summary-N.md` § Summary

## Scope

Review only **changes introduced by this branch** vs. `origin/<BASE_BRANCH>`.
Do not flag pre-existing issues visible in surrounding context lines, even
if real — they belong in a separate PR.

## Focus areas (auto-extracted)

DR concerns the worktask surfaced but did not block on:
<DR_CONCERNS_BULLETS>
<!-- One bullet per "Issues Found" line; "(none flagged)" if empty -->

QA observations worth a second look:
<QA_NOTES_BULLETS>
<!-- Non-blocking notes from testing.md; "(none)" if empty -->

These are starting points, not the full scope. Do not simply restate them
as findings — DR already saw them. Use them to direct attention.

## When to flag a finding

A finding must satisfy ALL of:

1. Meaningfully impacts accuracy, performance, security, or maintainability.
2. Discrete and actionable.
3. **Introduced by this branch** (not pre-existing in the file).
4. The original author would fix it if they were aware.
5. Does not rely on unstated assumptions about the codebase.
6. Not just an intentional design choice.

If nothing meets the bar, return zero findings. Inventing issues to look
thorough wastes the author's time and erodes trust in the review.

## Severity (use exactly these three)

- **blocking** — correctness, security, data-loss, or breaking-change risk. Must fix before merge.
- **important** — meaningful quality issue (perf, maintainability, missing test for new code path). Should fix; discuss if you disagree.
- **nit** — minor improvement. Author may close without action.

Severity must match impact. Do not inflate to be heard.

## Do NOT flag

- Style or formatting if the linter passes.
- Naming preferences without a concrete readability problem.
- "Have you considered <alternative pattern>" when current code works and is consistent with the codebase.
- Pre-existing issues unrelated to this branch.
- Missing tests for code paths the branch did not touch.
- Speculative future scaling concerns with no current impact.
- Items DR or QA already explicitly accepted (see Focus areas above).

## Comment style

- One comment per distinct issue. Use a multi-line range only when needed.
- Use ` ```suggestion ` blocks ONLY for concrete replacement code; preserve exact leading whitespace; no commentary inside the block.
- One paragraph max per comment. Inline code via backticks; code blocks ≤ 3 lines.
- Tone: matter-of-fact, not accusatory; not flattering. No "Great job", no "Thanks for".
- Prefer questions over commands when uncertain ("What happens if `items` is empty?" beats "Add a length check.").

## Getting the diff

Prefer `mcp__conductor__GetWorkspaceDiff` (start with `stat: true`, then request specific files).

Fallback when the tool is unavailable:

```bash
MERGE_BASE=$(git merge-base origin/<BASE_BRANCH> HEAD)
git diff $MERGE_BASE HEAD       # committed changes
git diff HEAD                    # uncommitted work in progress
```

Review both outputs together. No need to mention which strategy you used.

If the diff exceeds ~1000 changed lines, focus on the highest-risk files
first (auth, persistence, public APIs, config). Note in your summary that
review was scoped due to size — do not silently skip files.

## Output

1. **Inline comments first** — post via `mcp__conductor__DiffComment`, one per unique issue, severity prefix (e.g. `**blocking**: …`).
2. **Then a top-level summary**:

```
## Review summary
Verdict: <approve | approve-with-nits | request-changes>
Findings: <B blocking, I important, N nits>

### #1 <Short title>  (<severity>)
<One-paragraph explanation>
File: <path>:<line>

### #2 <Short title>  (<severity>)
…
```

If verdict is **approve** with zero findings, write only:

```
## Review summary
Verdict: approve. No findings meet the bar.
```
PRESEED_EOF
  substitute "$out"
}

emit() {
  local dir="$WORKDIR/.context/attachments"
  mkdir -p "$dir"
  write_pr_instructions "$dir/PR instructions.md"
  write_review_request "$dir/Review request.md"
  printf '%s\n' "$dir/PR instructions.md" "$dir/Review request.md"
}

# ----------------------------------------------------------- self-test ----

if [[ "$MODE" == "self-test" ]]; then
  td="$(mktemp -d -t preseed-selftest-XXXXXX)"
  trap 'rm -rf "$td"' EXIT
  WORKDIR="$td"; BASE_BRANCH="main"; BRANCH="feature/x"; WORKTASK_ID="self-test"
  UNCOMMITTED=0; UPSTREAM=""; UPSTREAM_LINE="No upstream branch yet — use \`git push -u origin ${BRANCH}\`."
  mkdir -p "$td/.context"
  emit >/dev/null
  rc=0
  for f in "$td/.context/attachments/PR instructions.md" "$td/.context/attachments/Review request.md"; do
    [[ -s "$f" ]] || { printf >&2 'FAIL: %s not written\n' "$f"; rc=1; }
    # Every placeholder the § Data sources table defines must be resolved. The
    # skeleton's own angle-bracket prose (<Change 1>, <severity>, …) is not a
    # placeholder, so the check is on the exact token list, not on `<...>`.
    if grep -qE '<(WORKTASK_ID|ISO_TS|BRANCH|BASE_BRANCH|UPSTREAM_LINE|DR_VERDICT|QA_VERDICT|DR_CONCERNS_BULLETS|QA_NOTES_BULLETS|ISSUE_LINE)>' "$f"; then
      printf >&2 'FAIL: unresolved placeholder in %s\n' "$f"; rc=1
    fi
  done
  if [[ $rc -eq 0 ]]; then
    echo "PASS: attachments-preseed.sh --self-test"
  fi
  exit "$rc"
fi

emit
