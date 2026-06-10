#!/usr/bin/env bash
# desc-lint.sh — frontmatter description-length lint (≤250 chars).
#
# Frontmatter descriptions of every agent, command, and skill are AMBIENT:
# Claude Code injects them into every session's startup context in every
# project with the plugin enabled. CC guidance caps them at ~250 chars.
# Multi-line YAML scalars (`description: |` / `>`) hide overruns from
# single-line greps — this lint joins continuation lines before measuring.
#
# Usage:
#   desc-lint.sh                 # lint agents/*.md commands/*.md skills/*/SKILL.md
#   desc-lint.sh <file> [...]    # lint specific files
#   desc-lint.sh --self-test     # verify the parser against inline fixtures
#
# Exit codes: 0 = all within cap, 1 = at least one over cap, 2 = usage/parser error.
#
# CI / repo-maintenance helper only — never read by agents at runtime.

set -euo pipefail

CAP=250

lint() {
  python3 - "$@" <<'PYEOF'
import re, sys

CAP = 250

def desc_len(path):
    try:
        t = open(path, encoding='utf-8').read()
    except OSError as e:
        print(f"desc-lint: cannot read {path}: {e}", file=sys.stderr)
        return None
    m = re.match(r'^---\r?\n(.*?)\r?\n---', t, re.S)
    if not m:
        return None  # no frontmatter — nothing to lint
    out, cap = [], False
    for ln in m.group(1).split('\n'):
        if re.match(r'^description:', ln):
            cap = True
            v = ln.split(':', 1)[1].strip()
            if v and v not in ('|', '>', '|-', '>-'):
                out.append(v)
            continue
        if cap:
            if re.match(r'^\S', ln):
                break  # next top-level key
            out.append(ln.strip())
    return len(' '.join(' '.join(out).split())) if out else 0

fail = 0
for path in sys.argv[1:]:
    n = desc_len(path)
    if n is None:
        continue
    status = "OVER" if n > CAP else "ok"
    if n > CAP:
        fail = 1
        print(f"desc-lint: {path}: {n} chars (cap {CAP}) — {status}")
    else:
        print(f"desc-lint: {path}: {n} chars ok")
sys.exit(fail)
PYEOF
}

self_test() {
  td=$(mktemp -d -t desc-lint-XXXXXX)
  trap 'rm -rf "$td"' EXIT
  # fixture 1: single-line, within cap
  printf -- '---\nname: a\ndescription: short and sweet\nmodel: sonnet\n---\nbody\n' > "$td/ok.md"
  # fixture 2: multi-line block scalar, over cap
  long=$(printf 'x%.0s' {1..130})
  printf -- '---\nname: b\ndescription: |\n  %s\n  %s\nmodel: sonnet\n---\nbody\n' "$long" "$long" > "$td/over.md"
  # fixture 3: no frontmatter
  printf -- '# plain markdown\n' > "$td/plain.md"

  if ! lint "$td/ok.md" "$td/plain.md" >/dev/null; then
    echo "desc-lint self-test: FAIL (ok fixture flagged)" >&2; exit 2
  fi
  if lint "$td/over.md" >/dev/null; then
    echo "desc-lint self-test: FAIL (over fixture passed)" >&2; exit 2
  fi
  echo "desc-lint self-test: ALL PASS"
}

case "${1:-}" in
  --self-test) self_test ;;
  "")
    cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
    # shellcheck disable=SC2046
    lint $(ls agents/*.md commands/*.md skills/*/SKILL.md 2>/dev/null) | { grep -v " ok$" || true; }
    # re-run for exit code (grep above consumes it)
    lint $(ls agents/*.md commands/*.md skills/*/SKILL.md 2>/dev/null) >/dev/null
    ;;
  *) lint "$@" ;;
esac
