#!/usr/bin/env bash
# cache-lint.sh — preamble byte-stability lint for the handoff-protocol cache prefix.
#
# Modes:
#
#   1. Prefix lint (default):
#        cache-lint.sh <prompt-log.jsonl>
#      Reads a prompt-log.jsonl (one prompt per line, schema:
#        {"worktask_id": "...", "stage": "...", "prompt": "..."}
#      where `prompt` contains marker tags <<<contract-reminder>>>,
#      <<<worktask-header>>>, <<<stage-contract>>> as section delimiters).
#      Asserts byte-identity of sections [1] contract-reminder + [2]
#      worktask-header across ALL stages of the same worktask_id, and
#      byte-identity of section [4] stage-contract across all calls of
#      the same (worktask_id, stage) pair. Exits 1 on drift.
#
#      N (number of lines compared) is computed from the FIRST stage's
#      sections [1]+[2]+[4] line count — derived dynamically, NOT a magic
#      number. Robust to spec changes.
#
#   2. Anchor lint:
#        cache-lint.sh --anchor-lint <artifact.md>
#      Verifies the artifact's H2 headings match the per-stage allow-list
#      from skills/worktask/references/handoff-protocol.md#anchor-allow-list.
#      Stage is read from the artifact's `handoff:` frontmatter (yq if
#      available; awk subset fallback). Exits 1 on missing/extra anchors.
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
#   5. Self-test:
#        cache-lint.sh --self-test
#      Runs all modes against built-in fixtures (tempdir). Exits 0 on pass.
#
# Reference: skills/worktask/references/handoff-protocol.md#cache-prefix
#            skills/shared/stage-contracts.md#per-stage-frontmatter-templates
# AR decisions implemented: AD-4 (cache-prefix invariants), AD-5 (anchors).
# AC satisfied: AC-3 (anchor convention), AC-14 (cache stability).

set -euo pipefail

usage() {
  sed -n 's/^# \{0,1\}//p' "$0" | sed -n '1,/^$/p'
  exit 2
}

[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { usage; }

# ---------- Anchor allow-list (mirrors handoff-protocol.md#anchor-allow-list) ----------
# POSIX-compatible lookup (bash 3.2 has no associative arrays).
anchors_for_stage() {
  case "$1" in
    PL) echo "requirements acceptance-criteria scope out-of-scope risks complexity stages" ;;
    AR) echo "decisions trade-offs patterns integration-points schemas open-questions risks" ;;
    TL) echo "fan-out shared-snippets sequence risks" ;;
    DV) echo "files-changed tests-added deviations follow-ups" ;;
    DR) echo "findings verdict blockers follow-ups" ;;
    SR) echo "findings verdict blockers threat-model" ;;
    QA) echo "results coverage regressions verdict" ;;
    DC) echo "files-changed cross-references follow-ups" ;;
    RE) echo "artifacts version rollback-plan" ;;
    FN) echo "summary artifacts followups metrics" ;;
    ST) echo "decision learnings followups" ;;
    IR) echo "root-cause fix-plan blast-radius" ;;
    ET) echo "findings verdict mitigations" ;;
    *) echo "" ;;
  esac
}

# ---------- Frontmatter stage extractor ----------
# Prints stage code on stdout; empty if not found.
extract_stage() {
  local f="$1"
  if command -v yq >/dev/null 2>&1; then
    yq eval '.handoff.stage // ""' "$f" 2>/dev/null || true
  else
    awk '
      BEGIN { in_fm = 0; depth = 0 }
      /^---$/ { depth++; in_fm = (depth == 1); next }
      in_fm && /^[[:space:]]*stage:[[:space:]]*/ {
        sub(/^[[:space:]]*stage:[[:space:]]*/, "")
        gsub(/[[:space:]"]+/, "")
        print
        exit
      }
    ' "$f"
  fi
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
  extras=$(comm -23 <(echo "$found") <(printf '%s\n' $expected | sort -u))

  if [[ ${#missing[@]} -gt 0 || -n "$extras" ]]; then
    echo "anchor-lint: $artifact (stage=$stage) FAIL" >&2
    [[ ${#missing[@]} -gt 0 ]] && echo "  missing: ${missing[*]}" >&2
    [[ -n "$extras" ]] && echo "  unexpected: $(echo "$extras" | tr '\n' ' ')" >&2
    exit 1
  fi

  echo "anchor-lint: $artifact (stage=$stage) ok"
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

# ---------- Forbidden-token scanner (L1, REQ-3/AC-4) ----------
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

  # 1. ISO-8601 timestamp (date/now render), e.g. 2026-07-05T15:15:39Z
  if grep -qE '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}' <<< "$section_text"; then
    echo "forbidden-token-lint: $label: ISO-8601 timestamp found" >&2
    rc=1
  fi

  # 2. ENV expansions that vary per call (unresolved $VAR / ${VAR} literals,
  #    or a shell already substituted a per-user path under one of these).
  if grep -qE '\$(HOSTNAME|USER|PWD|RANDOM)\b|\$\{(HOSTNAME|USER|PWD|RANDOM)\}' <<< "$section_text"; then
    echo "forbidden-token-lint: $label: ENV expansion ($HOSTNAME/$USER/$PWD/$RANDOM) found" >&2
    rc=1
  fi

  # 3. Random / request IDs — UUID v4 shape.
  if grep -qiE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' <<< "$section_text"; then
    echo "forbidden-token-lint: $label: UUID found" >&2
    rc=1
  fi

  # 4. $RANDOM literal (bash builtin) appearing unresolved in the text.
  if grep -qE '\$RANDOM\b' <<< "$section_text"; then
    echo "forbidden-token-lint: $label: literal \$RANDOM found" >&2
    rc=1
  fi

  # 5. Retry counters (belong in section [6], never [1]/[2]/[4]).
  if grep -qiE 'retry[_-]?count[[:space:]]*[:=][[:space:]]*[0-9]+|attempt[[:space:]]*#?[0-9]+' <<< "$section_text"; then
    echo "forbidden-token-lint: $label: retry/attempt counter found (belongs in section [6])" >&2
    rc=1
  fi

  # 6. File mtime-shaped values (epoch seconds/millis label or "mtime:").
  if grep -qiE 'mtime[[:space:]]*[:=][[:space:]]*[0-9]{9,13}\b' <<< "$section_text"; then
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
    local wid stage prompt
    wid=$(jq -r '.worktask_id' <<< "$line")
    stage=$(jq -r '.stage' <<< "$line")
    prompt=$(jq -r '.prompt' <<< "$line")

    local s1 s2 s4
    s1=$(extract_section "$prompt" "contract-reminder")
    s2=$(extract_section "$prompt" "worktask-header")
    s4=$(extract_section "$prompt" "stage-contract")

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

    # Sanitize wid/stage for use in filenames (allow [a-zA-Z0-9._-]).
    local widsafe stagesafe
    widsafe=$(printf '%s' "$wid" | tr -c 'a-zA-Z0-9._-' '_')
    stagesafe=$(printf '%s' "$stage" | tr -c 'a-zA-Z0-9._-' '_')

    local f1="$td/wf-${widsafe}-s1"
    local f2="$td/wf-${widsafe}-s2"
    local f4="$td/wf-${widsafe}-stage-${stagesafe}-s4"

    if [[ ! -f "$f1" ]]; then
      printf '%s' "$s1" > "$f1"
      printf '%s' "$s2" > "$f2"
    else
      if [[ "$s1" != "$(cat "$f1")" ]]; then
        echo "prefix-lint: worktask_id=$wid stage=$stage: section [1] contract-reminder DRIFT" >&2
        rc=1
      fi
      if [[ "$s2" != "$(cat "$f2")" ]]; then
        echo "prefix-lint: worktask_id=$wid stage=$stage: section [2] worktask-header DRIFT" >&2
        rc=1
      fi
    fi

    if [[ ! -f "$f4" ]]; then
      printf '%s' "$s4" > "$f4"
    elif [[ "$s4" != "$(cat "$f4")" ]]; then
      echo "prefix-lint: worktask_id=$wid stage=$stage: section [4] stage-contract DRIFT" >&2
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
# Canonical agent-basename → stage code mapping. Mirrors the §
# Per-Stage Frontmatter Templates section in stage-contracts.md.
agent_basename_to_stage() {
  case "$1" in
    product-manager) echo PL ;;
    software-architector) echo AR ;;
    team-lead) echo TL ;;
    developer) echo DV ;;
    technical-lead) echo DR ;;
    security-reviewer) echo SR ;;
    qa-engineer) echo QA ;;
    technical-writer) echo DC ;;
    release-engineer) echo RE ;;
    project-manager) echo FN ;;
    stakeholder) echo ST ;;
    incident-responder) echo IR ;;
    ethics-reviewer) echo ET ;;
    *) echo "" ;;
  esac
}

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
# Canonical stage → artifact basename mapping (mirrors handoff-protocol.md#stage-artifact-map).
canonical_basename_for_stage() {
  case "$1" in
    PL) echo "planning" ;;
    AR) echo "architecture" ;;
    TL) echo "coordination" ;;
    DV) echo "development" ;;
    DR) echo "developer-review" ;;
    SR) echo "security-review" ;;
    QA) echo "testing" ;;
    DC) echo "documentation" ;;
    RE) echo "release" ;;
    FN) echo "complete-summary" ;;
    ST) echo "retrospective" ;;
    IR) echo "incident" ;;
    ET) echo "ethics-review" ;;
    *) echo "" ;;
  esac
}

# extract_stage() yq-parses the whole file, which aborts on any real artifact
# body ("mapping values are not allowed in this context") and made filename-lint
# skip every artifact it was meant to check. Scoped to the filename path on
# purpose: this compares basenames only, so tightening it cannot surface new
# assertions the way repairing extract_stage() for --anchor-lint would.
extract_stage_from_frontmatter() {
  local f="$1" fm
  fm=$(awk '/^---$/{c++; if (c==1) next; if (c==2) exit} c==1' "$f")
  [[ -n "$fm" ]] || return 0
  if command -v yq >/dev/null 2>&1; then
    printf '%s\n' "$fm" | yq eval '.handoff.stage // ""' - 2>/dev/null || true
  else
    printf '%s\n' "$fm" | awk '
      /^[[:space:]]*stage:[[:space:]]*/ {
        sub(/^[[:space:]]*stage:[[:space:]]*/, "")
        gsub(/[[:space:]"]+/, "")
        print
        exit
      }'
  fi
}

filename_lint() {
  local ctx_dir="$1"
  [[ -d "$ctx_dir" ]] || { echo "filename-lint: directory not found: $ctx_dir" >&2; exit 2; }

  local rc=0 count=0
  for artifact in "$ctx_dir"/*.md; do
    [[ -f "$artifact" ]] || continue

    local stage
    stage=$(extract_stage_from_frontmatter "$artifact")
    [[ -z "$stage" || "$stage" == "null" ]] && continue

    count=$((count + 1))
    local expected_base
    expected_base=$(canonical_basename_for_stage "$stage")
    [[ -z "$expected_base" ]] && continue

    local actual_name name_re expected_desc
    actual_name=$(basename "$artifact")
    name_re="^${expected_base}-[0-9]+\\.md\$"
    expected_desc="${expected_base}-N.md"
    # DV fans out one sub-agent per TL-assigned workstream, each writing
    # development-N-<stream>.md; the entry agent merges them into the canonical
    # development-N.md. Both names are legal on disk simultaneously.
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

# ---------- Self-test ----------
self_test() {
  local td
  td=$(mktemp -d -t cache-lint-XXXXXX)
  trap "rm -rf '$td'" EXIT

  # Anchor lint fixture: minimal DV artifact
  cat > "$td/development.md" <<'EOF'
---
handoff:
  stage: DV
  verdict: ok
  summary: "self-test fixture"
  refs: { plan: planning-0.md#requirements }
---

# Development

## files-changed

table goes here

## tests-added

list

## deviations

none

## follow-ups

none
EOF
  if "$0" --anchor-lint "$td/development.md" >/dev/null 2>&1; then
    echo "self-test: anchor-lint pass: ok"
  else
    echo "self-test: anchor-lint pass: FAIL" >&2; exit 1
  fi

  # Negative anchor lint: missing anchor
  cat > "$td/bad.md" <<'EOF'
---
handoff:
  stage: DV
  verdict: ok
  summary: "missing anchors"
  refs: { plan: planning-0.md#requirements }
---

## files-changed

partial
EOF
  if "$0" --anchor-lint "$td/bad.md" >/dev/null 2>&1; then
    echo "self-test: anchor-lint reject: FAIL (should have rejected missing anchors)" >&2; exit 1
  else
    echo "self-test: anchor-lint reject: ok"
  fi

  # Prefix lint fixture: two prompts, identical sections [1][2]
  local log="$td/log.jsonl"
  : > "$log"
  for stg in PL AR; do
    jq -cn --arg wid wf-self --arg stage "$stg" --arg prompt \
"<<<contract-reminder>>>
contract
<<<worktask-header>>>
worktask_id=wf-self
plan_file=planning-0.md
<<<stage-contract>>>
stage=$stg
<<<task>>>
desc" '{worktask_id:$wid, stage:$stage, prompt:$prompt}' >> "$log"
  done
  if "$0" "$log" >/dev/null 2>&1; then
    echo "self-test: prefix-lint pass: ok"
  else
    echo "self-test: prefix-lint pass: FAIL" >&2; exit 1
  fi

  # Negative: drift in section [1]
  jq -cn --arg prompt \
"<<<contract-reminder>>>
DIFFERENT contract
<<<worktask-header>>>
worktask_id=wf-self
plan_file=planning-0.md
<<<stage-contract>>>
stage=TL
<<<task>>>
desc" '{worktask_id:"wf-self", stage:"TL", prompt:$prompt}' >> "$log"

  if "$0" "$log" >/dev/null 2>&1; then
    echo "self-test: prefix-lint drift detect: FAIL (should have caught drift)" >&2; exit 1
  else
    echo "self-test: prefix-lint drift detect: ok"
  fi

  # L1 forbidden-token scanner (REQ-3/AC-4): happy path first (fresh log, no
  # forbidden tokens — must still pass byte-identity AND the new scan).
  local ftlog="$td/forbidden-token-log.jsonl"
  : > "$ftlog"
  jq -cn --arg wid wf-ft --arg stage PL --arg prompt \
"<<<contract-reminder>>>
contract
<<<worktask-header>>>
worktask_id=wf-ft
plan_file=planning-0.md
<<<stage-contract>>>
stage=PL
<<<task>>>
desc" '{worktask_id:$wid, stage:$stage, prompt:$prompt}' >> "$ftlog"
  if "$0" "$ftlog" >/dev/null 2>&1; then
    echo "self-test: forbidden-token-lint happy path: ok"
  else
    echo "self-test: forbidden-token-lint happy path: FAIL" >&2; exit 1
  fi

  # Negative: ISO-8601 timestamp injected into section [2] (worktask-header)
  # — a previously-uncaught class (byte-identical across every stage of THIS
  # worktask, so the existing drift check alone would miss it; only becomes a
  # problem cross-worktask, which the intrinsic scan catches immediately).
  local ftlog_ts="$td/forbidden-token-log-ts.jsonl"
  jq -cn --arg prompt \
"<<<contract-reminder>>>
contract
<<<worktask-header>>>
worktask_id=wf-ft-ts
plan_file=planning-0.md
generated_at=2026-07-05T15:15:39Z
<<<stage-contract>>>
stage=PL
<<<task>>>
desc" '{worktask_id:"wf-ft-ts", stage:"PL", prompt:$prompt}' > "$ftlog_ts"
  if "$0" "$ftlog_ts" >/dev/null 2>&1; then
    echo "self-test: forbidden-token-lint timestamp reject: FAIL (should have caught ISO-8601 timestamp)" >&2; exit 1
  else
    echo "self-test: forbidden-token-lint timestamp reject: ok"
  fi

  # Negative: retry counter injected into section [1] (contract-reminder) —
  # belongs in section [6] only, never [1]/[2]/[4].
  local ftlog_retry="$td/forbidden-token-log-retry.jsonl"
  jq -cn --arg prompt \
"<<<contract-reminder>>>
contract retry_count: 2
<<<worktask-header>>>
worktask_id=wf-ft-retry
plan_file=planning-0.md
<<<stage-contract>>>
stage=PL
<<<task>>>
desc" '{worktask_id:"wf-ft-retry", stage:"PL", prompt:$prompt}' > "$ftlog_retry"
  if "$0" "$ftlog_retry" >/dev/null 2>&1; then
    echo "self-test: forbidden-token-lint retry-counter reject: FAIL (should have caught retry_count)" >&2; exit 1
  else
    echo "self-test: forbidden-token-lint retry-counter reject: ok"
  fi

  # Frontmatter template lint: positive fixture (stage agent shaped like
  # the post-v3.9.0 collapsed agents).
  cat > "$td/developer.md" <<'EOF'
---
name: developer
description: dummy
---

# Developer

## Handoff Protocol

Required Inputs etc live in stage-contracts.md.

### Frontmatter for this stage (DV)

```yaml
---
handoff:
  stage: DV
  verdict: ok
  summary: "<one-line ≤200 chars>"
  files_touched:
    - path/to/file1.md
  next_stage_focus: "<imperative>"
  refs:
    decisions: architecture-N.md#decisions
---
```

## Other Section
EOF
  if "$0" --frontmatter-template-lint "$td/developer.md" >/dev/null 2>&1; then
    echo "self-test: frontmatter-template-lint pass: ok"
  else
    echo "self-test: frontmatter-template-lint pass: FAIL" >&2; exit 1
  fi

  # Negative: stage mismatch
  cat > "$td/qa-engineer.md" <<'EOF'
---
name: qa-engineer
description: dummy
---

# QA

## Handoff Protocol

text

### Frontmatter for this stage (QA)

```yaml
---
handoff:
  stage: DV
  verdict: ok
  summary: "wrong stage"
  refs: { dev: development-N.md#files-changed }
---
```
EOF
  if "$0" --frontmatter-template-lint "$td/qa-engineer.md" >/dev/null 2>&1; then
    echo "self-test: frontmatter-template-lint reject mismatch: FAIL (should have rejected stage mismatch)" >&2; exit 1
  else
    echo "self-test: frontmatter-template-lint reject mismatch: ok"
  fi

  # Negative: two yaml blocks (re-inlined boilerplate regression)
  cat > "$td/team-lead.md" <<'EOF'
---
name: team-lead
description: dummy
---

# TL

## Handoff Protocol

text

```yaml
---
handoff:
  stage: TL
  verdict: ok
  summary: "first"
  refs: { plan: planning-N.md#requirements }
---
```

```yaml
extra: block
```
EOF
  if "$0" --frontmatter-template-lint "$td/team-lead.md" >/dev/null 2>&1; then
    echo "self-test: frontmatter-template-lint reject duplicate: FAIL (should have rejected two yaml blocks)" >&2; exit 1
  else
    echo "self-test: frontmatter-template-lint reject duplicate: ok"
  fi

  # Positive: pointer-only form (P1 dedup, Batch 5/ad4) — zero inline yaml
  # blocks, but a stage-contracts.md#tpl-<CODE> pointer is present.
  cat > "$td/release-engineer.md" <<'EOF'
---
name: release-engineer
description: dummy
---

## Handoff Protocol

Frontmatter template (paste verbatim at artifact top): `stage-contracts.md#tpl-re`.

### State.json Atomic Merge — REQUIRED before return

no yaml block here, just the pointer above
EOF
  if "$0" --frontmatter-template-lint "$td/release-engineer.md" >/dev/null 2>&1; then
    echo "self-test: frontmatter-template-lint pointer-only pass: ok"
  else
    echo "self-test: frontmatter-template-lint pointer-only pass: FAIL" >&2; exit 1
  fi

  # Negative: zero yaml blocks AND no pointer (a botched dedup that deleted
  # the frontmatter with no replacement reference) — must be rejected.
  cat > "$td/stakeholder.md" <<'EOF'
---
name: stakeholder
description: dummy
---

## Handoff Protocol

Nothing here — no yaml block, no stage-contracts.md pointer.

### State.json Atomic Merge — REQUIRED before return

placeholder
EOF
  if "$0" --frontmatter-template-lint "$td/stakeholder.md" >/dev/null 2>&1; then
    echo "self-test: frontmatter-template-lint reject no-pointer-no-block: FAIL (should have rejected)" >&2; exit 1
  else
    echo "self-test: frontmatter-template-lint reject no-pointer-no-block: ok"
  fi

  # Filename lint: positive — canonical names
  mkdir -p "$td/ctx"
  cat > "$td/ctx/development-0.md" <<'EOF'
---
handoff:
  stage: DV
  verdict: ok
  summary: "self-test"
  refs: { plan: planning-0.md#requirements }
---
## files-changed
EOF
  cat > "$td/ctx/testing-0.md" <<'EOF'
---
handoff:
  stage: QA
  verdict: pass
  summary: "self-test"
  refs: { dev: development-0.md#files-changed }
---
## results
EOF
  if "$0" --filename-lint "$td/ctx" >/dev/null 2>&1; then
    echo "self-test: filename-lint pass: ok"
  else
    echo "self-test: filename-lint pass: FAIL" >&2; exit 1
  fi

  # Filename lint: negative — non-canonical name
  cat > "$td/ctx/arch-0.md" <<'EOF'
---
handoff:
  stage: AR
  verdict: ok
  summary: "wrong name"
  refs: { plan: planning-0.md }
---
## decisions
EOF
  if "$0" --filename-lint "$td/ctx" >/dev/null 2>&1; then
    echo "self-test: filename-lint reject non-canonical: FAIL (should have flagged arch-0.md)" >&2; exit 1
  else
    echo "self-test: filename-lint reject non-canonical: ok"
  fi

  echo "self-test: ALL PASS"
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
  --self-test)   self_test ;;
  "") usage ;;
  *) prefix_lint "$1"; exit $? ;;
esac
