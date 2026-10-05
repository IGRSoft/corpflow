#!/usr/bin/env bash
# section-lint-selftest.sh — the `--self-test` harness for section-lint.sh.
#
# SOURCED, never executed: section-lint.sh loads this file only on the `--self-test`
# path, so the production path never pays for it. Sourcing leaves the caller's
# `$0` and every function it has already defined in scope — this file reads the
# caller's helpers and is not standalone.
#
# Contract: defines `self_test`, returning 0 when every case passes.

self_test() {
  td=$(mktemp -d "${TMPDIR:-/tmp}/section-lint-XXXXXX")
  trap 'rm -rf "$td"' EXIT

  # fixture 1: one section within cap
  printf -- '## ok section\nshort body\n' > "$td/ok.md"
  # fixture 2: one section over cap
  { printf -- '## big section\n'; printf 'x%.0s' $(seq 1 1100); printf '\n'; } > "$td/over.md"
  # fixture 3: heading-lookalike inside a fence stays in the enclosing section
  printf -- '## real\n```markdown\n## fake heading\n```\ntail\n' > "$td/fenced.md"
  # fixture 4: tilde fence wrapping backtick fences is ONE block
  printf -- '## real\n~~~markdown\n```bash\ninner\n```\n## fake\n~~~\n' > "$td/tilde.md"
  # fixture 5: leaf semantics — H2 body stops at the H3
  { printf -- '## parent\n'; printf 'p%.0s' $(seq 1 800); printf '\n### child\n'; \
    printf 'c%.0s' $(seq 1 800); printf '\n'; } > "$td/leaf.md"
  # fixture 6: frontmatter only, no headings
  printf -- '---\nname: a\ndescription: b\n---\npreamble only\n' > "$td/plain.md"

  lint "$td/ok.md" "$td/plain.md" >/dev/null \
    || { echo "section-lint self-test: FAIL (ok/plain fixtures flagged)" >&2; exit 2; }
  lint "$td/over.md" >/dev/null \
    && { echo "section-lint self-test: FAIL (over fixture passed)" >&2; exit 2; }
  lint "$td/fenced.md" | grep -q '1 sections' \
    || { echo "section-lint self-test: FAIL (fenced heading started a section)" >&2; exit 2; }
  lint "$td/tilde.md" | grep -q '1 sections' \
    || { echo "section-lint self-test: FAIL (nested fence mis-toggled)" >&2; exit 2; }
  lint "$td/leaf.md" | grep -q '2 sections' \
    || { echo "section-lint self-test: FAIL (leaf split not applied)" >&2; exit 2; }
  echo "section-lint self-test: ALL PASS"
}
