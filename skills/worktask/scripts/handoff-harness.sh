#!/usr/bin/env bash
# handoff-harness.sh — token-count + schema-validation harness for the
# handoff protocol (state.json + frontmatter + atomic write).
#
# Usage:
#   handoff-harness.sh [--out DIR]
#       Generates a synthetic state.json and 3 synthetic stage artifacts
#       (PL, AR, DV) under DIR (default: a tempdir). Constructs a "legacy"
#       prompt (full-file inlining) and a "new" prompt (state.json + anchors
#       only) for stages DV, DR, QA, DC, FN. Computes token counts using a
#       wc-words proxy (words × 1.33 ≈ cl100k_base tokens), prints a
#       per-stage diff table, and asserts ≥30% reduction on each. Exits 1
#       if any stage fails the threshold (AC-12).
#
#   handoff-harness.sh --self-test
#       Runs the above against built-in fixtures, then validates frontmatter
#       and state.json schemas using yq + jq. Exits 0 on pass.
#
#   handoff-harness.sh --validate-frontmatter <artifact.md> [--state <state.json>] [--strict]
#       Validates the artifact's `handoff:` frontmatter against the per-stage
#       required-field matrix. Exits 0 on pass, 1 on fail.
#
#       --state adds the AR->DV architecture-reference gate: when the artifact
#       is a DV handoff and the state ledger has a stages.AR entry, the
#       architecture reference (refs.decisions, then architecture.ref -- the
#       same precedence stage-contracts.md#tpl-dv and the DR rule declare)
#       must match ^architecture-[0-9]+\.md(#[a-z-]+)?$ and
#       resolve to a file beside the artifact. Without --state the check does
#       not run at all and behaviour is unchanged.
#
#       --strict turns gate violations from `warn:` + exit 0 into `fail:` +
#       exit 1. Equivalent env opt-in: IGRSOFT_AR_REF_STRICT=1, which the
#       orchestrator honours when deciding whether to pass --strict. The gate
#       ships warn-only in 3.42.0; --strict becomes the orchestrator default in
#       a future minor, so treat warnings as work to do now.
#
#       The inverse guard (an architecture reference with no stages.AR entry)
#       always warns and never fails, in either mode.
#
#       Exception: an unreadable --state (file missing, jq unavailable, or
#       invalid JSON) is itself a gate violation, not a silent skip -- it
#       warns by default and, unlike every other case above where --strict
#       is opt-in future behaviour, this ALREADY fails under --strict today
#       (exit 1). A state file we cannot read is not evidence AR didn't run.
#
#   handoff-harness.sh --validate-state <state.json>
#       Validates the ledger against the schema (required keys, ≤500 token
#       proxy, atomic-write idempotency check by re-merging the same patch).
#       Exits 0 on pass, 1 on fail.
#
# Tokenizer proxy: wc-words × 1.33. Documented in handoff-protocol.md.
# Spec: AR RK-6 accepts proxy because AC-12 is a RELATIVE reduction metric.
#
# AR decisions implemented: AD-1 (atomic write), AD-2 (frontmatter schema),
# AD-3 (state.json schema).
# AC satisfied: AC-5 (harness exists), AC-6 (validates schemas), AC-7
# (atomic-write idempotency), AC-8 (token reduction ≥30%).

set -euo pipefail

OUT_DIR=""
MODE="run"
ARG=""
STATE_ARG=""
# Env opt-in is read here so the gate is strict even when an older orchestrator
# forgets the --strict flag; --strict alone can only turn it on.
STRICT=0
if [[ "${IGRSOFT_AR_REF_STRICT:-0}" == "1" ]]; then STRICT=1; fi

usage() {
  sed -n 's/^# \{0,1\}//p' "$0" | sed -n '1,/^$/p'
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage ;;
    --out) shift; OUT_DIR="${1:-}"; shift ;;
    --self-test) MODE="self-test"; shift ;;
    --validate-frontmatter) MODE="validate-fm"; shift; ARG="${1:-}"; shift ;;
    --validate-state) MODE="validate-state"; shift; ARG="${1:-}"; shift ;;
    --state) shift; STATE_ARG="${1:-}"; shift ;;
    --strict) STRICT=1; shift ;;
    *) echo "unknown arg: $1" >&2; usage ;;
  esac
done

# ---------- Token counter (wc-words × 1.33 proxy) ----------
toks() {
  local f="$1"
  local words
  words=$(wc -w < "$f" | tr -d ' ')
  awk -v w="$words" 'BEGIN { printf "%d", w * 1.33 }'
}

toks_str() {
  local s="$1"
  local words
  words=$(printf '%s' "$s" | wc -w | tr -d ' ')
  awk -v w="$words" 'BEGIN { printf "%d", w * 1.33 }'
}

# ---------- Frontmatter validation ----------
PL_REQ="stage verdict summary refs key_decisions next_stage_focus"
AR_REQ="stage verdict summary refs key_decisions next_stage_focus open_questions"
TL_REQ="stage verdict summary refs next_stage_focus"
DV_REQ="stage verdict summary refs files_touched next_stage_focus"
DR_REQ="stage verdict summary refs key_decisions"
SR_REQ="stage verdict summary refs key_decisions"
QA_REQ="stage verdict summary refs files_touched key_decisions"
DC_REQ="stage verdict summary refs files_touched"
RE_REQ="stage verdict summary refs files_touched key_decisions"
FN_REQ="stage verdict summary refs next_stage_focus files_touched"
ST_REQ="stage verdict summary refs key_decisions"
IR_REQ="stage verdict summary refs key_decisions next_stage_focus"
ET_REQ="stage verdict summary refs key_decisions"

required_for() {
  case "$1" in
    PL) echo "$PL_REQ" ;; AR) echo "$AR_REQ" ;; TL) echo "$TL_REQ" ;;
    DV) echo "$DV_REQ" ;; DR) echo "$DR_REQ" ;; SR) echo "$SR_REQ" ;;
    QA) echo "$QA_REQ" ;; DC) echo "$DC_REQ" ;; RE) echo "$RE_REQ" ;;
    FN) echo "$FN_REQ" ;; ST) echo "$ST_REQ" ;; IR) echo "$IR_REQ" ;;
    ET) echo "$ET_REQ" ;;
    *) echo "" ;;
  esac
}

ARCH_REF_RE='^architecture-[0-9]+\.md(#[a-z-]+)?$'

# Warn-only by default so an advisory check can never break an unrelated run.
ar_ref_violation() {
  if [[ "$STRICT" -eq 1 ]]; then
    echo "fail: $1" >&2
    return 1
  fi
  echo "warn: $1" >&2
  return 0
}

# Runtime truth for "did AR run" is the stages.AR entry, never the presence of
# an architecture file — AR is optional and PL0 decides it per run.
check_ar_ref() {
  local artifact="$1" fmfile="$2"

  # A state file we cannot read is NOT evidence that AR did not run. Saying so
  # out loud keeps the two cases distinguishable once --strict becomes the
  # default, where a silent skip would be a false negative on every jq-less host.
  local unreadable=""
  if [[ ! -f "$STATE_ARG" ]]; then
    unreadable="state file not found: $STATE_ARG"
  elif ! command -v jq >/dev/null 2>&1; then
    unreadable="jq unavailable; cannot read $STATE_ARG"
  elif ! jq empty "$STATE_ARG" >/dev/null 2>&1; then
    unreadable="state file is not valid JSON: $STATE_ARG"
  fi

  if [[ -n "$unreadable" ]]; then
    ar_ref_violation "AR-ref check skipped — $unreadable" || return 1
    return 0
  fi

  local ar_present=0
  if jq -e '.stages.AR' "$STATE_ARG" >/dev/null 2>&1; then
    ar_present=1
  fi

  local ref
  ref=$(yq eval '.handoff.refs.decisions // .handoff.architecture.ref // ""' "$fmfile")
  [[ "$ref" == "null" ]] && ref=""

  if [[ "$ar_present" -eq 0 ]]; then
    if [[ -n "$ref" ]] && printf '%s' "$ref" | grep -qE '^architecture-'; then
      echo "warn: DV references $ref but state has no stages.AR entry" >&2
    fi
    return 0
  fi

  if [[ -z "$ref" ]]; then
    ar_ref_violation "AR completed but DV refs.decisions missing" || return 1
    return 0
  fi

  if ! printf '%s' "$ref" | grep -qE "$ARCH_REF_RE"; then
    ar_ref_violation "DV architecture ref dangling: $ref" || return 1
    return 0
  fi

  local reffile
  reffile="${ref%%#*}"
  if [[ ! -f "$(dirname "$artifact")/$reffile" ]]; then
    ar_ref_violation "DV architecture ref dangling: $reffile" || return 1
    return 0
  fi

  return 0
}

validate_frontmatter() {
  local f="$1"
  [[ -f "$f" ]] || { echo "frontmatter: file not found: $f" >&2; return 1; }

  # Extract just the frontmatter block (between first two ^---$ lines) to a tmp,
  # so yq can parse it as pure YAML (the rest of the markdown is not YAML).
  local fmfile
  fmfile=$(mktemp -t handoff-fm-XXXXXX)
  awk '/^---$/{c++; if (c==1) next; if (c==2) exit} c==1' "$f" > "$fmfile"
  if [[ ! -s "$fmfile" ]]; then
    rm -f "$fmfile"
    echo "fail: missing frontmatter block in $f" >&2
    return 1
  fi

  command -v yq >/dev/null 2>&1 || {
    echo "frontmatter: yq required for full validation; running grep-only fallback" >&2
    head -1 "$f" | grep -q '^---$' || { rm -f "$fmfile"; echo "fail: missing leading ---" >&2; return 1; }
    grep -q '^handoff:' "$fmfile" || { rm -f "$fmfile"; echo "fail: no handoff: block" >&2; return 1; }
    rm -f "$fmfile"
    return 0
  }

  local stage
  stage=$(yq eval '.handoff.stage // ""' "$fmfile")
  [[ -n "$stage" && "$stage" != "null" ]] || { rm -f "$fmfile"; echo "fail: no stage" >&2; return 1; }

  local req
  req=$(required_for "$stage")
  [[ -n "$req" ]] || { rm -f "$fmfile"; echo "fail: unknown stage $stage" >&2; return 1; }

  local field
  for field in $req; do
    local val
    val=$(yq eval ".handoff.${field} // \"\"" "$fmfile")
    if [[ -z "$val" || "$val" == "null" ]]; then
      rm -f "$fmfile"
      echo "fail: stage=$stage missing required field: $field" >&2
      return 1
    fi
  done

  if [[ "$stage" == "DV" && -n "$STATE_ARG" ]]; then
    if ! check_ar_ref "$f" "$fmfile"; then
      rm -f "$fmfile"
      return 1
    fi
  fi

  # Token budget check (≤200 cl100k_base proxy)
  local tcount
  tcount=$(toks "$fmfile")
  rm -f "$fmfile"
  if [[ "$tcount" -gt 200 ]]; then
    echo "warn: stage=$stage frontmatter ${tcount} tokens > 200 budget" >&2
  fi

  echo "ok: $f stage=$stage tokens=$tcount"
}

# ---------- state.json validation ----------
validate_state() {
  local f="$1"
  [[ -f "$f" ]] || { echo "state: file not found: $f" >&2; return 1; }
  command -v jq >/dev/null 2>&1 || { echo "state: jq required" >&2; return 1; }

  jq empty "$f" 2>/dev/null || { echo "fail: state.json invalid JSON" >&2; return 1; }
  local v
  v=$(jq -r '.version' "$f")
  [[ "$v" == "1" ]] || { echo "fail: version != 1 (got '$v')" >&2; return 1; }
  jq -e 'has("worktask_id") and has("plan_file") and has("platform") and has("stages") and has("facts") and has("handoffs")' "$f" >/dev/null \
    || { echo "fail: missing required keys" >&2; return 1; }

  local tcount
  tcount=$(toks "$f")
  if [[ "$tcount" -gt 500 ]]; then
    echo "warn: state.json ${tcount} tokens > 500 budget" >&2
  fi

  # Atomic-write idempotency check: re-merging the same patch must be a no-op.
  local td
  td=$(mktemp -d -t handoff-state-XXXXXX)
  trap "rm -rf '$td'" RETURN
  cp "$f" "$td/orig.json"
  local patch='{"stages":{"PL":{"status":"completed"}}}'
  jq --argjson p "$patch" '. * $p' "$td/orig.json" > "$td/m1.json"
  jq --argjson p "$patch" '. * $p' "$td/m1.json" > "$td/m2.json"
  if ! diff -q "$td/m1.json" "$td/m2.json" >/dev/null; then
    echo "fail: idempotent merge produced different output" >&2
    return 1
  fi

  echo "ok: $f tokens=$tcount idempotent=yes"
}

# ---------- Synthetic fixtures + token-count run ----------
make_fixtures() {
  local d="$1"
  mkdir -p "$d/.context"

  cat > "$d/.context/state.json" <<'EOF'
{
  "version": 1,
  "worktask_id": "harness-demo",
  "plan_file": ".context/planning-0.md",
  "platform": "all",
  "stages": {
    "PL": {"status":"completed","verdict":"ok"},
    "AR": {"status":"completed","verdict":"ok"},
    "TL": {"status":"completed","verdict":"ok"}
  },
  "facts": {
    "files_modified": [],
    "tests_added": [],
    "decisions": [
      {"id":"pd1","summary":"9-stage worktask","ref":"planning-0.md#stages"},
      {"id":"ad1","summary":"Atomic write agent-primary + hook idempotent","ref":"architecture.md#decisions"}
    ],
    "open_questions": [],
    "verdicts": {"PL":"ok","AR":"ok","TL":"ok"}
  },
  "handoffs": {
    "PL→AR": "9-stage, complexity 38. ref: planning-0.md#requirements",
    "AR→TL": "Schemas designed, atomic write strategy. ref: architecture.md#decisions",
    "TL→DV": "24-file fan-out, 8 batches. ref: coordination.md#fan-out"
  }
}
EOF

  cat > "$d/.context/planning-0.md" <<'EOF'
---
handoff:
  stage: PL
  verdict: ok
  summary: "Demo plan for harness."
  key_decisions:
    - { id: pd1, summary: "9-stage", anchor: "planning-0.md#stages" }
  next_stage_focus: "AR designs schema"
  refs: { plan: planning-0.md#requirements }
---

# Planning

## requirements

EOF
  # Pad with synthetic body to make the legacy-mode reading expensive.
  for i in $(seq 1 200); do echo "- requirement line $i with extra context describing the work to be done in this synthetic plan" >> "$d/.context/planning-0.md"; done
  cat >> "$d/.context/planning-0.md" <<'EOF'

## acceptance-criteria

EOF
  for i in $(seq 1 60); do echo "- AC-$i criterion description with measurement details" >> "$d/.context/planning-0.md"; done
  cat >> "$d/.context/planning-0.md" <<'EOF'

## scope

In scope.

## out-of-scope

Out.

## risks

None.

## complexity

Score 38.

## stages

PL AR TL DV DR QA DC FN ST.
EOF

  cat > "$d/.context/architecture.md" <<'EOF'
---
handoff:
  stage: AR
  verdict: ok
  summary: "Schemas designed."
  key_decisions:
    - { id: ad1, summary: "Atomic write", anchor: "architecture.md#decisions" }
  next_stage_focus: "TL fans out edits"
  open_questions: ["q3: hook lang"]
  refs: { plan: planning-0.md#requirements }
---

# Architecture

## decisions

EOF
  for i in $(seq 1 200); do echo "- AD-$i decision body with justification, alternatives, and trade-offs spanning multiple lines" >> "$d/.context/architecture.md"; done
  cat >> "$d/.context/architecture.md" <<'EOF'

## trade-offs

Listed.

## patterns

Listed.

## integration-points

Listed.

## schemas

Listed.

## open-questions

q3, q4, q5, q6.

## risks

Listed.
EOF

  cat > "$d/.context/development.md" <<'EOF'
---
handoff:
  stage: DV
  verdict: ok
  summary: "Implemented."
  files_touched: [a.md, b.md]
  next_stage_focus: "DR reviews"
  refs: { dev: development.md#files-changed }
---

# Development

## files-changed

EOF
  for i in $(seq 1 100); do echo "- file-$i.md edit description" >> "$d/.context/development.md"; done
  cat >> "$d/.context/development.md" <<'EOF'

## tests-added

None.

## deviations

None.

## follow-ups

None.
EOF
}

run_token_count() {
  local d="${1:-$(mktemp -d -t handoff-demo-XXXXXX)}"
  make_fixtures "$d"

  echo "Fixtures created at: $d"
  echo
  printf '%-6s | %12s | %10s | %10s\n' "stage" "legacy_tok" "new_tok" "reduction"
  printf '%s\n' "------+--------------+------------+-----------"

  # New mode prompt: state.json blob + targeted anchor headers (frontmatter only).
  local state_tok
  state_tok=$(toks "$d/.context/state.json")

  # Per-stage simulated reading scope.
  # POSIX-compatible: case-statement lookup instead of associative arrays.
  legacy_files_for() {
    case "$1" in
      DV) echo ".context/planning-0.md .context/architecture.md" ;;
      DR) echo ".context/planning-0.md .context/architecture.md .context/development.md" ;;
      QA) echo ".context/planning-0.md .context/development.md" ;;
      DC) echo ".context/planning-0.md .context/development.md" ;;
      FN) echo ".context/planning-0.md .context/architecture.md .context/development.md" ;;
      *) echo "" ;;
    esac
  }
  new_files_for() {
    case "$1" in
      DV) echo ".context/planning-0.md" ;;
      DR|QA|DC|FN) echo ".context/development.md" ;;
      *) echo "" ;;
    esac
  }

  local rc=0 stage
  for stage in DV DR QA DC FN; do
    local legacy=0 new=$state_tok
    local rel
    for rel in $(legacy_files_for "$stage"); do
      legacy=$(( legacy + $(toks "$d/$rel") ))
    done
    # New mode: state.json + ONLY the frontmatter block of the most relevant artifact
    for rel in $(new_files_for "$stage"); do
      local fm
      fm=$(awk '/^---$/{c++; if (c==2) exit} c>=1' "$d/$rel")
      new=$(( new + $(toks_str "$fm") ))
    done
    local reduction
    reduction=$(awk -v l="$legacy" -v n="$new" 'BEGIN { if (l==0) print "0%"; else printf "%.0f%%", (l-n)*100.0/l }')
    printf '%-6s | %12d | %10d | %10s\n' "$stage" "$legacy" "$new" "$reduction"

    # Threshold: ≥30% reduction (AC-12).
    local pct
    pct=$(awk -v l="$legacy" -v n="$new" 'BEGIN { if (l==0) print 0; else printf "%.0f", (l-n)*100.0/l }')
    if [[ "$pct" -lt 30 ]]; then
      echo "FAIL: stage=$stage reduction $pct% < 30% threshold" >&2
      rc=1
    fi
  done

  echo
  if [[ $rc -eq 0 ]]; then
    echo "PASS: all stages ≥30% reduction (AC-12 met)"
  else
    echo "FAIL: one or more stages below 30% threshold"
  fi
  return $rc
}

# ---------- Self-test ----------
self_test() {
  local td
  td=$(mktemp -d -t handoff-selftest-XXXXXX)
  trap "rm -rf '$td'" EXIT

  make_fixtures "$td"
  validate_frontmatter "$td/.context/planning-0.md" >/dev/null
  validate_frontmatter "$td/.context/architecture.md" >/dev/null
  validate_frontmatter "$td/.context/development.md" >/dev/null
  validate_state "$td/.context/state.json" >/dev/null

  if run_token_count "$td" >/dev/null 2>&1; then
    echo "self-test: token-count ≥30% reduction: ok"
  else
    echo "self-test: token-count: FAIL" >&2; exit 1
  fi

  self_test_ar_gate "$td"

  echo "self-test: ALL PASS"
}

# Exercises every branch of the AR->DV gate. Each case restores STATE_ARG/STRICT
# itself, so ordering between cases carries no state.
self_test_ar_gate() {
  local ctx="$1/.context"

  if ! command -v yq >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    echo "self-test: ar-ref gate: SKIP (yq/jq unavailable)"
    return 0
  fi

  jq 'del(.stages.AR)' "$ctx/state.json" > "$ctx/state-no-ar.json"

  # The shared preamble every gate fixture needs; only refs differ per case.
  _dv_artifact() {
    local path="$1" refs_block="$2"
    {
      echo '---'
      echo 'handoff:'
      echo '  stage: DV'
      echo '  verdict: ok'
      echo '  summary: "Implemented."'
      echo '  files_touched: [a.md]'
      echo '  next_stage_focus: "DR reviews"'
      echo '  refs:'
      printf '%s\n' "$refs_block"
      echo '---'
      echo
      echo '# Development'
    } > "$path"
  }

  _dv_artifact "$ctx/dv-no-ref.md"    '    dev: development.md#files-changed'
  _dv_artifact "$ctx/dv-dangling.md"  '    decisions: architecture-9.md#decisions'
  _dv_artifact "$ctx/dv-valid.md"     '    decisions: architecture-0.md#decisions'
  cp "$ctx/architecture.md" "$ctx/architecture-0.md"

  # <label> <state-file|-> <strict> <want-rc> <want-pattern|-> <artifact>
  _ar_case() {
    local label="$1" state="$2" strict="$3" want_rc="$4" want_pat="$5" artifact="$6"
    STATE_ARG=""; [[ "$state" != "-" ]] && STATE_ARG="$state"
    STRICT="$strict"
    local out rc=0
    out=$(validate_frontmatter "$artifact" 2>&1) || rc=$?
    STATE_ARG=""; STRICT=0
    if [[ "$rc" -ne "$want_rc" ]]; then
      echo "self-test: ar-ref $label: FAIL (rc=$rc want=$want_rc)" >&2; exit 1
    fi
    if [[ "$want_pat" == "-" ]]; then
      if printf '%s' "$out" | grep -qE '^(warn|fail): (AR completed|DV architecture|DV references)'; then
        echo "self-test: ar-ref $label: FAIL (unexpected gate line)" >&2; exit 1
      fi
    elif ! printf '%s' "$out" | grep -q "$want_pat"; then
      echo "self-test: ar-ref $label: FAIL (pattern not found: $want_pat)" >&2; exit 1
    fi
    echo "self-test: ar-ref $label: ok"
  }

  _ar_case "AR+missing/default"  "$ctx/state.json"       0 0 "warn: AR completed but DV refs.decisions missing" "$ctx/dv-no-ref.md"
  _ar_case "AR+missing/strict"   "$ctx/state.json"       1 1 "fail: AR completed but DV refs.decisions missing" "$ctx/dv-no-ref.md"
  _ar_case "AR+dangling/default" "$ctx/state.json"       0 0 "warn: DV architecture ref dangling"               "$ctx/dv-dangling.md"
  _ar_case "AR+dangling/strict"  "$ctx/state.json"       1 1 "fail: DV architecture ref dangling"               "$ctx/dv-dangling.md"
  _ar_case "AR+valid/default"    "$ctx/state.json"       0 0 -                                                  "$ctx/dv-valid.md"
  _ar_case "AR+valid/strict"     "$ctx/state.json"       1 0 -                                                  "$ctx/dv-valid.md"
  _ar_case "noAR+noref/default"  "$ctx/state-no-ar.json" 0 0 -                                                  "$ctx/dv-no-ref.md"
  _ar_case "noAR+ref/default"    "$ctx/state-no-ar.json" 0 0 "warn: DV references architecture-0.md"               "$ctx/dv-valid.md"
  _ar_case "noAR+ref/strict"     "$ctx/state-no-ar.json" 1 0 "warn: DV references architecture-0.md"               "$ctx/dv-valid.md"
  _ar_case "legacy/no-state"     -                       0 0 -                                                  "$ctx/dv-no-ref.md"
  _ar_case "legacy/no-state+strict" -                    1 0 -                                                  "$ctx/dv-dangling.md"

  # F5: an unreadable --state must be loud, not silently indistinguishable from "no AR".
  printf 'not json {{' > "$ctx/state-corrupt.json"
  _ar_case "badstate/missing/default" "$ctx/nope.json"     0 0 "warn: AR-ref check skipped" "$ctx/dv-no-ref.md"
  _ar_case "badstate/missing/strict"  "$ctx/nope.json"     1 1 "fail: AR-ref check skipped" "$ctx/dv-no-ref.md"
  _ar_case "badstate/corrupt/default" "$ctx/state-corrupt.json" 0 0 "warn: AR-ref check skipped" "$ctx/dv-no-ref.md"
  _ar_case "badstate/corrupt/strict"  "$ctx/state-corrupt.json" 1 1 "fail: AR-ref check skipped" "$ctx/dv-no-ref.md"
}

# ---------- main ----------
case "$MODE" in
  run)              run_token_count "${OUT_DIR:-}" ;;
  self-test)        self_test ;;
  validate-fm)      [[ -n "$ARG" ]] || usage; validate_frontmatter "$ARG" ;;
  validate-state)   [[ -n "$ARG" ]] || usage; validate_state "$ARG" ;;
  *) usage ;;
esac
