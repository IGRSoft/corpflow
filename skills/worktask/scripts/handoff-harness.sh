#!/usr/bin/env bash
# handoff-harness.sh — token-count + schema-validation harness for the
# handoff protocol (state.json + frontmatter + atomic write).
#
# Usage:
#   handoff-harness.sh [--out DIR]
#       Generates a synthetic state.json and 3 synthetic stage artifacts
#       (PL, AR, DV) under DIR (default: a tempdir). Constructs a "baseline"
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
#       is a DV handoff and the state ledger has a tasks.AR<N> entry, the
#       architecture reference (refs.decisions, then architecture.ref -- the
#       same precedence stage-contracts.md#tpl-dv and the DR rule declare)
#       must match ^architecture-[0-9]+\.md(#[a-z-]+)?$ and
#       resolve to a file beside the artifact. Without --state the check does
#       not run at all and behaviour is unchanged.
#
#       --strict turns gate violations from `warn:` + exit 0 into `fail:` +
#       exit 1. Equivalent env opt-in: CORPFLOW_AR_REF_STRICT=1, which the
#       orchestrator honours when deciding whether to pass --strict. The gate
#       ships warn-only in 3.42.0; --strict becomes the orchestrator default in
#       a future minor, so treat warnings as work to do now.
#
#       The inverse guard (an architecture reference with no tasks.AR<N> entry)
#       always warns and never fails, in either mode.
#
#       The three closing-sweep checks (stub shape, ref anchor, ledger parity)
#       ride on the same invocation for EVERY stage and hard-fail in both modes.
#       Ledger parity needs --state; when --state is unreadable and the artifact
#       carries a sweep stub it fails rather than skips.
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
if [[ "${CORPFLOW_AR_REF_STRICT:-0}" == "1" ]]; then STRICT=1; fi

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

# Tokens spent on the open_questions block alone, for the AD-2 discretionary budget.
# Measured over the SAME source text `toks` counts — the frontmatter as written, not a
# re-emitted copy — so the subtraction is exact rather than an estimate of a re-render.
# The block runs from the `open_questions:` key to the next line indented no deeper, which
# is how YAML already delimits it; a file without the key yields 0.
toks_open_questions_block() {
  local f="$1" words
  words=$(awk '
    /^[[:space:]]*open_questions:/ && !inblock {
      match($0, /^[[:space:]]*/); indent = RLENGTH; inblock = 1; print; next
    }
    inblock {
      if ($0 ~ /^[[:space:]]*$/) { print; next }
      match($0, /^[[:space:]]*/)
      if (RLENGTH <= indent) { inblock = 0; next }
      print
    }' "$f" | wc -w | tr -d ' ')
  awk -v w="$words" 'BEGIN { printf "%d", w * 1.33 }'
}

toks_str() {
  local s="$1"
  local words
  words=$(printf '%s' "$s" | wc -w | tr -d ' ')
  awk -v w="$words" 'BEGIN { printf "%d", w * 1.33 }'
}

# ---------- Frontmatter validation ----------
PL_REQ="stage verdict summary refs key_decisions next_stage_focus open_questions"
AR_REQ="stage verdict summary refs key_decisions next_stage_focus open_questions"
TL_REQ="stage verdict summary refs next_stage_focus open_questions"
# R-2.1 — the changed-file list is capped structurally, not excluded from the budget: the
# observed failure was not stages running out of budget, it was each stage inventing its own
# truncation. One shape everywhere: the first FILES_TOUCHED_MAX repo-relative paths plus a
# single `+ <count> more` marker. Ten paths plus the marker measure 33 proxy tokens of the
# 200-token discretionary budget. Defined once here and in stage-contracts.md; the budget
# checker gains no second extractor and no second cap constant.
FILES_TOUCHED_MAX=10

DV_REQ="stage verdict summary refs files_touched next_stage_focus tests_executed open_questions"
DR_REQ="stage verdict summary refs key_decisions open_questions"
SR_REQ="stage verdict summary refs key_decisions open_questions"
QA_REQ="stage verdict summary refs files_touched key_decisions tests_executed open_questions"
DC_REQ="stage verdict summary refs files_touched open_questions"
RE_REQ="stage verdict summary refs files_touched key_decisions open_questions"
FN_REQ="stage verdict summary refs next_stage_focus files_touched open_questions"
ST_REQ="stage verdict summary refs key_decisions open_questions"
IR_REQ="stage verdict summary refs key_decisions next_stage_focus open_questions"
ET_REQ="stage verdict summary refs key_decisions open_questions"

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

# The SweepStub predicate is defined once, in sweep-stub-lib.sh, and enforced twice — here and
# in state-patch.sh --facts. A shape gate that cannot load its shape must not pass anything.
_SWEEP_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/sweep-stub-lib.sh"
if [ -r "$_SWEEP_LIB" ]; then
  # shellcheck source=/dev/null
  . "$_SWEEP_LIB"
fi
if [ -z "${SWEEP_ID_RE:-}" ] || [ -z "${SWEEP_CLASS_ENUM:-}" ] || [ -z "${SWEEP_REF_RE:-}" ]; then
  echo "fail: sweep-stub-lib.sh unreachable at $_SWEEP_LIB — the sweep shape gate cannot run" >&2
  exit 1
fi

# One frontmatter reader across this tool and state-patch.sh. Fail closed for the same
# reason the sweep library does: a missing library under skills/ is a broken install.
# Sourced AFTER the sweep guard so a wholly broken install still reports the sweep library
# first, which is the message the cross-enforcer parity suite pins.
_FM_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/frontmatter-lib.sh"
if [ ! -r "$_FM_LIB" ]; then
  printf >&2 'fail: frontmatter-lib.sh unreachable at %s — the frontmatter reader cannot run\n' "$_FM_LIB"
  exit 1
fi
# shellcheck source=frontmatter-lib.sh
. "$_FM_LIB"

# Fail closed like the two libraries above: a gate that cannot scan for raw bytes must not
# hand yq an artifact it may silently truncate at a NUL.
_CB_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/control-byte-lib.sh"
if [ -r "$_CB_LIB" ]; then
  # shellcheck source=control-byte-lib.sh
  . "$_CB_LIB"
fi
if ! command -v cb_scan_file > /dev/null 2>&1; then
  printf >&2 'fail: control-byte-lib.sh unreachable at %s — the control-byte gate cannot run\n' "$_CB_LIB"
  exit 1
fi

# A yq failure inside a sweep check is a gate FAILURE, never a skip: the gate has no advisory
# tier, so a read that cannot be trusted must not yield a pass. First error line is surfaced.
_sweep_yq() {  # <expr> <fmfile>
  local out
  if ! out=$(yq eval "$1" "$2" 2>&1); then
    echo "fail: open_questions could not be read as sweep stubs — ${out%%$'\n'*}" >&2
    return 1
  fi
  printf '%s' "$out"
}

# ONE yq pass over the frontmatter, feeding all three sweep checks. This runs at every one
# of the thirteen stage boundaries, and the six separate `yq eval` processes it replaces
# each re-parsed the same file to answer one question about the same list.
#
# Still one select per defect, because yq v4 has no if/elif and a lumped rejection names no
# cause: the arms are concatenated into one array and splatted, each row tagged with the
# defect it evidences. The three predicates are SWEEP_ID_RE, SWEEP_CLASS_ENUM and
# SWEEP_REF_RE from sweep-stub-lib.sh — the same constants state-patch.sh --facts enforces,
# interpolated here and passed as jq arguments there, never re-stated in either place.
#
# The trailing STUB rows are the id/ref inventory the anchor and ledger-parity checks walk;
# they cover map items only, so those two never have to re-ask what shape an item was. FLAGS
# is a SECOND inventory rather than three more fields on STUB: check_sweep_ref_anchor splits a
# STUB row on its first space and takes the rest as the ref, so a widened row would silently
# hand it a ref with trailing junk.
_sweep_scan() {  # <fmfile> -> tagged rows on stdout
  local base='[.handoff.open_questions[]?] | to_entries | .[]'
  local classexpr="" cls
  for cls in $SWEEP_CLASS_ENUM; do
    classexpr="${classexpr:+$classexpr and }(.value.class // \"\") != \"$cls\""
  done
  # `tostring` on the id keeps a non-string id inside the bad-id arm rather than in yq's error path.
  local ismap='select(.value | type == "!!map")'
  _sweep_yq "(
      [\"TYPE \" + (.handoff.open_questions | type)]
    + [$base | select(.value | type != \"!!map\") | \"NONMAP \" + (.key | tostring)]
    + [$base | $ismap | select(((.value.id // \"\") | tostring) | test(\"$SWEEP_ID_RE\") | not) | \"BADID \" + (.key | tostring) + \" \" + ((.value.id // \"\") | tostring)]
    + [$base | $ismap | select($classexpr) | \"BADCLASS \" + (.key | tostring) + \" \" + ((.value.id // \"\") | tostring)]
    + [$base | $ismap | select(((.value.ref // \"\") | tostring) | test(\"$SWEEP_REF_RE\") | not) | \"NOREF \" + (.key | tostring) + \" \" + ((.value.id // \"\") | tostring)]
    + [$base | $ismap | select((.value.blocks_next_stage | tag) != \"!!bool\") | \"NOFLAG \" + (.key | tostring) + \" \" + ((.value.id // \"\") | tostring)]
    + [$base | $ismap | \"STUB \" + ((.value.id // \"\") | tostring) + \" \" + ((.value.ref // \"\") | tostring)]
    + [$base | $ismap | \"FLAGS \" + ((.value.id // \"\") | tostring) + \" \" + ((.value.class // \"\") | tostring) + \" \" + ((.value.blocks_next_stage // false) | tostring)]
  ) | .[]" "$1"
}

# Memoised per artifact: the three checks run back to back against one file, and a second
# scan would re-pay the parse this consolidation exists to remove.
_sweep_scan_for=""
_sweep_scan_out=""
_sweep_load() {  # <fmfile>
  [[ "$_sweep_scan_for" == "$1" ]] && return 0
  _sweep_scan_out=$(_sweep_scan "$1") || return 1
  _sweep_scan_for="$1"
  return 0
}

# Rows of one tag, with the tag stripped.
_sweep_rows() {  # <TAG>
  printf '%s' "$_sweep_scan_out" | sed -n "s/^$1 //p"
}

# THE shape gate for open_questions[]: the sweep stub is the only item shape the field
# accepts, so this runs first and the two checks below may assume every surviving item is a
# map carrying id/class/ref. A bare schema rejection names no cause, so each defect gets its
# own sentence. Offenders are addressed by index, the only identity a non-map item has.
check_sweep_stub_shape() {
  local fmfile="$1" rc=0 line
  local oqtype nonmap badid badclass noref noflag

  _sweep_load "$fmfile" || return 1

  # `[]?` in the scan silently yields nothing for a scalar, and the required-field loop only
  # asks for a non-empty value, so `open_questions: "none"` would otherwise pass every check.
  oqtype=$(_sweep_rows TYPE)
  case "$oqtype" in
    '!!seq' | '!!null') ;;
    *)
      echo "fail: open_questions is $oqtype, not a sequence — write open_questions: [] when there is nothing to elicit" >&2
      return 1 ;;
  esac

  nonmap=$(_sweep_rows NONMAP)
  badid=$(_sweep_rows BADID)
  badclass=$(_sweep_rows BADCLASS)
  noref=$(_sweep_rows NOREF)
  noflag=$(_sweep_rows NOFLAG)

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    echo "fail: open_questions[$line] is not a sweep stub — every item is { id: sw-<TASK_ID>-<n>, class: decision|escalate, ref: \"<artifact>-N.md#elicitation-sweep\", blocks_next_stage: false }" >&2
    rc=1
  done <<< "$nonmap"
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    echo "fail: open_questions[${line%% *}] id \"${line#* }\" is not sw-<TASK_ID>-<n>" >&2
    rc=1
  done <<< "$badid"
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    echo "fail: sweep stub $(_sweep_label "$line") class is not $(printf '%s' "$SWEEP_CLASS_ENUM" | tr ' ' '|')" >&2
    rc=1
  done <<< "$badclass"
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    echo "fail: sweep stub $(_sweep_label "$line") carries no ref anchor — add ref: \"<artifact>-N.md#elicitation-sweep\" (an optional .md path plus one non-empty #anchor)" >&2
    rc=1
  done <<< "$noref"
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    echo "fail: sweep stub $(_sweep_label "$line") carries no blocks_next_stage — add blocks_next_stage: false (or true only if the next stage would build on a guess)" >&2
    rc=1
  done <<< "$noflag"
  return $rc
}

# "<index> <id>" -> the id when the item has one, else its positional address.
_sweep_label() {
  local id="${1#* }"
  [[ -n "$id" ]] && printf '%s' "$id" || printf 'open_questions[%s]' "${1%% *}"
}

# The stub's `ref` anchor is the SOLE transport of the options[] the FN gate renders —
# SweepStub carries none. A dangling anchor therefore has no failure arm anywhere in
# Step C: C.4 either skips the item or invents options, which is silent degradation of
# exactly the kind the ledger-parity check above exists to prevent. Verifying the FIELD
# exists is not enough; check_sweep_stub_shape's own error message hands the agent the
# literal to paste. An empty open_questions array walks nothing, so there is nothing to
# compare and the check is silent.
# An empty `open_questions: []` is a claim, not an absence: it says "I ran the sweep and had
# nothing to ask". Nothing distinguished that from a stage that never swept, which is the
# whole point of the rule — so the prose half is required exactly when the array half is
# empty, the mirror of the `ref` anchor already required when it is not.
#
# The heading alone is the check. Its CONTENT is the stage's explicit statement, and this
# gate does not read it: an anchor with an empty body is a stage that wrote the heading
# without thinking, which is a review problem rather than a mechanical one.
check_empty_sweep_prose() {
  local artifact="$1" fmfile="$2" oqtype rows

  oqtype=$(_sweep_rows TYPE)
  # Only a real sequence reaches this arm. A non-sequence is check_sweep_stub_shape's
  # failure and an ABSENT field is the required-field loop's, both already reported;
  # calling either one "empty" here would send the stage two failures for one slip.
  case "$oqtype" in
    '!!seq') ;;
    *) return 0 ;;
  esac
  rows=$(_sweep_rows STUB)
  [[ -z "$rows" ]] || return 0

  if ! grep -qE '^## +elicitation-sweep[[:space:]]*$' "$artifact"; then
    echo "fail: open_questions is empty but $(basename "$artifact") has no '## elicitation-sweep' heading — an empty array alone cannot tell 'swept, nothing to ask' from 'never swept'. Write the heading with the explicit statement (stage-contracts.md § Closing Elicitation Sweep)" >&2
    return 1
  fi
  return 0
}

check_sweep_ref_anchor() {
  local artifact="$1" fmfile="$2"
  local dir rows line id ref file anchor target
  dir=$(dirname "$artifact")
  _sweep_load "$fmfile" || return 1
  rows=$(_sweep_rows STUB)
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    id="${line%% *}"
    ref="${line#* }"
    [[ -n "$ref" && "$ref" != "$id" ]] || continue   # missing ref is check_sweep_stub_shape's failure
    anchor="${ref##*#}"
    file="${ref%%#*}"
    if [[ -z "$anchor" || "$anchor" == "$ref" ]]; then
      echo "fail: sweep stub $id ref \"$ref\" names no #anchor — it must point at the artifact heading carrying this item's options[]" >&2
      return 1
    fi
    target="$dir/$file"
    [[ -n "$file" ]] || target="$artifact"           # anchor-only ref resolves to this artifact
    # The per-stage templates spell the `refs:` rows `.context/<artifact>-N.md#…`, two lines
    # under a stub written `<artifact>-N.md#…`, so a ref that repeats the artifact's own
    # directory names the same file — not a nested one — and must not fail as missing.
    if [[ ! -f "$target" && "$file" == "$(basename "$dir")/"* ]]; then
      target="$dir/${file#*/}"
    fi
    if [[ ! -f "$target" ]]; then
      echo "fail: sweep stub $id ref \"$ref\" names a file that does not exist: $target" >&2
      return 1
    fi
    if ! grep -qE "^## +${anchor}[[:space:]]*\$" "$target"; then
      echo "fail: sweep stub $id ref \"$ref\" is dangling — $(basename "$target") has no '## $anchor' heading, so the FN gate has no options[] to render" >&2
      return 1
    fi
  done <<< "$rows"
  return 0
}

# A resolvable anchor proves only that the heading exists. What sits under it is what the
# FN gate renders, and a bare status note ("q", "done", "see below") renders as a prompt with
# nothing to pick, so the gate either skips the item or invents options. The item block must
# carry at least two options[] (`label:` entries). An escalate item is asked rather than chosen,
# so it may instead stand on an explicit question ending in `?`.
#
# The block runs from the first line in the anchor section naming the id to the next line
# that starts another item (a line opening on a different sw- id, optionally after `-`, `{`
# or `id:`), or the next `## ` heading. A mere mention such as "follow-up to sw-PL0-1" in a
# summary does not end the block. A missing file or heading is
# check_sweep_ref_anchor's failure and is skipped here so one slip yields one line. Unlike that
# check, every stub is reported: Step B.1 re-dispatches with the `fail:` lines verbatim, and a
# stage fixing one note at a time costs a round each.
check_sweep_item_body() {
  local artifact="$1" fmfile="$2"
  local dir rows flags line id ref file anchor target cls verdict where rc=0
  dir=$(dirname "$artifact")
  _sweep_load "$fmfile" || return 1
  rows=$(_sweep_rows STUB)
  flags=$(_sweep_rows FLAGS)
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    id="${line%% *}"
    ref="${line#* }"
    [[ -n "$ref" && "$ref" != "$id" ]] || continue
    anchor="${ref##*#}"
    file="${ref%%#*}"
    [[ -n "$anchor" && "$anchor" != "$ref" ]] || continue
    target="$dir/$file"
    [[ -n "$file" ]] || target="$artifact"
    if [[ ! -f "$target" && "$file" == "$(basename "$dir")/"* ]]; then
      target="$dir/${file#*/}"
    fi
    [[ -f "$target" ]] || continue
    cls=$(printf '%s\n' "$flags" | awk -v want="$id" '$1 == want { print $2; exit }')
    verdict=$(_sweep_item_verdict "$target" "$anchor" "$id" "$cls")
    where="'## $anchor' in $(basename "$target")"
    case "$verdict" in
      missing)
        echo "fail: sweep stub $id has no item under $where — write the full item there (summary, options[]) on lines that start by naming $id" >&2
        rc=1 ;;
      note)
        if [[ "$cls" == "escalate" ]]; then
          echo "fail: sweep stub $id is a status note, not a question — its item under $where has fewer than 2 options[] (label:) and no explicit question ending in '?'" >&2
        else
          echo "fail: sweep stub $id is a status note, not a question — its item under $where has fewer than 2 options[] (label:); only an escalate item may stand on a bare question" >&2
        fi
        rc=1 ;;
    esac
  done <<< "$rows"
  return $rc
}

# <file> <anchor> <id> <class> -> ok | note | missing | noanchor
# Values reach awk through ENVIRON, never `-v`: BSD awk rewrites backslash escapes in -v values.
# An id match must not run on into more digits, or sw-DV0-1 would claim sw-DV0-12's block.
_sweep_item_verdict() {
  _SIB_ANCHOR="$2" _SIB_ID="$3" _SIB_CLASS="$4" awk '
    function names_id(s,    i, nc) {
      while ((i = index(s, ID)) > 0) {
        nc = substr(s, i + length(ID), 1)
        if (nc !~ /[0-9]/) return 1
        s = substr(s, i + length(ID))
      }
      return 0
    }
    function starts_other(s,    t) {
      if (!match(s, /^[[:space:]]*(-[[:space:]]*)?([{][[:space:]]*)?(id:[[:space:]]*)?sw-[A-Z][A-Z][0-9]+-[0-9]+/)) return 0
      t = substr(s, RSTART, RLENGTH)
      sub(/.*sw-/, "sw-", t)
      return t != ID
    }
    BEGIN { ID = ENVIRON["_SIB_ID"]; ANCHOR = ENVIRON["_SIB_ANCHOR"]; CLS = ENVIRON["_SIB_CLASS"] }
    /^## / {
      insec = 0
      h = $0
      sub(/^## +/, "", h)
      sub(/[[:space:]]+$/, "", h)
      if (h == ANCHOR && !seen) { insec = 1; seen = 1 }
      next
    }
    !insec { next }
    inblk && starts_other($0) { inblk = 0 }
    !inblk && !found && names_id($0) { inblk = 1; found = 1 }
    inblk {
      s = $0
      labels += gsub(/(^|[^A-Za-z0-9_])label:/, "", s)
      if ($0 ~ /\?["\047]?[[:space:]]*$/ || $0 ~ /summary:[[:space:]]*"[^"]*\?"/ || $0 ~ /summary:[[:space:]]*\047[^\047]*\?\047/) q = 1
    }
    END {
      if (!seen) print "noanchor"
      else if (!found) print "missing"
      else if (labels >= 2) print "ok"
      else if (CLS == "escalate" && q) print "ok"
      else print "note"
    }
  ' "$1"
}

# state_unreadable_reason -> echoes why $STATE_ARG cannot be trusted, or nothing.
#
# Detection only. The two callers deliberately DISAGREE on the verdict — check_ar_ref
# downgrades to an advisory skip, check_sweep_ledger fails outright — so the verdict stays
# at the call site and only the three ways a ledger can be unusable are shared.
state_unreadable_reason() {
  if [[ ! -f "$STATE_ARG" ]]; then
    printf 'state file not found: %s' "$STATE_ARG"
  elif ! command -v jq > /dev/null 2>&1; then
    printf 'jq unavailable; cannot read %s' "$STATE_ARG"
  elif ! jq empty "$STATE_ARG" > /dev/null 2>&1; then
    printf 'state file is not valid JSON: %s' "$STATE_ARG"
  fi
}

# report_task_id_fallback <fmfile> <artifact> -> stderr note only; always returns 0.
#
# On a split stage an artifact without handoff.task_id leaves check_sweep_ledger to infer
# its task from stub prefixes, which cannot see a stub-less stream's items. That is worth
# saying, but it is not a sweep verdict: the sweep checks have no advisory tier, so the note
# lives here and the exit code stays whatever the checks decide.
report_task_id_fallback() {
  local fmfile="$1" artifact="${2:-}" stage_code stage_tasks
  [[ -r "$STATE_ARG" ]] || return 0
  [[ -z "$(corpflow_fm_field "$fmfile" task_id)" ]] || return 0
  stage_code=$(yq eval '.handoff.stage // ""' "$fmfile" 2> /dev/null || printf '')
  [[ -n "$stage_code" && "$stage_code" != "null" ]] || return 0
  stage_tasks=$(jq -r --arg st "$stage_code" \
      '(.tasks // {}) | keys[] | select(test("^" + $st + "[0-9]+$"))' \
    "$STATE_ARG" 2> /dev/null | grep -c . || true)
  if [[ "${stage_tasks:-0}" -ge 2 ]]; then
    echo "warn: $(basename "${artifact:-the artifact}") omits handoff.task_id while stage $stage_code has $stage_tasks tasks — parity falls back to stub prefixes" >&2
  fi
  return 0
}

# Sweep-stub ledger parity. The frontmatter stub and facts.open_questions[] are two
# transports with two writers and no derivation between them, so a stage that writes
# the stub but omits it from `state-patch.sh --facts` produces a schema-valid artifact
# whose sweep never reaches the FN gate. Fires only with --state, like check_ar_ref.
# No warn arm: the sweep obligation is strict (stage-contracts.md § Closing Elicitation
# Sweep), so a dropped item fails rather than whispers.
#
# An unreadable --state is a FAILURE here whenever there is a stub to compare, not a
# skip: check_ar_ref makes that case loud for DV only, and the other twelve stages
# would otherwise pass parity by never running it. An empty open_questions array leaves
# nothing to compare, so the check is silent.
check_sweep_ledger() {
  local fmfile="$1" artifact="${2:-}"
  local ids id missing unreadable divergent artname
  artname=$(basename "${artifact:-the artifact}")
  _sweep_load "$fmfile" || return 1
  ids=$(_sweep_rows STUB | sed 's/ .*//')

  # Reverse direction, scoped to THIS TASK. facts.open_questions[] accumulates across every
  # stage, and a split stage (DV0/DV1) shares one `.stage` slice, so the slice alone would
  # charge one stream with the other's stubs. The `sw-<TASK_ID>-` prefix is the task identity:
  # an artifact carrying stubs is charged only ids under its own prefixes; one with no stubs
  # is charged the stage slice only when tasks{} holds at most one task of that stage.
  #
  # Resolved items are excluded: a rework round re-emits only what is still open, so charging
  # it with an already-answered id fails the round, and Step B.1 reads that as missing_input
  # and burns a whole stage re-dispatch. A missing status reads as open, matching state-patch.sh.
  #
  # handoff.task_id, when set, IS the task identity and replaces the prefix inference: the
  # artifact is charged every open item of its own task whether or not it carries stubs. A
  # malformed id was already failed by validate_frontmatter, so it charges nothing here.
  local stage_code ledger_ids extra artifact_tasks stage_tasks task_id
  stage_code=$(yq eval '.handoff.stage // ""' "$fmfile" 2> /dev/null || printf '')
  task_id=$(corpflow_fm_field "$fmfile" task_id)
  ledger_ids=""
  if [[ -n "$stage_code" && "$stage_code" != "null" ]] && [[ -r "$STATE_ARG" ]] && [[ -n "$task_id" ]]; then
    if [[ "$task_id" =~ ^${stage_code}[0-9]+$ ]]; then
      # Only a readable `false` is a missing task; a ledger jq cannot parse is the unreadable
      # arm's to report, not a claim about tasks{}.
      local has_task
      has_task=$(jq -r --arg t "$task_id" '(.tasks // {}) | has($t)' "$STATE_ARG" 2> /dev/null || printf '')
      if [[ "$has_task" == "false" ]]; then
        echo "fail: handoff.task_id $task_id is not in tasks{}" >&2
        return 1
      fi
      # A sibling's valid id would charge that sibling's items and none of this stream's; a
      # stub under another prefix is the one trace of that mislabel the artifact itself holds.
      local foreign='' fid=''
      foreign=$(printf '%s\n' "$ids" | sed -n 's/^sw-\([A-Z][A-Z][0-9][0-9]*\)-[0-9][0-9]*$/& \1/p' \
        | awk -v t="$task_id" '$2 != t { print $1 }')
      if [[ -n "$foreign" ]]; then
        while IFS= read -r fid; do
          echo "fail: sweep stub $fid does not belong to handoff.task_id $task_id — stamp the task that asked it" >&2
        done <<< "$foreign"
        return 1
      fi
      ledger_ids=$(jq -r --arg st "$stage_code" --arg t "$task_id" '
          (.facts.open_questions? // [])
          | map(select((.stage // "") == $st and (.status // "open") != "resolved"))
          | .[].id // empty
          | select(startswith("sw-" + $t + "-"))' \
        "$STATE_ARG" 2> /dev/null || printf '')
    fi
  elif [[ -n "$stage_code" && "$stage_code" != "null" ]] && [[ -r "$STATE_ARG" ]]; then
    stage_tasks=$(jq -r --arg st "$stage_code" \
        '(.tasks // {}) | keys[] | select(test("^" + $st + "[0-9]+$"))' \
      "$STATE_ARG" 2> /dev/null | grep -c . || true)
    artifact_tasks=$(printf '%s\n' "$ids" \
      | sed -n 's/^sw-\([A-Z][A-Z][0-9][0-9]*\)-[0-9][0-9]*$/\1/p' | sort -u)
    if [[ -n "$artifact_tasks" ]]; then
      ledger_ids=$(jq -r --arg st "$stage_code" \
          --argjson tasks "$(printf '%s\n' "$artifact_tasks" | jq -R . | jq -sc .)" '
          (.facts.open_questions? // [])
          | map(select((.stage // "") == $st and (.status // "open") != "resolved"))
          | .[].id // empty
          | select(. as $i | $tasks | any(. as $t | $i | startswith("sw-" + $t + "-")))' \
        "$STATE_ARG" 2> /dev/null || printf '')
    else
      if [[ "${stage_tasks:-0}" -le 1 ]]; then
        ledger_ids=$(jq -r --arg st "$stage_code" '
            (.facts.open_questions? // [])
            | map(select((.stage // "") == $st and (.status // "open") != "resolved"))
            | .[].id // empty' \
          "$STATE_ARG" 2> /dev/null || printf '')
      fi
    fi
  fi

  # An empty artifact stub block used to be a silent pass — the one shape that hides a whole
  # stage's sweep. It is only a pass when the ledger holds nothing for this stage either.
  if [[ -z "$ids" ]] && [[ -z "$ledger_ids" ]]; then
    return 0
  fi

  if [[ -n "$ledger_ids" ]]; then
    extra=$(printf '%s\n' "$ledger_ids" | grep -vxF -f <(printf '%s\n' "$ids") 2> /dev/null || true)
    if [[ -n "$extra" ]]; then
      while IFS= read -r id; do
        [[ -n "$id" ]] || continue
        echo "fail: sweep stub $id is in ledger, not in frontmatter — facts.open_questions[] carries it for stage $stage_code but $artname does not. Re-emit it in the artifact's open_questions[], or the two transports disagree about what this stage asked" >&2
      done <<< "$extra"
      return 1
    fi
  fi

  [[ -n "$ids" ]] || return 0

  unreadable=$(state_unreadable_reason)
  if [[ -n "$unreadable" ]]; then
    echo "fail: sweep ledger parity cannot be verified for $(echo "$ids" | tr '\n' ' ')— $unreadable" >&2
    return 1
  fi

  # One jq set difference, not one membership probe per id: the ledger is re-read and
  # re-parsed by every probe, and a sweep of any size pays that per item.
  #
  # 2>&1 into the same capture, like _sweep_yq: a ledger whose open_questions is a string
  # or a list of non-objects aborts jq mid-filter, and treating that exit as "nothing
  # missing" would pass the gate on exactly the shapes it exists to catch.
  # The ledger is not the whole record: the per-task question clamp spills unresolved evictions to
  # `open-questions-<run_index>.jsonl` (AD-4), and an item that legitimately reached the FN
  # gate through the spill must not read here as a dropped stub.  The path derives from the
  # ledger's own run_index — never guessed — and a MISSING spill contributes the empty set,
  # which is exactly today's behaviour for every run whose sweep never overflowed.
  local spill
  spill="$(dirname "$STATE_ARG")/open-questions-$(jq -r '.run_index // 0' "$STATE_ARG" 2> /dev/null || printf '0').jsonl"
  if [[ -e "$spill" ]] && ! jq -e -s 'type == "array"' "$spill" > /dev/null 2>&1; then
    # A spill that exists but cannot be parsed is a FAILURE, not an empty set: silently
    # treating a corrupt overflow file as "no items" restores the precise loss this check
    # exists to catch, and does it only in the runs that overflowed.
    echo "fail: sweep ledger parity cannot be verified for $(echo "$ids" | tr '\n' ' ')— spill file $spill is not readable as JSON lines" >&2
    return 1
  fi
  [[ -e "$spill" ]] || spill="/dev/null"

  if ! missing=$(printf '%s\n' "$ids" | jq -r -R -s --slurpfile st "$STATE_ARG" --rawfile sp "$spill" '
      ( ( ($st[0].facts.open_questions? // []) | map(.id) )
        + ( $sp | split("\n") | map(select(length > 0) | fromjson.id) ) ) as $have
      | split("\n") | map(select(length > 0 and . != "null"))
      | . - $have | .[]' 2>&1); then
    echo "fail: sweep ledger parity cannot be verified for $(echo "$ids" | tr '\n' ' ')— facts.open_questions in $STATE_ARG could not be read as an array of stubs: ${missing%%$'\n'*}" >&2
    return 1
  fi
  if [[ -n "$missing" ]]; then
    while IFS= read -r id; do
      [[ -n "$id" ]] || continue
      echo "fail: sweep stub $id is in the frontmatter but not in facts.open_questions[] — pass it in the state-patch.sh --facts payload, or the FN gate never sees it" >&2
    done <<< "$missing"
    return 1
  fi

  # Stub parity, not just id parity. The arm above catches an item that never reached the
  # ledger; this one catches an item that reached it carrying DIFFERENT values. Same two
  # transports, same absence of any derivation between them, and until this existed the only
  # cross-check was on id — so a stub saying `blocks_next_stage: false` beside a ledger entry
  # saying `true` validated clean, and the orchestrator read the ledger, joined raise-only and
  # held a boundary gate for an item its own author had marked non-blocking (OV-183).
  #
  # This is deliberately NOT a join: the two copies have ONE author, so a disagreement is a
  # defect and not a lattice (`skills/shared/stage-contracts.md § Self-labels raise, never
  # lower`). The harness refuses and names both values; reconciling is the agent's job, because
  # a harness that picked a winner would be guessing which copy the author meant.
  #
  # An absent flag normalises to `false` on BOTH sides, its documented default, so a legacy
  # ledger entry written before the field was required does not read as divergence.
  #
  # The LIVE ledger only — deliberately not the spill, which the id arm above does read. The
  # spill is an append-only record of what was evicted, never rewritten, so a re-emitted stub
  # legitimately disagrees with its own older eviction line; comparing against it would fail
  # rework rounds for doing exactly what the carry-forward contract asks. An item that exists
  # only in the spill has no live row to diverge from, so nothing is lost by skipping it.
  divergent=$(_sweep_rows FLAGS)
  [[ -n "$divergent" ]] || return 0
  # Every emitted field is non-empty — an absent ledger class prints as "(absent)" rather
  # than "" — because tab is IFS whitespace, so `read` would collapse an empty column and
  # silently shift every value after it into the wrong variable.
  if ! divergent=$(printf '%s\n' "$divergent" | jq -r -R -s --slurpfile st "$STATE_ARG" '
      def _norm: { class: (if (.class // "") == "" then "(absent)" else .class end),
                   flag: ((.blocks_next_stage // false) | tostring) };
      ( ( ($st[0].facts.open_questions? // []) | map({ key: .id, value: _norm }) )
        | from_entries ) as $have
      | split("\n") | map(select(length > 0))
      | map((. / " ") as $c | { id: $c[0], class: $c[1], flag: $c[2] })
      | map(select($have[.id] != null))
      | map(select(.class != $have[.id].class or .flag != $have[.id].flag))
      | .[] | [.id, .class, .flag, $have[.id].class, $have[.id].flag] | @tsv' 2>&1); then
    echo "fail: sweep stub parity cannot be verified for $(echo "$ids" | tr '\n' ' ')— facts.open_questions in $STATE_ARG could not be read as an array of stubs: ${divergent%%$'\n'*}" >&2
    return 1
  fi
  [[ -n "$divergent" ]] || return 0
  local fid fclass fflag lclass lflag
  while IFS=$'\t' read -r fid fclass fflag lclass lflag; do
    [[ -n "$fid" ]] || continue
    if [[ "$fflag" != "$lflag" ]]; then
      echo "fail: sweep stub $fid disagrees across transports — blocks_next_stage is $fflag in $artname but $lflag in facts.open_questions[]. Reconcile both to the intended value (the artifact is the author's copy); do not leave them divergent" >&2
    fi
    if [[ "$fclass" != "$lclass" ]]; then
      echo "fail: sweep stub $fid disagrees across transports — class is $fclass in $artname but $lclass in facts.open_questions[]. Reconcile both to the intended value (the artifact is the author's copy); do not leave them divergent" >&2
    fi
  done <<< "$divergent"
  return 1
}

# files_touched shape: at most FILES_TOUCHED_MAX paths, and any overflow declared by exactly
# one trailing `+ <count> more` marker. A list longer than the cap with no marker is the
# ad-hoc truncation this convention exists to replace — it reads as a complete set.
check_files_touched_cap() {  # <fmfile> <stage> <artname>
  local fmfile="$1" stage="$2" artname="$3"
  local entries markers paths last
  entries=$(yq eval '(.handoff.files_touched // []) | .[]' "$fmfile" 2> /dev/null || printf '')
  [[ -n "$entries" ]] || return 0
  markers=$(printf '%s\n' "$entries" | grep -cE '^\+ [0-9]+ more$' || true)
  paths=$(printf '%s\n' "$entries" | grep -vcE '^\+ [0-9]+ more$' || true)
  last=$(printf '%s\n' "$entries" | tail -1)

  if [[ "$markers" -gt 1 ]]; then
    echo "fail: stage=$stage files_touched carries ${markers} '+ <count> more' markers in $artname — emit exactly one, last" >&2
    return 1
  fi
  if [[ "$markers" -eq 1 ]] && ! printf '%s' "$last" | grep -qE '^\+ [0-9]+ more$'; then
    echo "fail: stage=$stage files_touched has a '+ <count> more' marker that is not the last entry in $artname" >&2
    return 1
  fi
  if [[ "$paths" -gt "$FILES_TOUCHED_MAX" ]]; then
    echo "fail: stage=$stage files_touched lists ${paths} paths > FILES_TOUCHED_MAX=${FILES_TOUCHED_MAX} in $artname — emit the first ${FILES_TOUCHED_MAX} plus one '+ <count> more' marker, and mark the body section carrying the full set authoritative in the same edit" >&2
    return 1
  fi
  return 0
}

# key_decisions vs the body: the same id must not carry two different summaries. Until this
# existed the harness read the frontmatter slice alone, so a decision could be restated in the
# body with a different meaning and every downstream reader picked whichever copy it happened
# to open. Overlap-based, not equality: the frontmatter summary is a ≤160-char precis of a
# longer body entry, so a shared-vocabulary test is what distinguishes a precis from a
# contradiction. Silent when an id has no body entry — not every decision is restated.
check_decision_divergence() {  # <artifact> <fmfile> <stage>
  local artifact="$1" fmfile="$2" stage="$3"
  local rows body id fsum bsum artname
  artname=$(basename "$artifact")
  rows=$(yq eval '(.handoff.key_decisions // []) | .[] | ((.id // "") + "\t" + (.summary // ""))' \
    "$fmfile" 2> /dev/null || printf '')
  [[ -n "$rows" ]] || return 0
  body=$(mktemp -t handoff-body-XXXXXX)
  awk '/^---$/ { c++; next } c >= 2' "$artifact" > "$body"

  local failed=0
  while IFS=$'\t' read -r id fsum; do
    [[ -n "$id" && -n "$fsum" ]] || continue
    # Table row `| id | summary | ...`, bullet `- **id** — summary`, or bullet
    # `- **id — summary.**` (the form this repo's architecture artifacts use, against which
    # the check was inert); first hit wins. The third arm anchors its trim to the known id
    # rather than to a separator class, because leftmost-longest would eat an em-dash that
    # belongs to the summary.
    bsum=$(awk -v id="$id" '
      $0 ~ ("^[[:space:]]*\\|[[:space:]]*(\\*\\*)?" id "(\\*\\*)?[[:space:]]*\\|") {
        n = split($0, f, "|"); if (n >= 4) { print f[3]; exit }
      }
      $0 ~ ("^[[:space:]]*[-*][[:space:]]+\\*\\*" id "\\*\\*") {
        line = $0; sub(/^[^*]*\*\*[^*]*\*\*[[:space:]]*[-—:]*[[:space:]]*/, "", line)
        print line; exit
      }
      $0 ~ ("^[[:space:]]*[-*][[:space:]]+\\*\\*" id "[[:space:]]*[-—:]") {
        line = $0
        sub(/^[^*]*\*\*/, "", line)
        sub("^" id "[[:space:]]*[-—:]+[[:space:]]*", "", line)
        sub(/\*\*[[:space:]]*$/, "", line)
        print line; exit
      }' "$body")
    [[ -n "$bsum" ]] || continue
    if ! awk -v a="$fsum" -v b="$bsum" '
      # Deliberately narrow. A frontmatter summary is a ≤160-char precis of a longer body
      # entry, so paraphrase is the NORM and an equality or high-overlap test would fail
      # honest artifacts — a boundary-blocking false failure is worse than the divergence it
      # would catch. Two shapes are reported, both of which mean the id resolves to two
      # different statements rather than two phrasings of one:
      #   1. the two share no significant vocabulary at all;
      #   2. both quote numbers and no number is common (a restated bound or count).
      # Filenames are stripped BEFORE the split: `<stage>-<run_index>.md` would otherwise
      # contribute its index as a bare digit, and arm 2 fires on an unmatched numeral. A
      # digit counts only as a whole whitespace-delimited word — `newest-8` is a name, not a
      # count. Residual: a bare `planning-0` carrying no extension survives the strip, and
      # the whole-word rule is what covers it.
      function harvest(x, W, D,   i, n, w, m, t, tok) {
        x = tolower(x)
        gsub(/[a-z0-9_\/.-]+\.(md|yml|yaml|json|jsonl|sh|bats|txt|log)/, " ", x)
        m = split(x, t, /[ \t\n]+/)
        for (i = 1; i <= m; i++) {
          tok = t[i]
          sub(/^[^a-z0-9]+/, "", tok)
          sub(/[^a-z0-9]+$/, "", tok)
          if (tok ~ /^[0-9]+$/) D[tok] = 1
        }
        n = split(x, w, /[^a-z0-9]+/)
        for (i = 1; i <= n; i++) {
          if (w[i] == "") continue
          if (w[i] ~ /^[0-9]+$/) continue
          if (length(w[i]) >= 4) W[w[i]] = 1
        }
      }
      BEGIN {
        harvest(a, AW, AD); harvest(b, BW, BD)
        for (k in AW) { ca++; if (k in BW) hit++ }
        for (k in BW) cb++
        for (k in AD) { na++; if (k in BD) dhit++ }
        for (k in BD) nb++
        if (ca > 0 && cb > 0 && hit == 0) exit 1
        if (na > 0 && nb > 0 && dhit == 0) exit 1
        exit 0
      }'; then
      echo "fail: decision $id disagrees across transports — frontmatter says \"${fsum}\" but the ${artname} body says \"${bsum}\". Reconcile both to one statement; a reader resolving the id must not get two answers" >&2
      failed=1
    fi
  done <<< "$rows"
  rm -f "$body"
  return "$failed"
}

# A DV stage reporting zero executed tests must say whether the suite COMPILES.
# Zero is a legal outcome; being unable to tell it from "never built" is not — that
# ambiguity let a platform reach a merge decision with no test ever run, while four
# stages escalated with remedies aimed at a control that was not the one refusing
# them. Compilation is answerable WITHOUT test-execution authority, which is why it
# is asked of the stage that was denied.
#
# Blocking, not warn-only: unlike the AR-ref arm this is not a rollout, and a
# missing value is exactly the state the check exists to refuse.
# Contract: stage-contracts.md#tpl-dv § Zero executed tests must say whether the
# suite compiles.
check_test_evidence() {
  local fmfile="$1" executed compiles

  executed=$(yq eval '.handoff.tests_executed // ""' "$fmfile")
  [[ "$executed" == "null" ]] && executed=""
  # An absent value is the required-field loop's business and a non-numeric one is
  # check_summary_line's, which blocks it for both DV and QA: reporting it twice
  # would send the stage two failures for one slip.
  case "$executed" in
    '' | *[!0-9]*) return 0 ;;
  esac
  [[ "$executed" -eq 0 ]] || return 0

  # NOT `// ""`: yq's alternative operator treats a literal `false` as falsy and
  # hands back the default, which would silently turn one of the three legal
  # answers into "absent" — the exact ambiguity this check exists to refuse.
  compiles=$(yq eval '.handoff.test_suite_compiles' "$fmfile")
  [[ "$compiles" == "null" ]] && compiles=""
  case "$compiles" in
    true | false | unknown) return 0 ;;
    "")
      echo "fail: stage=DV reports tests_executed: 0 with no test_suite_compiles — add test_suite_compiles: true|false|unknown. It is checkable without test-execution authority, and it is what separates gate-blocked from never-built" >&2
      return 1 ;;
    *)
      echo "fail: stage=DV test_suite_compiles is \"$compiles\" — expected true, false or unknown" >&2
      return 1 ;;
  esac
}

# AD-4 — a non-zero execution count is checked against the words the runner used.
# Until this arm existed the count was checked against NOTHING: check_test_evidence
# returns early unless it is zero, so `tests_executed: 4000` validated clean for a
# stage that ran nothing, which is the same absence-reads-as-success defect the
# zero arm above closes from the other side.
#
# Two tiers, because "verbatim" is not mechanically decidable. Tier 1 asks only
# that the excerpt EXIST somewhere durable — the artifact body, or a .context/logs/
# capture the artifact names — which is platform-neutral and decidable. Tier 2, the
# count-token match, is warn-only: it holds for bats and pytest but not for every
# Gradle or Xcode formatter this cross-platform contract also governs, and a check
# that guesses wrong fails honest stages. Same posture as ar_ref_violation above.
#
# DV and QA only: they are the two stages holding test-execution authority, so no
# other stage can produce the line honestly.
# Contract: stage-contracts.md#tpl-dv § Verification Command carries the runner's
# verbatim summary line.
check_summary_line() {  # <artifact> <fmfile> <stage>
  local artifact="$1" fmfile="$2" stage="$3" executed line

  executed=$(yq eval '.handoff.tests_executed // ""' "$fmfile")
  [[ "$executed" == "null" ]] && executed=""
  # Absence is the required-field loop's business — it is the one shape that loop
  # decides. A PRESENT non-numeric value is this arm's: the loop tests only that a
  # value is there, so delegating it let `tests_executed: "1841 (scoped)"` skip every
  # tier below and validate clean for a stage that ran nothing.
  case "$executed" in
    '') return 0 ;;
    *[!0-9]*)
      echo "fail: stage=$stage tests_executed is \"$executed\" — a count is a whole number and nothing else; a value carrying units, a range or a parenthetical skips the whole evidence contract below it" >&2
      return 1 ;;
  esac
  [[ "$executed" -gt 0 ]] || return 0

  # NOT `// ""`: the alternative operator cannot tell an absent field from an
  # empty one, and those two get different messages because they are different
  # mistakes — nothing written versus a placeholder left behind.
  line=$(yq eval '.handoff.test_summary_line' "$fmfile")

  if [[ "$line" == "null" ]]; then
    echo "fail: stage=$stage reports tests_executed: $executed with no test_summary_line — copy the runner's own summary line in verbatim; it is the only record downstream that a count was ever observed" >&2
    return 1
  fi
  if [[ -z "${line//[[:space:]]/}" || "$line" != *[0-9]* ]]; then
    echo "fail: stage=$stage test_summary_line carries no digit: \"$line\" — a runner's summary line reports numbers; a label is not evidence" >&2
    return 1
  fi

  if ! summary_line_corroborated "$artifact" "$line"; then
    echo "fail: stage=$stage test_summary_line is uncorroborated: \"$line\" appears neither in $(basename "$artifact") nor in a .context/logs/ capture it names — an excerpt nobody can check is the unverifiable claim this arm refuses" >&2
    return 1
  fi

  if ! printf '%s' "$line" | grep -qE "(^|[^0-9])${executed}([^0-9]|\$)"; then
    echo "warn: stage=$stage tests_executed: $executed is not a whole-number token of test_summary_line \"$line\" — the excerpt is corroborated, the count is not" >&2
    summary_line_audit "$artifact" "$stage" "$executed" "$line"
  fi
  return 0
}

# The excerpt must exist in something durable. Body first; then any .context/logs/
# path the body names, glob included — a scoped bats run is captured as
# `dv0-bats-*.log`, and a stage that names its capture that way has still put the
# line somewhere a reader can open.
summary_line_corroborated() {  # <artifact> <line>
  local artifact="$1" line="$2" body dir cand path f
  body=$(awk 'NR==1 && /^---[[:space:]]*$/ { fm=1; next }
              fm==1 && /^---[[:space:]]*$/ { fm=0; next }
              fm!=1' "$artifact")
  if printf '%s\n' "$body" | grep -Fq -- "$line"; then
    return 0
  fi
  dir=$(cd "$(dirname "$artifact")" && pwd)
  while IFS= read -r cand; do
    [[ -n "$cand" ]] || continue
    # Three resolutions, because an artifact names its capture from the repo root
    # as often as from beside itself, and neither spelling is wrong.
    for path in "$cand" "$dir/${cand#.context/}" "$dir/../$cand"; do
      for f in $path; do
        [[ -f "$f" ]] || continue
        if grep -Fq -- "$line" "$f"; then
          return 0
        fi
      done
    done
  done < <(printf '%s\n' "$body" | grep -oE '[A-Za-z0-9._/*-]*logs/[A-Za-z0-9._/*-]+' | sort -u)
  return 1
}

# Warn tier only. The row is evidence that the softer half of the contract fired,
# so a later reader can tell a formatter this arm cannot parse from a count nobody
# checked. It rides the shared appender rather than a second writer, and a missing
# library degrades to silence: an audit row is never a gate.
summary_line_audit() {  # <artifact> <stage> <executed> <line>
  local artifact="$1" stage="$2" executed="$3" line="$4" lib
  lib="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../shared/lib/audit-lib.sh"
  [[ -r "$lib" ]] || return 0
  # shellcheck source=../../shared/lib/audit-lib.sh
  . "$lib" 2> /dev/null || return 0
  command -v corpflow_audit_row > /dev/null 2>&1 || return 0
  corpflow_audit_row --file "$(dirname "$artifact")/logs/audit.jsonl" \
    --actor "handoff-harness" --action "count_corroboration" --result "degraded" \
    --subject "$stage" --meta-kv "tests_executed=$executed" \
    --meta-kv "summary_line=$line" || return 0
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

# Runtime truth for "did AR run" is the tasks.AR<N> entry, never the presence of
# an architecture file — AR is optional and PL0 decides it per run.
check_ar_ref() {
  local artifact="$1" fmfile="$2"

  # A state file we cannot read is NOT evidence that AR did not run. Saying so
  # out loud keeps the two cases distinguishable once --strict becomes the
  # default, where a silent skip would be a false negative on every jq-less host.
  local unreadable
  unreadable=$(state_unreadable_reason)

  if [[ -n "$unreadable" ]]; then
    ar_ref_violation "AR-ref check skipped — $unreadable" || return 1
    return 0
  fi

  local ar_present=0
  # Any AR instance counts: a split or renumbered AR lands as AR1/AR2, and the
  # gate asks "did AR run", not "did AR0 run".
  if jq -e '[(.tasks // {}) | keys[] | select(test("^AR[0-9]+$"))] | length > 0' "$STATE_ARG" >/dev/null 2>&1; then
    ar_present=1
  fi

  local ref
  ref=$(yq eval '.handoff.refs.decisions // .handoff.architecture.ref // ""' "$fmfile")
  [[ "$ref" == "null" ]] && ref=""

  if [[ "$ar_present" -eq 0 ]]; then
    if [[ -n "$ref" ]] && printf '%s' "$ref" | grep -qE '^architecture-'; then
      echo "warn: DV references $ref but state has no tasks.AR<N> entry" >&2
    fi
    return 0
  fi

  if [[ -z "$ref" ]]; then
    ar_ref_violation "AR completed but DV refs.decisions missing" || return 1
    return 0
  fi

  # Two different defects shared one message, so neither said what to do. A malformed shape
  # is not a dangling reference: the commonest form by far is a `.context/` prefix, which
  # every SIBLING ref in this block carries, so it is a reasonable thing to write and worth
  # naming outright rather than leaving to be inferred from a regex nobody is shown.
  if ! printf '%s' "$ref" | grep -qE "$ARCH_REF_RE"; then
    ar_ref_violation "DV architecture ref malformed: $ref (expected a bare 'architecture-<N>.md#<anchor>' relative to the artifact — no .context/ prefix, unlike the sibling refs in this block)" || return 1
    return 0
  fi

  local reffile
  reffile="${ref%%#*}"
  if [[ ! -f "$(dirname "$artifact")/$reffile" ]]; then
    ar_ref_violation "DV architecture ref dangling: $reffile names no file next to $(basename "$artifact")" || return 1
    return 0
  fi

  return 0
}

validate_frontmatter() {
  local f="$1"
  [[ -f "$f" ]] || { echo "frontmatter: file not found: $f" >&2; return 1; }

  # Raw bytes first: awk and yq must never see a NUL, which each may truncate at silently.
  local cbrc=0 cbhits cbline cbhex cboff
  cbhits=$(cb_scan_file "$f" "$f") || cbrc=$?
  if [[ "$cbrc" -eq 1 ]]; then
    while IFS= read -r cbline; do
      [[ -n "$cbline" ]] || continue
      cbhex="${cbline##*:}"
      cboff="${cbline%:*}"
      cboff="${cboff##*:}"
      echo "fail: control byte $cbhex at byte offset $cboff in $f — rewrite it as text" >&2
    done <<< "$cbhits"
    return 1
  elif [[ "$cbrc" -ne 0 ]]; then
    echo "fail: cannot scan $f for control bytes" >&2
    return 1
  fi

  # Extract just the frontmatter block (between first two ^---$ lines) to a tmp,
  # so yq can parse it as pure YAML (the rest of the markdown is not YAML).
  local fmfile
  fmfile=$(mktemp -t handoff-fm-XXXXXX)
  # One cleanup for fourteen exits. Every failure arm below used to carry its own
  # `rm -f`, so a new arm leaked the temp file unless its author noticed. RETURN
  # traps are not inherited by called functions without `set -T`, which this
  # script does not set, so the checks invoked below cannot fire it early.
  #
  # The path is baked in at trap-set time, exactly as validate_state's sibling
  # trap does it, because a RETURN trap stays installed after the function
  # returns and fires again when a sourced file completes — by which time the
  # local is gone and `"$fmfile"` would be an unbound-variable error under
  # `set -u`. Baked, that late firing is a no-op on an already-removed path.
  # shellcheck disable=SC2064  # expansion at set time is the point, see above
  trap "rm -f '$fmfile'" RETURN
  # One extractor, shared with state-patch.sh: the two used different awk programs, and an
  # artifact carrying a second `---` in its body was sliced differently by each.
  corpflow_fm_block "$f" > "$fmfile" 2> /dev/null || true
  if [[ ! -s "$fmfile" ]]; then
    echo "fail: missing frontmatter block in $f" >&2
    return 1
  fi

  # The shape gate, also shared. Checked before the yq branch below so the flat shape is
  # refused identically with or without yq on the host — it is the divergence that let an
  # artifact be unreadable here and still write a healthy ledger row.
  if ! corpflow_fm_has_handoff "$fmfile"; then
    echo "fail: no handoff: block" >&2
    return 1
  fi

  command -v yq >/dev/null 2>&1 || {
    echo "frontmatter: yq required for full validation; running grep-only fallback" >&2
    head -1 "$f" | grep -q '^---$' || { echo "fail: missing leading ---" >&2; return 1; }
    return 0
  }

  local stage
  stage=$(yq eval '.handoff.stage // ""' "$fmfile")
  [[ -n "$stage" && "$stage" != "null" ]] || { echo "fail: no stage" >&2; return 1; }

  local req
  req=$(required_for "$stage")
  [[ -n "$req" ]] || { echo "fail: unknown stage $stage" >&2; return 1; }

  # Everything above is the fail-fast prologue: each of its checks makes every later check
  # meaningless, so running on would emit noise rather than information. Everything below
  # collects — an author handed one failure and then a second on the re-run pays a boundary
  # round per defect. Each check keeps its own message text and its own line: Step B.1
  # re-dispatches with the `fail:` line verbatim and the orchestrator greps for one naming a
  # sweep id, so aggregating them into a single line would break that reader.
  local rc=0

  local field
  for field in $req; do
    local val
    val=$(yq eval ".handoff.${field} // \"\"" "$fmfile")
    if [[ -z "$val" || "$val" == "null" ]]; then
      echo "fail: stage=$stage missing required field: $field" >&2
      rc=1
    fi
  done

  local task_id
  task_id=$(corpflow_fm_field "$fmfile" task_id)
  if [[ -n "$task_id" ]] && ! [[ "$task_id" =~ ^${stage}[0-9]+$ ]]; then
    echo "fail: handoff.task_id '$task_id' is not a task id of stage $stage" >&2
    rc=1
  fi

  if [[ "$stage" == "DV" && -n "$STATE_ARG" ]]; then
    check_ar_ref "$f" "$fmfile" || rc=1
  fi

  if [[ "$stage" == "DV" ]]; then
    check_test_evidence "$fmfile" || rc=1
  fi

  if [[ "$stage" == "DV" || "$stage" == "QA" ]]; then
    check_summary_line "$f" "$fmfile" "$stage" || rc=1
  fi

  check_files_touched_cap "$fmfile" "$stage" "$(basename "$f")" || rc=1
  check_decision_divergence "$f" "$fmfile" "$stage" || rc=1
  local stub_shape_ok=1
  check_sweep_stub_shape "$fmfile" || { rc=1; stub_shape_ok=0; }
  check_sweep_ref_anchor "$f" "$fmfile" || rc=1
  check_sweep_item_body "$f" "$fmfile" || rc=1
  check_empty_sweep_prose "$f" "$fmfile" || rc=1
  if [[ -n "$STATE_ARG" ]]; then
    report_task_id_fallback "$fmfile" "$f"
    check_sweep_ledger "$fmfile" "$f" || rc=1
  fi

  # Token budget (AD-2). The budget constrains DISCRETIONARY prose — summary,
  # next_stage_focus, decision bodies — so the mandatory open_questions stubs are excluded
  # from it: counting them made the check measure the wrong thing and rewarded a stage for
  # asking fewer questions, which is the incentive AC-8 names.
  #
  #   discretionary = toks(frontmatter) - min( toks(stub block), 4 x 16 )
  #   fail  when discretionary > 200
  #   warn  when total        > 264      # advisory; keeps the real absolute cost visible
  #
  # The exclusion caps at four stubs' worth (12 measured tokens plus a third of headroom),
  # so it cannot be gamed by inflating `ref` strings or emitting extra stubs: 264 is a
  # deterministic ceiling. check_sweep_stub_shape has already run above, so only
  # shape-valid stubs are ever excluded — that ordering is what makes the cap safe.
  #
  # Under collect-all the stub-shape check may have FAILED above, and the exclusion is only
  # sound once it passes. The arm then counts the stubs in full and says so, rather than
  # skipping: a skip lets a broken stub hide an over-budget block for a round, which is the
  # cost collect-all exists to remove.
  local tcount stubtoks discretionary budget_note=""
  tcount=$(toks "$fmfile")
  if [[ "$stub_shape_ok" -eq 1 ]]; then
    stubtoks=$(toks_open_questions_block "$fmfile")
    [[ "$stubtoks" -le 64 ]] || stubtoks=64
  else
    stubtoks=0
    budget_note="(stub-shape invalid: sweep stubs counted in full) "
  fi
  discretionary=$((tcount - stubtoks))
  # The advisory line is emitted BEFORE the failure, not after: 264 is exactly 200 plus the
  # 64-token exclusion cap, so every artifact over the ceiling is already over the budget and
  # a warn placed after the `return 1` could never print. Ordering it first is what keeps the
  # absolute cost visible on the report that matters — the failing one.
  if [[ "$tcount" -gt 264 ]]; then
    echo "warn: stage=$stage frontmatter ${tcount} tokens > 264 absolute ceiling" >&2
  fi
  if [[ "$discretionary" -gt 200 ]]; then
    echo "fail: ${budget_note}stage=$stage frontmatter ${discretionary} discretionary tokens > 200 budget (${tcount} total - ${stubtoks} sweep-stub tokens excluded)" >&2
    rc=1
  fi

  [[ "$rc" -eq 0 ]] || return "$rc"
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
  [[ "$v" == "2" ]] || { echo "fail: version != 2 (got '$v')" >&2; return 1; }
  jq -e 'has("worktask_id") and has("plan_file") and has("platform") and has("tasks") and has("facts") and has("handoffs")' "$f" >/dev/null \
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
  local patch='{"tasks":{"PL0":{"status":"completed"}}}'
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
  "version": 2,
  "worktask_id": "harness-demo",
  "plan_file": ".context/planning-0.md",
  "platform": "all",
  "tasks": {
    "PL0": {"status":"completed","verdict":"ok"},
    "AR0": {"status":"completed","verdict":"ok"},
    "TL0": {"status":"completed","verdict":"ok"}
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
    "PL→AR0": "9-stage, complexity 38. ref: planning-0.md#requirements",
    "AR→TL0": "Schemas designed, atomic write strategy. ref: architecture.md#decisions",
    "TL→DV0": "24-file fan-out, 8 batches. ref: coordination.md#fan-out"
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
  open_questions: []
  refs: { plan: planning-0.md#requirements }
---

# Planning

## requirements

## elicitation-sweep

nothing to ask

EOF
  # Pad with synthetic body to make the baseline-mode reading expensive.
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
  open_questions:
    - { id: sw-AR0-1, class: decision, ref: "architecture.md#elicitation-sweep", blocks_next_stage: false }
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

## elicitation-sweep

- id: sw-AR0-1
  summary: "Which language do the hooks use?"
  options:
    - { label: "Bash", detail: "Matches every existing hook", recommended: true }
    - { label: "Python", detail: "Richer parsing, new runtime dependency" }
EOF

  cat > "$d/.context/development.md" <<'EOF'
---
handoff:
  stage: DV
  verdict: ok
  summary: "Implemented."
  tests_executed: 12
  test_summary_line: "12 tests, 0 failures"
  files_touched: [a.md, b.md]
  next_stage_focus: "DR reviews"
  open_questions: []
  refs: { dev: development.md#files-changed }
---

# Development

## files-changed

## verification-command

12 tests, 0 failures

## elicitation-sweep

nothing to ask

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
  printf '%-6s | %12s | %10s | %10s\n' "stage" "baseline_tok" "new_tok" "reduction"
  printf '%s\n' "------+--------------+------------+-----------"

  # New mode prompt: state.json blob + targeted anchor headers (frontmatter only).
  local state_tok
  state_tok=$(toks "$d/.context/state.json")

  # Per-stage simulated reading scope.
  # POSIX-compatible: case-statement lookup instead of associative arrays.
  baseline_files_for() {
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
    local baseline=0 new=$state_tok
    local rel
    for rel in $(baseline_files_for "$stage"); do
      baseline=$(( baseline + $(toks "$d/$rel") ))
    done
    # New mode: state.json + ONLY the frontmatter block of the most relevant artifact
    for rel in $(new_files_for "$stage"); do
      local fm
      fm=$(awk '/^---$/{c++; if (c==2) exit} c>=1' "$d/$rel")
      new=$(( new + $(toks_str "$fm") ))
    done
    local reduction
    reduction=$(awk -v l="$baseline" -v n="$new" 'BEGIN { if (l==0) print "0%"; else printf "%.0f%%", (l-n)*100.0/l }')
    printf '%-6s | %12d | %10d | %10s\n' "$stage" "$baseline" "$new" "$reduction"

    # Threshold: ≥30% reduction (AC-12).
    local pct
    pct=$(awk -v l="$baseline" -v n="$new" 'BEGIN { if (l==0) print 0; else printf "%.0f", (l-n)*100.0/l }')
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

# ---------- main ----------
case "$MODE" in
  run)              run_token_count "${OUT_DIR:-}" ;;
  self-test)
    # Sourced HERE, not at the top: the harness is test code the validate paths
    # never run. `[ -r ]` first, not a bare `.`: sourcing a missing file with the
    # `.` builtin is a special-builtin error that exits the shell immediately,
    # bypassing an `if ! . …` guard entirely.
    SELFTEST_LIB_PATH="$(dirname "${BASH_SOURCE[0]}")/handoff-harness-selftest.sh"
    if [ -r "$SELFTEST_LIB_PATH" ]; then
      # shellcheck source=handoff-harness-selftest.sh
      # shellcheck disable=SC1090
      . "$SELFTEST_LIB_PATH"
    else
      printf >&2 'handoff-harness: self-test harness unreachable at %s — plugin install broken\n' \
        "$SELFTEST_LIB_PATH"
      exit 2
    fi
    self_test
    ;;
  validate-fm)      [[ -n "$ARG" ]] || usage; validate_frontmatter "$ARG" ;;
  validate-state)   [[ -n "$ARG" ]] || usage; validate_state "$ARG" ;;
  *) usage ;;
esac
