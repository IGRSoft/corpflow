#!/usr/bin/env bash
# @description capability-registry.sh — emit every command, agent, skill, hook, skill
#   script and harness module this plugin ships, one line each, as `path — description`.
#
#   Exists because search cannot close the gap it is aimed at. 9 of the 16 standing
#   `buried` failures are requests for a capability the repo ALREADY ships, missed because
#   the request states a need in user words while the registry states a domain in ours, with
#   no term in common. Keyword search bridged 4 of 9 such cases; a model reading the list
#   bridges more, because the gap is semantic rather than lexical.
#
#   The executable classes were added after the 0.0.1 capture measured where search
#   actually fails: every one of the 8 search misses grounded on a hook, a skill script or
#   a harness module — precisely the classes the markdown-only registry did not enumerate,
#   and the ones behaviour search resolved two times in three.
#
#   No worked example is given here on purpose: this file is inside the tree the model
#   searches, so a prompt printed beside its answer converts that eval case into a lookup.
#
#   The whole inventory is ~148 lines / ~7k tokens, so this REPLACES a search rather
#   than seeding one: enumeration is complete by construction, which is the point. A
#   search needs a stop condition the searcher cannot evaluate; a bounded list does not.
#
#   Deliberately NOT enumerated: tests/, evals/, skills/*/references/, skills/shared/*.md
#   and any */tests/ subtree. Those hold the surfaces the eval corpus grounds its remaining
#   search cases on; listing them would convert that measurement into a lookup, exactly as
#   the executable classes did to the tranche they replaced. The exclusion is on shared
#   CANON, not on shared code — a script under skills/shared/*/scripts/ is a capability like
#   any other and is listed.
#
#   Description source, per class: markdown takes frontmatter `description:` only — never
#   body text; shell takes `@description` when present, else the first comment block after
#   the shebang; Python takes the module docstring's summary paragraph. A file whose class
#   yields no description emits NO line rather than a half-formed one — a capability that
#   cannot say what it is for is a bug to fix at the source, not to paper over here.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

# Shared tail for every extractor: fold whitespace, strip wrapping quotes.
normalize() {
  printf '%s' "$1" | tr -s '[:space:]' ' ' | sed "s/^['\"]//; s/['\"]\$//; s/^[[:space:]]*//; s/[[:space:]]*\$//"
}

emit_line() {
  local file="$1" desc
  desc="$(normalize "$2")"
  [ -n "$desc" ] && printf '%s — %s\n' "$file" "$desc"
  return 0
}

desc_markdown() {
  # Frontmatter only: stop at the next key or the closing fence, so a multi-line
  # description folds but a body heading never leaks in.
  awk '
    /^description:[[:space:]]*/ { sub(/^description:[[:space:]]*/, ""); buf=$0; inside=1; next }
    inside && /^[a-z_-]+:/     { exit }
    inside && /^---/           { exit }
    inside                     { buf = buf " " $0 }
    END                        { print buf }
  ' "$1"
}

desc_shell() {
  # Two header shapes are in use and both must work: an explicit `@description`
  # (with hanging-indent continuation lines) and a bare comment block. Prefer the
  # tag when present — a file that declares one means that line, not its neighbours.
  # `@file`/`@`-tagged lines are metadata, never prose, so they never enter the buffer.
  awk '
    NR == 1 && /^#!/            { next }
    /^#[[:space:]]*@description/ {
      sub(/^#[[:space:]]*@description[[:space:]]*:?[[:space:]]*/, "")
      buf = $0; tagged = 1; inside = 1; next
    }
    tagged && /^#[[:space:]]*@/ { exit }            # next tag closes the description
    tagged && /^#[[:space:]]*$/ { exit }            # blank comment line closes the block
    tagged && /^#/              { sub(/^#[[:space:]]*/, ""); buf = buf " " $0; next }
    tagged                      { exit }            # first non-comment line closes it
    /^#[[:space:]]*@/           { next }            # untagged file: skip @file and friends
    /^#[[:space:]]*$/           { if (inside) exit; next }
    /^#/                        { sub(/^#[[:space:]]*/, ""); buf = (inside ? buf " " $0 : $0); inside = 1; next }
                                { if (inside) exit }
    END                         { print buf }
  ' "$1"
}

desc_python() {
  # The module docstring's summary paragraph — its first blank-line-delimited block,
  # folded. A one-line docstring is that block; a wrapped opening sentence would be cut
  # mid-clause by taking the first physical line only.
  python3 - "$1" <<'PY'
import ast, sys
try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        doc = ast.get_docstring(ast.parse(fh.read()))
except (OSError, SyntaxError, ValueError):
    doc = None
if doc:
    print(doc.strip().split("\n\n", 1)[0])
PY
}

main() {
  cd "$ROOT"

  local f
  for f in commands/*.md agents/*.md skills/*/SKILL.md; do
    [ -f "$f" ] && emit_line "$f" "$(desc_markdown "$f")"
  done

  # benchmark/*.sh is the harness entry point; skills/*/*/scripts/ catches a skill that
  # nests its code one level deeper (skills/shared/milestone-helpers/), which the flat
  # skills/*/scripts/ glob silently skipped.
  for f in hooks/*.sh benchmark/*.sh skills/*/scripts/*.sh skills/*/*/scripts/*.sh; do
    [ -f "$f" ] && emit_line "$f" "$(desc_shell "$f")"
  done

  for f in skills/*/scripts/*.py; do
    [ -f "$f" ] && emit_line "$f" "$(desc_python "$f")"
  done

  # Harness modules only — benchmark/harness/**/tests/ is test scaffolding, and it is also
  # where eval cases ground, so enumerating it would answer the cases it is meant to test.
  while IFS= read -r f; do
    emit_line "$f" "$(desc_python "$f")"
  done < <(find benchmark/harness -type f -name '*.py' -not -path '*/tests/*' | sort)
}

# Sourceable so the extractors can be tested against fixtures without a tree that
# happens to contain every shape.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
