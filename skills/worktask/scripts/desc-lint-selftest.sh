#!/usr/bin/env bash
# desc-lint-selftest.sh — the `--self-test` harness for desc-lint.sh.
#
# SOURCED, never executed: desc-lint.sh loads this file only on the `--self-test`
# path, so the production path never pays for it. Sourcing leaves the caller's
# `$0` and every function it has already defined in scope — this file reads the
# caller's helpers and is not standalone.
#
# Contract: defines `self_test`, returning 0 when every case passes.

self_test() {
  td=$(mktemp -d "${TMPDIR:-/tmp}/desc-lint-XXXXXX")
  trap 'rm -rf "$td"' EXIT
  mkdir -p "$td/agents" "$td/commands" "$td/skills/nested/deep"

  # length parser
  printf -- '---\nname: a\ndescription: short and sweet\nmodel: sonnet\n---\nbody\n' > "$td/ok.md"
  long=$(printf 'x%.0s' {1..130})
  printf -- '---\nname: b\ndescription: |\n  %s\n  %s\nmodel: sonnet\n---\nbody\n' "$long" "$long" > "$td/over.md"
  printf -- '# plain markdown\n' > "$td/plain.md"
  # a frontmatter with no description key at all is skipped, never failed
  printf -- '---\nname: c\nmodel: sonnet\n---\nbody\n' > "$td/nodesc.md"

  # grammar fixtures (agent/skill classes)
  printf -- '---\nname: g\ndescription: Use when reviewing prompt assets. Grammar, routing terms, and cap enforcement.\n---\nbody\n' > "$td/agents/trigger-first.md"
  printf -- '---\nname: g\ndescription: Elite specialist for prompt architecture and model selection.\n---\nbody\n' > "$td/agents/capability-first.md"
  printf -- '---\nname: g\ndescription: Use to review every prompt asset in the plugin catalogue; applies when routing is unclear.\n---\nbody\n' > "$td/agents/no-connective.md"
  printf -- '---\nname: g\ndescription: Use when auditing. First it scores, then it reports. A third sentence lands here.\n---\nbody\n' > "$td/agents/workflow.md"
  printf -- '---\nname: g\ndescription: Use when auditing assets. I will score each description and our team reviews it.\n---\nbody\n' > "$td/agents/first-person.md"
  # G5 must not fire on AI / API / SwiftUI — the word-boundary regression guard
  printf -- '---\nname: g\ndescription: Use when documenting AI, API, or SwiftUI surfaces. Reference docs for routing terms.\n---\nbody\n' > "$td/agents/bare-i-terms.md"
  # commands are exempt from G1-G5 and carry G6 alone
  printf -- '---\nname: g\ndescription: Comprehensive audit of every prompt asset in the plugin.\n---\nbody\n' > "$td/commands/menu-label.md"
  printf -- '---\nname: g\ndescription: Capability-first nested skill, no trigger clause anywhere.\n---\nbody\n' > "$td/skills/nested/deep/SKILL.md"

  pass_files="$td/ok.md $td/plain.md $td/nodesc.md $td/agents/trigger-first.md $td/agents/bare-i-terms.md $td/commands/menu-label.md"
  # shellcheck disable=SC2086
  if ! lint $pass_files >/dev/null; then
    echo "desc-lint self-test: FAIL (compliant fixture flagged)" >&2; exit 2
  fi
  for f in over:G6 agents/capability-first:G1 agents/no-connective:G2 \
           agents/workflow:G3 agents/first-person:G5 skills/nested/deep/SKILL:G1; do
    path="$td/${f%%:*}.md"; rule="${f##*:}"
    if out=$(lint "$path"); then
      echo "desc-lint self-test: FAIL ($rule fixture passed)" >&2; exit 2
    fi
    case "$out" in
      *"[$rule]"*) ;;
      *) echo "desc-lint self-test: FAIL ($rule not reported for $path)" >&2; exit 2 ;;
    esac
    case "$out" in
      *"$path"*) ;;
      *) echo "desc-lint self-test: FAIL (message does not name $path)" >&2; exit 2 ;;
    esac
  done
  # G4 is reported alongside G3 on the workflow fixture; assert it explicitly.
  if out=$(lint "$td/agents/workflow.md"); then :; fi
  case "$out" in
    *"[G4]"*) ;;
    *) echo "desc-lint self-test: FAIL (G4 not reported)" >&2; exit 2 ;;
  esac
  echo "desc-lint self-test: ALL PASS"
}
