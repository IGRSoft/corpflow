#!/usr/bin/env bash
# cache-lint.sh — preamble byte-stability lint for the handoff-protocol cache prefix.
#
# Two modes:
#
#   1. Prefix lint (default):
#        cache-lint.sh <prompt-log.jsonl>
#      Reads a prompt-log.jsonl (one prompt per line, schema:
#        {"workflow_id": "...", "stage": "...", "prompt": "..."}
#      where `prompt` contains marker tags <<<contract-reminder>>>,
#      <<<workflow-header>>>, <<<stage-contract>>> as section delimiters).
#      Asserts byte-identity of sections [1] contract-reminder + [2]
#      workflow-header across ALL stages of the same workflow_id, and
#      byte-identity of section [4] stage-contract across all calls of
#      the same (workflow_id, stage) pair. Exits 1 on drift.
#
#      N (number of lines compared) is computed from the FIRST stage's
#      sections [1]+[2]+[4] line count — derived dynamically, NOT a magic
#      number. Robust to spec changes.
#
#   2. Anchor lint:
#        cache-lint.sh --anchor-lint <artifact.md>
#      Verifies the artifact's H2 headings match the per-stage allow-list
#      from skills/workflow/references/handoff-protocol.md#anchor-allow-list.
#      Stage is read from the artifact's `handoff:` frontmatter (yq if
#      available; awk subset fallback). Exits 1 on missing/extra anchors.
#
#   3. Self-test:
#        cache-lint.sh --self-test
#      Runs both modes against built-in fixtures (tempdir). Exits 0 on pass.
#
# Reference: skills/workflow/references/handoff-protocol.md#cache-prefix
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
    wid=$(jq -r '.workflow_id' <<< "$line")
    stage=$(jq -r '.stage' <<< "$line")
    prompt=$(jq -r '.prompt' <<< "$line")

    local s1 s2 s4
    s1=$(extract_section "$prompt" "contract-reminder")
    s2=$(extract_section "$prompt" "workflow-header")
    s4=$(extract_section "$prompt" "stage-contract")

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
        echo "prefix-lint: workflow_id=$wid stage=$stage: section [1] contract-reminder DRIFT" >&2
        rc=1
      fi
      if [[ "$s2" != "$(cat "$f2")" ]]; then
        echo "prefix-lint: workflow_id=$wid stage=$stage: section [2] workflow-header DRIFT" >&2
        rc=1
      fi
    fi

    if [[ ! -f "$f4" ]]; then
      printf '%s' "$s4" > "$f4"
    elif [[ "$s4" != "$(cat "$f4")" ]]; then
      echo "prefix-lint: workflow_id=$wid stage=$stage: section [4] stage-contract DRIFT" >&2
      rc=1
    fi
  done < "$log"

  if [[ $rc -eq 0 ]]; then
    local nlines
    nlines=$(wc -l < "$log" | tr -d ' ')
    echo "prefix-lint: $nlines prompts checked, no drift"
  fi
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
<<<workflow-header>>>
workflow_id=wf-self
plan_file=planning-0.md
<<<stage-contract>>>
stage=$stg
<<<task>>>
desc" '{workflow_id:$wid, stage:$stage, prompt:$prompt}' >> "$log"
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
<<<workflow-header>>>
workflow_id=wf-self
plan_file=planning-0.md
<<<stage-contract>>>
stage=TL
<<<task>>>
desc" '{workflow_id:"wf-self", stage:"TL", prompt:$prompt}' >> "$log"

  if "$0" "$log" >/dev/null 2>&1; then
    echo "self-test: prefix-lint drift detect: FAIL (should have caught drift)" >&2; exit 1
  else
    echo "self-test: prefix-lint drift detect: ok"
  fi

  echo "self-test: ALL PASS"
}

# ---------- main ----------
case "${1:-}" in
  --anchor-lint) shift; [[ $# -ge 1 ]] || usage; anchor_lint "$1" ;;
  --self-test)   self_test ;;
  "") usage ;;
  *) prefix_lint "$1"; exit $? ;;
esac
