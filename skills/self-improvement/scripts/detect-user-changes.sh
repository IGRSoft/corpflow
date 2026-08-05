#!/usr/bin/env bash
# detect-user-changes.sh — find the last agent commit, diff agent_sha..HEAD,
# emit a per-path change table and full unified diff.
#
# Usage:
#   detect-user-changes.sh <agent_sha_hint>   # pass explicit SHA; else auto-detect
#
# Output to stdout:
#   <path>\t<lines_added>\t<lines_removed>    (one row per changed file)
#
# Side effects:
#   - writes full unified diff to $DIFF_OUT (env var, required)
#   - writes run metadata to $LOG_OUT (env var, required)
#
# Exit codes:
#   0 — success (may be zero rows if no changes)
#   1 — git error or environment missing
#   2 — could not identify agent commit baseline

set -euo pipefail

: "${DIFF_OUT:?DIFF_OUT env var required}"
: "${LOG_OUT:?LOG_OUT env var required}"

HINT="${1:-}"

# Resolve baseline SHA.
# Priority 1: explicit hint.
# Priority 2: most recent commit with an `Agent:` trailer.
# Priority 3: HEAD (no edits since last commit → empty diff is expected).
resolve_baseline() {
  if [ -n "$HINT" ] && git rev-parse --verify --quiet "$HINT^{commit}" >/dev/null; then
    echo "$HINT"
    return 0
  fi

  # Find most recent commit whose trailer contains `Agent:`
  local sha
  sha="$(git log --max-count=50 --grep='^Agent: ' --format='%H' 2>/dev/null | head -n 1 || true)"

  if [ -n "$sha" ]; then
    echo "$sha"
    return 0
  fi

  # Fallback — HEAD (means "compare HEAD vs working tree only")
  git rev-parse HEAD
}

BASELINE="$(resolve_baseline)"
if [ -z "$BASELINE" ]; then
  echo "error: could not resolve baseline SHA" >&2
  exit 2
fi

# Write log header
{
  echo "# Self-Improvement Run Log"
  echo
  echo "**Generated:** $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "**Baseline SHA:** $BASELINE"
  echo "**Head:** $(git rev-parse HEAD) (+ working tree)"
  echo
} >> "$LOG_OUT"

# Full unified diff: committed changes + uncommitted working tree
# Exclude .context/ internals and binary files from review surface
EXCLUDES=(
  ':(exclude).context/logs/**'
  ':(exclude).context/errors/**'
  ':(exclude).context/learnings.md'
  ':(exclude)skills/self-improvement/**'
)

# `git diff <commit>` diffs the baseline against the WORKING TREE, so staged and
# unstaged edits are already included. Unioning a second bare `git diff` on top
# replayed every uncommitted hunk twice — duplicated in the patch, double-counted
# in the numstat totals.
git diff "$BASELINE" -- "${EXCLUDES[@]}" > "$DIFF_OUT" 2>/dev/null || true

# Per-file change summary (additions/removals)
{ git diff --numstat "$BASELINE" -- "${EXCLUDES[@]}" 2>/dev/null || true; } | awk '
  NF == 3 && $1 != "-" && $2 != "-" {
    add[$3] += $1
    rem[$3] += $2
  }
  END {
    for (p in add) printf "%s\t%d\t%d\n", p, add[p], rem[p]
  }
' | sort -u

exit 0
