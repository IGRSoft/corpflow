#!/usr/bin/env bash
# @description capability-registry.sh — emit every command, agent and skill this plugin
#   ships, one line each, as `path — description`.
#
#   Exists because search cannot close the gap it is aimed at. 9 of the 16 standing
#   `buried` failures are requests for a capability the repo ALREADY ships, missed because
#   the request states a need in user words while the registry states a domain in ours, with
#   no term in common. Keyword search bridged 4 of 9 such cases; a model reading the list
#   bridges more, because the gap is semantic rather than lexical.
#
#   No worked example is given here on purpose: this file is inside the tree the model
#   searches, so a prompt printed beside its answer converts that eval case into a lookup.
#
#   The whole inventory is ~79 lines / ~2.8k tokens, so this REPLACES a search rather
#   than seeding one: enumeration is complete by construction, which is the point. A
#   search needs a stop condition the searcher cannot evaluate; a bounded list does not.
#
#   Frontmatter `description:` only — never body text. A description that does not say
#   what the capability is for is the bug to fix at the source, not to paper over here.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

emit() {
  local file="$1" desc
  # Frontmatter only: stop at the next key or the closing fence, so a multi-line
  # description folds but a body heading never leaks in.
  desc=$(awk '
    /^description:[[:space:]]*/ { sub(/^description:[[:space:]]*/, ""); buf=$0; inside=1; next }
    inside && /^[a-z_-]+:/     { exit }
    inside && /^---/           { exit }
    inside                     { buf = buf " " $0 }
    END                        { print buf }
  ' "$file")
  desc=$(printf '%s' "$desc" | tr -s '[:space:]' ' ' | sed "s/^['\"]//; s/['\"]$//; s/[[:space:]]*$//")
  [ -n "$desc" ] && printf '%s — %s\n' "$file" "$desc"
}

for f in commands/*.md agents/*.md skills/*/SKILL.md; do
  [ -f "$f" ] && emit "$f"
done
