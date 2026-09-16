#!/usr/bin/env bash
# cache-lint.sh — preamble byte-stability lint for the handoff-protocol cache prefix.
#
# Modes:
#
#   1. Prefix lint (default):
#        cache-lint.sh <prompt-log.jsonl>
#      Reads a prompt-log.jsonl (one prompt per line, schema:
#        {"worktask_id": "...", "stage": "...", "prompt": "..."}
#      where `prompt` contains the marker tags named in
#      handoff-protocol.md#cache-prefix as section delimiters:
#      <<<contract-reminder>>>, <<<worktask-header>>>, <<<state-json>>>,
#      <<<stage-contract>>>, <<<model-discipline>>>, <<<task-description>>>,
#      <<<retry-hints>>>, <<<stage-banners>>>.
#      Asserts byte-identity of sections [1] contract-reminder + [2]
#      worktask-header across ALL stages of the same worktask_id, and
#      byte-identity of sections [4] stage-contract + [4b] model-discipline
#      across all calls of the same (worktask_id, stage) pair. Exits 1 on drift.
#
#      An optional `model` field on a log line turns on the canon check:
#      section [4b] must equal, byte for byte, the block
#      skills/shared/model-prompting.md carries for that alias. Byte-identity
#      alone cannot see a stage that consistently carries the WRONG model's
#      block, which is the routing miss this check exists for.
#
#      N (number of lines compared) is computed from the FIRST stage's
#      sections [1]+[2]+[4] line count — derived dynamically, NOT a magic
#      number. Robust to spec changes.
#
#   2. Anchor lint:
#        cache-lint.sh --anchor-lint <artifact.md>
#      Verifies the artifact's H2 headings match the per-stage allow-list
#      from skills/worktask/references/handoff-protocol.md#anchor-allow-list.
#      Stage is read from the artifact's `handoff:` frontmatter block (yq when
#      it parses it; awk subset fallback when yq is absent OR errors).
#      Exits 1 on missing/extra anchors.
#
#   3. Frontmatter template lint:
#        cache-lint.sh --frontmatter-template-lint <agent.md> [<agent.md> ...]
#      For each stage agent, asserts:
#        - The `## Handoff Protocol` section exists.
#        - Inside it, there is exactly one fenced ```yaml block.
#        - That block contains a `handoff:` mapping with a `stage:` value.
#        - The `stage:` value matches the canonical agent→stage mapping.
#        - The block is ≤30 lines (per handoff-protocol.md#frontmatter-schema).
#      Drift-detection guard: catches "someone re-inlined boilerplate" or
#      changed the per-stage frontmatter template inconsistently between
#      agents and `skills/shared/stage-contracts.md § Per-Stage Frontmatter
#      Templates`. Exits 1 on any failure; lists every offending agent.
#
#   4. Filename lint:
#        cache-lint.sh --filename-lint <context-dir>
#      Scans all stage artifacts in the given .context/ directory and asserts
#      each filename matches the canonical #stage-artifact-map from
#      handoff-protocol.md. Stage is inferred from handoff: frontmatter.
#      Flags non-canonical names (e.g. arch-0.md instead of
#      architecture-0.md). Exits 1 on any violation.
#
#   5. Agent-section cross-check:
#        cache-lint.sh --agent-section-lint [<repo-root>]
#      For every stage, resolves that stage's agent file and asserts each `## X`
#      section its prose instructs it to write into the stage artifact is already
#      accepted by this lint (stage allow-list row, UNIVERSAL_ANCHORS, or
#      OPTIONAL_ANCHOR_RE). Catches contradiction shape (iv): an agent mandating a
#      heading anchor_lint rejects, which no artifact can satisfy. Names both files.
#      Extraction under-matches by design — see agent_mandated_sections.
#      Exits 1 on any unaccepted mandate.
#
#   6. Self-test:
#        cache-lint.sh --self-test   (alias: --selftest)
#      Runs all modes against built-in fixtures (tempdir). Exits 0 on pass.
#
# Reference: skills/worktask/references/handoff-protocol.md#cache-prefix
#            skills/shared/stage-contracts.md#per-stage-frontmatter-templates

set -euo pipefail

usage() {
  sed -n 's/^# \{0,1\}//p' "$0" | sed -n '1,/^$/p'
  exit 2
}

[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { usage; }

# ---------- Anchor allow-list (mirrors handoff-protocol.md#anchor-allow-list) ----------
# POSIX-compatible lookup (bash 3.2 has no associative arrays).
# One row per stage: <code> <agent-basename> <canonical-artifact-basename> <anchors…>.
#
# One row, not four parallel case tables: a new stage otherwise stayed half-added and nothing
# could report which table was missed. Anchors mirror handoff-protocol.md#anchor-allow-list,
# basenames its #stage-artifact-map, agents stage-contracts.md § Per-Stage Frontmatter
# Templates; UNIVERSAL_ANCHORS and OPTIONAL_ANCHOR_RE add the stage-independent obligations.
_STAGE_TABLE='PL product-manager planning requirements acceptance-criteria scope out-of-scope risks complexity stages summary
AR software-architector architecture decisions trade-offs patterns integration-points schemas open-questions risks
TL team-lead coordination fan-out shared-snippets sequence risks
DV developer development files-changed tests-added deviations follow-ups
DR technical-lead developer-review findings verdict blockers follow-ups
SR security-reviewer security-review findings verdict blockers threat-model
QA qa-engineer testing results coverage regressions verdict
DC technical-writer documentation files-changed cross-references follow-ups
RE release-engineer release artifacts version rollback-plan
FN project-manager complete-summary summary artifacts followups metrics
ST stakeholder retrospective decision learnings followups
IR incident-responder incident root-cause fix-plan blast-radius
ET ethics-reviewer ethics-review findings verdict mitigations'

# Out-parameter of _stage_row, holding the matched row minus its stage code. Not a return
# value: a command substitution would fork once per lookup per artifact.
_STAGE_ROW=""

# _stage_row <stage> — rc 1 with _STAGE_ROW empty when the stage is unknown.
_stage_row() {
  local row
  _STAGE_ROW=""
  [ -n "${1:-}" ] || return 1
  while IFS= read -r row; do
    case "$row" in
      "$1 "*) _STAGE_ROW="${row#* }"; return 0 ;;
    esac
  done <<< "$_STAGE_TABLE"
  return 1
}

# The anchors an artifact of <stage> must carry, space-separated. Empty for an unknown
# stage, which every caller reads as "not a stage artifact".
anchors_for_stage() {
  _stage_row "$1" || { echo ""; return 0; }
  # shellcheck disable=SC2086  # deliberate word split: the row is space-separated
  set -- $_STAGE_ROW
  shift 2
  echo "$*"
}

# The agent basename that owns <stage> — DV -> developer.
stage_to_agent_basename() {
  _stage_row "$1" || { echo ""; return 0; }
  # shellcheck disable=SC2086  # deliberate word split
  set -- $_STAGE_ROW
  echo "$1"
}

# The canonical artifact basename for <stage> — DV -> development. Pinned against six other
# spellings of the same map by artifact-map-parity.bats.
canonical_basename_for_stage() {
  _stage_row "$1" || { echo ""; return 0; }
  # shellcheck disable=SC2086  # deliberate word split
  set -- $_STAGE_ROW
  echo "$2"
}

# The inverse of stage_to_agent_basename, read off the same rows rather than out of a
# second table that could disagree with it.
agent_basename_to_stage() {
  local row key="${1:-}"
  [ -n "$key" ] || { echo ""; return 0; }
  while IFS= read -r row; do
    # shellcheck disable=SC2086  # deliberate word split
    set -- $row
    if [ "$2" = "$key" ]; then echo "$1"; return 0; fi
  done <<< "$_STAGE_TABLE"
  echo ""
}

# Anchors REQUIRED in every stage artifact, on top of that stage's own row. Stage-independent
# obligations live here rather than in thirteen copies of anchors_for_stage:
#   elicitation-sweep  the closing sweep's artifact-body transport — the full items or the
#                      explicit empty statement. Mandatory for all 13 stages, no grace.
UNIVERSAL_ANCHORS='elicitation-sweep'

# Anchors ALLOWED in any stage artifact but required in none, so neither retroactively
# fails an older artifact nor is reported as unexpected in a newer one:
#   rework-<N>         the scope-addition re-entry section agents/technical-lead.md reads
#                      at the DR gate — a shipped convention this lint used to reject.
#   re-review          the DR second-pass section, same class as rework-<N>: a review that
#                      re-runs after rework records it here rather than rewriting its verdict.
#   design-preview     PL's Figma capture block, written only when a Figma URL is present.
#   test-strategy      PL's test-strategy section; pl0-procedure.md never mandates it.
#   <Platform> App Architecture, Test Architecture
#                      the two H2s agents/software-architector.md mandates in every AR artifact,
#                      the first named for the detected platform. Title-case by that agent's own
#                      template, so they are matched literally rather than as kebab anchors.
#   Blockers, DV Completion Checklist, Incident Report, Release Preparation Summary,
#   Self-Improvement    the same class as the two above: an H2 its stage agent's prose MANDATES
#                      into the stage artifact while anchors_for_stage never listed it. Each is
#                      ACCEPTED, never required, so no existing artifact retroactively fails —
#                      agent_section_lint below is what stops the next one from being added
#                      silently.
OPTIONAL_ANCHOR_RE='^(rework-[0-9]+|re-review|design-preview|test-strategy|[A-Za-z][A-Za-z0-9+ -]* App Architecture|Test Architecture|Blockers|DV Completion Checklist|Incident Report|Release Preparation Summary|Self-Improvement)$'

# ---------- Frontmatter stage extractor ----------
# The frontmatter block alone (between the first two `---` lines), empty if absent.
# Everything downstream parses THIS, never the whole file: an artifact body is markdown,
# and a table cell or a `**Bold**:` line makes a whole-file YAML parse abort on a document
# whose frontmatter is perfectly well-formed.
frontmatter_block() {
  awk '/^---$/{c++; if (c==1) next; if (c==2) exit} c==1' "$1"
}

# The awk subset parser — the fallback whenever yq cannot answer. Reads a `stage:` line
# out of an already-isolated frontmatter block.
_stage_via_awk() {
  awk '
    /^[[:space:]]*stage:[[:space:]]*/ {
      sub(/^[[:space:]]*stage:[[:space:]]*/, "")
      gsub(/[[:space:]"]+/, "")
      print
      exit
    }'
}

# Prints stage code on stdout; empty if genuinely absent.
#
# Two failure modes that look identical from the outside must NOT be conflated:
#   - yq ran and reported no stage  -> a REAL absence; report it, do not paper over it
#     with a second parser that might disagree.
#   - yq errored (or is missing)    -> NO answer; fall back to awk.
# Treating the second as the first is how this lint failed OPEN: --anchor-lint reported
# "no stage in handoff frontmatter" for artifacts that carry one, and every anchor of
# every such artifact went unchecked on any host where yq is installed.
extract_stage() {
  local fm out
  fm=$(frontmatter_block "$1")
  [ -n "$fm" ] || return 0
  if command -v yq >/dev/null 2>&1; then
    if out=$(printf '%s\n' "$fm" | yq eval '.handoff.stage // ""' - 2>/dev/null); then
      [ "$out" = "null" ] && out=""
      printf '%s\n' "$out"
      return 0
    fi
  fi
  printf '%s\n' "$fm" | _stage_via_awk
}

# ---------- Anchor lint ----------
anchor_lint() {
  local artifact="$1"
  [[ -f "$artifact" ]] || { echo "anchor-lint: file not found: $artifact" >&2; exit 2; }

  local stage
  stage=$(extract_stage "$artifact")
  if [[ -z "$stage" ]]; then
    echo "anchor-lint: $artifact: no stage in handoff frontmatter (possibly path F3 — frontmatter missing)" >&2
    exit 1
  fi

  local expected
  expected=$(anchors_for_stage "$stage")
  if [[ -z "$expected" ]]; then
    echo "anchor-lint: $artifact: unknown stage '$stage' (no anchor allow-list)" >&2
    exit 1
  fi
  # Appended AFTER the unknown-stage check so an unrecognised stage still reports as such
  # rather than as a missing sweep heading. Both the missing loop and the `comm` below read
  # $expected, so one append makes the anchor required and accepted in a single stroke.
  expected="$expected $UNIVERSAL_ANCHORS"

  # Extract H2 headings (skip H2 inside fenced code blocks).
  local found
  found=$(awk '
    BEGIN { in_fence = 0 }
    /^```/ { in_fence = !in_fence; next }
    !in_fence && /^## / {
      sub(/^## +/, "")
      sub(/[[:space:]]+$/, "")
      print
    }
  ' "$artifact" | sort -u)

  local missing=()
  local exp
  for exp in $expected; do
    if ! grep -qx -- "$exp" <<< "$found"; then
      missing+=("$exp")
    fi
  done

  local extras
  extras=$(comm -23 <(echo "$found" | grep -Ev "$OPTIONAL_ANCHOR_RE" || true) \
                    <(printf '%s\n' $expected | sort -u))

  if [[ ${#missing[@]} -gt 0 || -n "$extras" ]]; then
    echo "anchor-lint: $artifact (stage=$stage) FAIL" >&2
    [[ ${#missing[@]} -gt 0 ]] && echo "  missing: ${missing[*]}" >&2
    [[ -n "$extras" ]] && echo "  unexpected: $(echo "$extras" | tr '\n' ' ')" >&2
    exit 1
  fi

  echo "anchor-lint: $artifact (stage=$stage) ok"
}

# ---------- Agent-section cross-check (#16 letter b) ----------
# The H2 names an agent's prose INSTRUCTS it to write into its own stage artifact.
#
# Deliberately under-matching: a false negative leaves today's behaviour, while a
# false positive would block correct work by rejecting a section no agent ever mandated.
# Three filters, all conservative:
#   1. The name must sit in its own code span opening with `## ` — `development-N.md ## decisions`
#      is one span starting with a filename and is not a mandate this check can read.
#   2. The SAME line must name a stage-artifact file (`<name>-N.md`, `-0.md`, `release-*.md`).
#      That is what separates "write this into your artifact" from a cross-reference to another
#      document's heading, and it is why `.context/errors/developer.md` — no run-index segment —
#      never reaches the check.
#   3. A placement word must be ADJACENT to the span — introducing it (`under \x60## X\x60`) or
#      following it (`\x60## X\x60 section`). Same-line proximity is not enough: developer.md
#      L475 cites `## decisions` in prose on a line that separately names `development-N.md`,
#      and security-reviewer.md L65 reaches "read as \x60git diff\x60" and "\x60## anchor\x60" on
#      one line ending in `security-review-N.md`. Adjacency rejects both; a loose same-line
#      word test accepted both.
#   4. Placeholder names are dropped: anything holding `<`, `[`, or a bare trailing ` N`/`-N`
#      segment cannot be compared literally against an allow-list entry.
agent_mandated_sections() {
  local agent="$1"
  grep -E '`## ' "$agent" 2>/dev/null \
    | grep -E '[a-z][a-z-]*-(N|\*|[0-9]+)\.md' \
    | grep -E '(under|over|as|into|H2)[[:space:]]+`##[[:space:]]|`##[[:space:]][^`]+`[[:space:]]+(sections?|H2|headings?)' \
    | grep -oE '`## [^`]+`' \
    | sed -e 's/^`## //' -e 's/`$//' -e 's/[[:space:]]*$//' \
    | grep -vE '[<>[]' \
    | grep -vE '(^|[ -])N$' \
    | sort -u
}

# For each stage: every section its agent mandates must already be accepted by the lint
# (stage row ∪ UNIVERSAL_ANCHORS ∪ OPTIONAL_ANCHOR_RE). The failure this catches is
# contradiction shape (iv) — an agent told to write an H2 that anchor_lint then rejects,
# which no artifact author can satisfy. Both files are named because the fix is a choice
# between them, not a mechanical edit to one.
agent_section_lint() {
  local root="${1:-.}" rc=0 checked=0
  local stage agent_base agent expected sect
  for stage in PL AR TL DV DR SR QA DC RE FN ST IR ET; do
    agent_base=$(stage_to_agent_basename "$stage")
    agent="$root/agents/$agent_base.md"
    [[ -f "$agent" ]] || continue
    checked=$((checked + 1))
    expected="$(anchors_for_stage "$stage") $UNIVERSAL_ANCHORS"
    while IFS= read -r sect; do
      [[ -n "$sect" ]] || continue
      if grep -qE "$OPTIONAL_ANCHOR_RE" <<< "$sect"; then continue; fi
      if grep -qx -- "$sect" <<< "$(printf '%s\n' $expected)"; then continue; fi
      echo "agent-section-lint: FAIL stage=$stage" >&2
      echo "  agents/$agent_base.md mandates '## $sect' into its artifact" >&2
      echo "  skills/worktask/scripts/cache-lint.sh accepts neither anchors_for_stage $stage" \
        "nor UNIVERSAL_ANCHORS nor OPTIONAL_ANCHOR_RE" >&2
      rc=1
    done <<< "$(agent_mandated_sections "$agent")"
  done

  if [[ $checked -eq 0 ]]; then
    echo "agent-section-lint: no stage agents found under $root/agents/" >&2
    return 1
  fi
  [[ $rc -eq 0 ]] && echo "agent-section-lint: $checked stage agents checked, all mandated sections accepted"
  return $rc
}

# ---------- Prefix lint ----------
extract_section() {
  # extract_section <prompt-text> <marker> → section body between
  # <<<marker>>> and the next <<<...>>> tag (or EOF).
  local body="$1" marker="$2"
  awk -v m="$marker" '
    $0 == "<<<" m ">>>" { capture = 1; next }
    /^<<<.*>>>$/ && capture { exit }
    capture { print }
  ' <<< "$body"
}

# Resolves the plugin root: $CLAUDE_PLUGIN_ROOT when set, else three levels up
# from this script (skills/worktask/scripts/ -> root). Full ladder:
# skills/shared/plugin-root-resolution.md.
plugin_root() {
  if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" && -f "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" ]]; then
    printf '%s' "$CLAUDE_PLUGIN_ROOT"
    return 0
  fi
  local d
  d=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
  printf '%s' "$d"
}

# canonical_model_block <alias> <root> -> the fenced `text` block under that
# alias's H2 in model-prompting.md, or empty when the alias has none (haiku).
# The heading match tolerates both `## haiku` and `## opus — Claude Opus 5`,
# because the em-dash suffix is prose and is not part of the key.
canonical_model_block() {
  local alias="$1" root="$2" canon="$2/skills/shared/model-prompting.md"
  [[ -f "$canon" ]] || { echo "prefix-lint: canon not found: $canon" >&2; return 2; }
  awk -v a="$alias" '
    $0 ~ "^## " a "($| )" { inalias = 1; next }
    /^## / { inalias = 0 }
    inalias && $0 == "```text" { infence = 1; next }
    infence && $0 == "```" { exit }
    infence { print }
  ' "$canon"
}

# ---------- Forbidden-token scanner ----------
# Scans ONE section's text for the seven forbidden-token classes named in
# handoff-protocol.md#cache-prefix (mirrored verbatim in
# coordination-0.md#shared-snippets so no second taxonomy is ever invented):
#   timestamp / ENV expansion / UUID / $RANDOM / retry-counter / mtime /
#   agent-specific-name-beyond-worktask_id.
# These are INTRINSIC per-section checks (unlike the byte-identity check
# above, which only catches drift ACROSS lines) — a token that is identical
# on every line (e.g. the same ISO timestamp baked in at generation time)
# would pass byte-identity yet still be a latent miss on the NEXT worktask,
# because a fresh worktask_id at a fresh instant produces a NEW timestamp,
# breaking the cross-worktask cache-prefix reuse this scanner exists to
# protect. Prints one line per hit to stderr; returns non-zero on any hit.
forbidden_token_scan() {
  local section_text="$1" label="$2"
  local rc=0

  # Six `grep` forks per section used to run here, three sections per log line —
  # eighteen of the ~29 forks this lint spent on every line. The shell's own
  # regex engine answers the same questions with none. The three classes that
  # were `grep -i` (3, 5, 6) spell their case-folding inline rather than via
  # `nocasematch`: that shopt is function-wide, and it silently turned the
  # case-SENSITIVE classes 2 and 4 into matches on `$user` / `$random`.

  # 1. ISO-8601 timestamp (date/now render), e.g. 2026-07-05T15:15:39Z
  if [[ "$section_text" =~ [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2} ]]; then
    echo "forbidden-token-lint: $label: ISO-8601 timestamp found" >&2
    rc=1
  fi

  # 2. ENV expansions that vary per call (unresolved $VAR / ${VAR} literals,
  #    or a shell already substituted a per-user path under one of these).
  if [[ "$section_text" =~ \$(HOSTNAME|USER|PWD|RANDOM)([^A-Za-z0-9_]|$) \
     || "$section_text" =~ \$\{(HOSTNAME|USER|PWD|RANDOM)\} ]]; then
    # Single-quoted: this message names the four variables, and double quotes
    # made it print the running shell's own $USER and $PWD into a lint report
    # about leaked per-call values.
    echo "forbidden-token-lint: $label:"' ENV expansion ($HOSTNAME/$USER/$PWD/$RANDOM) found' >&2
    rc=1
  fi

  # 3. Random / request IDs — UUID v4 shape.
  if [[ "$section_text" =~ [0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12} ]]; then
    echo "forbidden-token-lint: $label: UUID found" >&2
    rc=1
  fi

  # 4. $RANDOM literal (bash builtin) appearing unresolved in the text.
  if [[ "$section_text" =~ \$RANDOM([^A-Za-z0-9_]|$) ]]; then
    echo "forbidden-token-lint: $label: literal \$RANDOM found" >&2
    rc=1
  fi

  # 5. Retry counters (belong in section [6], never [1]/[2]/[4]).
  if [[ "$section_text" =~ [Rr][Ee][Tt][Rr][Yy][_-]?[Cc][Oo][Uu][Nn][Tt][[:space:]]*[:=][[:space:]]*[0-9]+ \
     || "$section_text" =~ [Aa][Tt][Tt][Ee][Mm][Pp][Tt][[:space:]]*#?[0-9]+ ]]; then
    echo "forbidden-token-lint: $label: retry/attempt counter found (belongs in section [6])" >&2
    rc=1
  fi

  # 6. File mtime-shaped values (epoch seconds/millis label or "mtime:").
  if [[ "$section_text" =~ [Mm][Tt][Ii][Mm][Ee][[:space:]]*[:=][[:space:]]*[0-9]{9,13}([^0-9]|$) ]]; then
    echo "forbidden-token-lint: $label: file mtime found" >&2
    rc=1
  fi

  # 7. Agent-specific names beyond worktask_id (the per-stage agent identity
  #    belongs in section [4] ONLY, never baked into [1]/[2]). Checked by the
  #    caller passing the stage's OWN agent name as a second forbidden literal
  #    when scanning [1]/[2] (see prefix_lint call site) — a name appearing in
  #    its OWN [4] is expected and not scanned here.

  return $rc
}

prefix_lint() {
  local log="$1"
  [[ -f "$log" ]] || { echo "prefix-lint: log not found: $log" >&2; exit 2; }
  command -v jq >/dev/null 2>&1 || { echo "prefix-lint: jq required" >&2; exit 2; }

  # POSIX-compatible state: store per-key sections as files in a tempdir.
  # bash 3.2 has no associative arrays, so we use the filesystem.
  local td
  td=$(mktemp -d -t cache-lint-prefix-XXXXXX)
  trap "rm -rf '$td'" RETURN

  local rc=0
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    # One jq per line, not three: the fields come out in a fixed order, and the
    # prompt — the only multi-line one — is whatever follows the first two lines.
    # The `X` sentinel keeps command substitution from eating the separator that
    # an EMPTY prompt is reduced to, which would shift `stage` into `prompt`.
    local fields wid stage model prompt
    fields=$(jq -r '.worktask_id, .stage, (.model // ""), .prompt' <<< "$line"; printf 'X')
    fields="${fields%X}"
    wid="${fields%%$'\n'*}"; fields="${fields#*$'\n'}"
    stage="${fields%%$'\n'*}"; fields="${fields#*$'\n'}"
    model="${fields%%$'\n'*}"; prompt="${fields#*$'\n'}"
    # Three separate substitutions stripped every trailing newline from each
    # field; keep that, so a prompt is compared the same way it always was.
    while [ "${prompt%$'\n'}" != "$prompt" ]; do prompt="${prompt%$'\n'}"; done

    local s1 s2 s4 s4b
    s1=$(extract_section "$prompt" "contract-reminder")
    s2=$(extract_section "$prompt" "worktask-header")
    s4=$(extract_section "$prompt" "stage-contract")
    s4b=$(extract_section "$prompt" "model-discipline")

    # L1 forbidden-token scan — runs on EVERY line (intrinsic per-section
    # check, independent of the cross-line byte-identity comparison below).
    if ! forbidden_token_scan "$s1" "worktask_id=$wid stage=$stage section[1]"; then
      rc=1
    fi
    if ! forbidden_token_scan "$s2" "worktask_id=$wid stage=$stage section[2]"; then
      rc=1
    fi
    if ! forbidden_token_scan "$s4" "worktask_id=$wid stage=$stage section[4]"; then
      rc=1
    fi
    if ! forbidden_token_scan "$s4b" "worktask_id=$wid stage=$stage section[4b]"; then
      rc=1
    fi

    # Canon check. Opt-in on the log line carrying `model`, because the field is
    # new and a log written before it existed must stay lintable rather than
    # fail as if the block were wrong.
    if [[ -n "$model" ]]; then
      local canon
      if canon=$(canonical_model_block "$model" "$(plugin_root)"); then
        while [ "${canon%$'\n'}" != "$canon" ]; do canon="${canon%$'\n'}"; done
        if [[ "$s4b" != "$canon" ]]; then
          echo "prefix-lint: worktask_id=$wid stage=$stage: section [4b] does not match model-prompting.md block for model=$model" >&2
          rc=1
        fi
      else
        rc=1
      fi
    fi

    # Sanitize wid/stage for use in filenames (allow [a-zA-Z0-9._-]). Pattern
    # substitution rather than `tr`, which cost two forks on every line.
    local widsafe="${wid//[!a-zA-Z0-9._-]/_}" stagesafe="${stage//[!a-zA-Z0-9._-]/_}"

    local f1="$td/wf-${widsafe}-s1"
    local f2="$td/wf-${widsafe}-s2"
    local f4="$td/wf-${widsafe}-stage-${stagesafe}-s4"
    local f4b="$td/wf-${widsafe}-stage-${stagesafe}-s4b"

    if [[ ! -f "$f1" ]]; then
      printf '%s' "$s1" > "$f1"
      printf '%s' "$s2" > "$f2"
    else
      if [[ "$s1" != "$(<"$f1")" ]]; then
        echo "prefix-lint: worktask_id=$wid stage=$stage: section [1] contract-reminder DRIFT" >&2
        rc=1
      fi
      if [[ "$s2" != "$(<"$f2")" ]]; then
        echo "prefix-lint: worktask_id=$wid stage=$stage: section [2] worktask-header DRIFT" >&2
        rc=1
      fi
    fi

    if [[ ! -f "$f4" ]]; then
      printf '%s' "$s4" > "$f4"
    elif [[ "$s4" != "$(<"$f4")" ]]; then
      echo "prefix-lint: worktask_id=$wid stage=$stage: section [4] stage-contract DRIFT" >&2
      rc=1
    fi

    if [[ ! -f "$f4b" ]]; then
      printf '%s' "$s4b" > "$f4b"
    elif [[ "$s4b" != "$(<"$f4b")" ]]; then
      echo "prefix-lint: worktask_id=$wid stage=$stage: section [4b] model-discipline DRIFT" >&2
      rc=1
    fi
  done < "$log"

  if [[ $rc -eq 0 ]]; then
    local nlines
    nlines=$(wc -l < "$log" | tr -d ' ')
    echo "prefix-lint: $nlines prompts checked, no drift; forbidden-token scan clean"
  fi
  return $rc
}

# ---------- Frontmatter template lint ----------
# Extract the contents of the first ```yaml fenced block that appears
# AFTER the `## Handoff Protocol` H2 and BEFORE the next H2 heading.
# Returns the YAML body (without the fence markers). Empty if not found.
extract_handoff_yaml_block() {
  local f="$1"
  awk '
    BEGIN { in_section = 0; in_fence = 0; emit = 0 }
    /^## Handoff Protocol[[:space:]]*$/ { in_section = 1; next }
    in_section && /^## / { exit }
    in_section && /^```yaml[[:space:]]*$/ && !in_fence {
      in_fence = 1; emit = 1; next
    }
    in_section && /^```[[:space:]]*$/ && in_fence {
      in_fence = 0; exit
    }
    in_fence && emit { print }
  ' "$f"
}

# Count the number of ```yaml ... ``` fenced blocks inside Handoff Protocol.
count_handoff_yaml_blocks() {
  local f="$1"
  awk '
    BEGIN { in_section = 0; in_fence = 0; n = 0 }
    /^## Handoff Protocol[[:space:]]*$/ { in_section = 1; next }
    in_section && /^## / { print n; exit_done = 1; exit }
    in_section && /^```yaml[[:space:]]*$/ && !in_fence {
      in_fence = 1; n++; next
    }
    in_section && /^```[[:space:]]*$/ && in_fence { in_fence = 0; next }
    END { if (!exit_done) print n }
  ' "$f"
}

# Extract the Handoff Protocol section body (between the H2 and the next H2 /
# EOF) — used by the pointer-only acceptance path (P1 dedup, Batch 5) to check
# for a `stage-contracts.md#tpl-<CODE>` reference when no inline yaml block
# remains.
extract_handoff_section_body() {
  local f="$1"
  awk '
    /^## Handoff Protocol[[:space:]]*$/ { in_section = 1; next }
    in_section && /^## / { exit }
    in_section { print }
  ' "$f"
}

frontmatter_template_lint() {
  local rc=0 agent base stage_expected nblocks body stage_actual nlines section_body
  for agent in "$@"; do
    [[ -f "$agent" ]] || { echo "frontmatter-template-lint: file not found: $agent" >&2; rc=1; continue; }

    base=$(basename "$agent" .md)
    stage_expected=$(agent_basename_to_stage "$base")
    if [[ -z "$stage_expected" ]]; then
      echo "frontmatter-template-lint: $agent: not a stage agent (no canonical mapping) — skipping" >&2
      continue
    fi

    if ! grep -q '^## Handoff Protocol[[:space:]]*$' "$agent"; then
      echo "frontmatter-template-lint: $agent FAIL: missing '## Handoff Protocol' section" >&2
      rc=1; continue
    fi

    nblocks=$(count_handoff_yaml_blocks "$agent")

    # Pointer-only acceptance path (P1 dedup, Batch 5/ad4): an agent MAY carry
    # ZERO inline yaml blocks if its Handoff Protocol section instead cites the
    # canonical SSOT template `stage-contracts.md#tpl-<stage_expected>`
    # verbatim — this is the collapsed form the boilerplate-dedup pass
    # produces (deletes the byte-duplicated YAML, keeps a one-line pointer).
    # `developer.md` deliberately keeps its INLINE block (carries a load-
    # bearing `worktree:` field beyond the SSOT template) — nblocks==1 there
    # still takes the classic path below, unaffected by this branch.
    if [[ "$nblocks" == "0" ]]; then
      section_body=$(extract_handoff_section_body "$agent")
      # bash 3.2 has no ${var,,} — lowercase via tr for the anchor slug.
      local stage_lc
      stage_lc=$(printf '%s' "$stage_expected" | tr '[:upper:]' '[:lower:]')
      if grep -qE "stage-contracts\.md#tpl-${stage_lc}\b" <<< "$section_body"; then
        echo "frontmatter-template-lint: $agent (stage=$stage_expected, pointer-only) ok"
        continue
      fi
      echo "frontmatter-template-lint: $agent FAIL: no inline yaml block AND no stage-contracts.md#tpl-$stage_expected pointer found in Handoff Protocol" >&2
      rc=1; continue
    fi

    if [[ "$nblocks" != "1" ]]; then
      echo "frontmatter-template-lint: $agent FAIL: expected exactly 1 fenced yaml block inside Handoff Protocol, found $nblocks" >&2
      rc=1; continue
    fi

    body=$(extract_handoff_yaml_block "$agent")
    if ! grep -q '^handoff:' <<< "$body"; then
      echo "frontmatter-template-lint: $agent FAIL: yaml block has no top-level 'handoff:' key" >&2
      rc=1; continue
    fi

    # Extract stage value (allow optional quotes / trailing comment).
    stage_actual=$(awk '
      /^[[:space:]]*stage:[[:space:]]*/ {
        sub(/^[[:space:]]*stage:[[:space:]]*/, "")
        sub(/[[:space:]]*#.*$/, "")
        gsub(/[[:space:]"]+/, "")
        print; exit
      }
    ' <<< "$body")
    if [[ -z "$stage_actual" ]]; then
      echo "frontmatter-template-lint: $agent FAIL: yaml block has no 'stage:' value" >&2
      rc=1; continue
    fi
    if [[ "$stage_actual" != "$stage_expected" ]]; then
      echo "frontmatter-template-lint: $agent FAIL: stage='$stage_actual' but agent maps to '$stage_expected'" >&2
      rc=1; continue
    fi

    nlines=$(printf '%s\n' "$body" | wc -l | tr -d ' ')
    if (( nlines > 30 )); then
      echo "frontmatter-template-lint: $agent FAIL: yaml block has $nlines lines (limit 30 per handoff-protocol.md#frontmatter-schema)" >&2
      rc=1; continue
    fi

    echo "frontmatter-template-lint: $agent (stage=$stage_actual, $nlines lines) ok"
  done
  return $rc
}

# ---------- Filename lint ----------
filename_lint() {
  local ctx_dir="$1"
  [[ -d "$ctx_dir" ]] || { echo "filename-lint: directory not found: $ctx_dir" >&2; exit 2; }

  local rc=0 count=0
  for artifact in "$ctx_dir"/*.md; do
    [[ -f "$artifact" ]] || continue

    local stage
    stage=$(extract_stage "$artifact")
    [[ -z "$stage" || "$stage" == "null" ]] && continue

    count=$((count + 1))
    local expected_base
    expected_base=$(canonical_basename_for_stage "$stage")
    [[ -z "$expected_base" ]] && continue

    local actual_name name_re expected_desc
    actual_name=$(basename "$artifact")
    name_re="^${expected_base}-[0-9]+\\.md\$"
    expected_desc="${expected_base}-N.md"
    # DV fans out onto ledger tasks, one per stream, each writing its own
    # development-N-<stream>.md handoff; a run with a single DV row may omit the
    # stream and write development-N.md (handoff-protocol.md § DV fan-out).
    if [[ "$expected_base" == "development" ]]; then
      name_re="^development-[0-9]+(-[a-z0-9]+(-[a-z0-9]+)*)?\\.md\$"
      expected_desc="development-N.md or development-N-<stream>.md"
    fi
    if ! printf '%s' "$actual_name" | grep -qE "$name_re"; then
      echo "filename-lint: $artifact (stage=$stage) FAIL: expected '${expected_desc}', got '$actual_name'" >&2
      rc=1
    fi
  done

  if [[ $count -eq 0 ]]; then
    echo "filename-lint: no artifacts with handoff frontmatter found in $ctx_dir" >&2
    return 1
  fi

  [[ $rc -eq 0 ]] && echo "filename-lint: $count artifacts checked, all canonical"
  return $rc
}

# ---------- main ----------
case "${1:-}" in
  --anchor-lint) shift; [[ $# -ge 1 ]] || usage; anchor_lint "$1" ;;
  --frontmatter-template-lint)
    shift; [[ $# -ge 1 ]] || usage
    frontmatter_template_lint "$@"; exit $?
    ;;
  --filename-lint)
    shift; [[ $# -ge 1 ]] || usage
    filename_lint "$1"; exit $?
    ;;
  --agent-section-lint)
    shift
    agent_section_lint "${1:-.}"; exit $?
    ;;
  # `--selftest` is accepted alongside `--self-test`: the unhyphenated spelling is what
  # coordination-0.md and the DV2->DV3 #16 contract name, and without the alias it falls
  # through to the prefix-lint arm and reports "log not found" — a green contract command
  # that ran no test at all.
  --self-test | --selftest)
    # Sourced HERE, not at the top: the harness is test code the lint path never
    # runs. `[ -r ]` first, not a bare `.`: sourcing a missing file with the `.`
    # builtin is a special-builtin error that exits the shell immediately,
    # bypassing an `if ! . …` guard entirely.
    SELFTEST_LIB_PATH="$(dirname "${BASH_SOURCE[0]}")/cache-lint-selftest.sh"
    if [ -r "$SELFTEST_LIB_PATH" ]; then
      # shellcheck source=cache-lint-selftest.sh
      # shellcheck disable=SC1090
      . "$SELFTEST_LIB_PATH"
    else
      printf >&2 'cache-lint: self-test harness unreachable at %s — plugin install broken\n' \
        "$SELFTEST_LIB_PATH"
      exit 2
    fi
    self_test
    ;;
  "") usage ;;
  *) prefix_lint "$1"; exit $? ;;
esac
