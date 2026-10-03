#!/usr/bin/env bash
# @description acceptance-check.sh — QA's acceptance-command gate.
#   DV lists, under its acceptance-commands anchor, one command per exact-output rule of the task
#   (CLI contract, output format, byte-level example). QA must execute every one and record it
#   under its own acceptance-commands anchor as `- exit=<n> <command>`. This check compares the
#   two lists and decides whether QA may pass: a contract nobody executed is the failure that
#   let a paraphrased board format ship while every unit test stayed green.
#
# Usage: acceptance-check.sh --qa <testing-N.md> --dv <development-N.md> [--dv <path>]...
#        acceptance-check.sh -h | --help
#
# @arg --dv <path>  A DV artifact, repeatable (one per DV ledger row).
# @arg --qa <path>  The QA artifact being written.
#
# Commands are read from the fenced block(s) under each `## acceptance-commands` heading of
# the DV artifacts: one command per non-blank line, `#` comment lines skipped. QA rows are the
# `- exit=<n> <command>` list items under the QA heading; text is compared after trimming
# surrounding whitespace, never executed — this script only reads.
#
# stdout: `acceptance: <executed>/<required> executed, <failed> failed` then one
#   `missing: <command>` or `failed: <command>` line per offending entry.
#
# @exitcode 0  Pass: every required command was executed with exit 0 (or none are required).
# @exitcode 1  No-go: a required command was not executed, or an executed one exited non-zero.
# @exitcode 2  Usage error, or an artifact could not be read.
#
# Minimum shell: bash 3.2+ (macOS default). Requires awk.

set -euo pipefail
IFS=$'\n\t'
export LC_ALL=C

usage_error() {
  printf >&2 'acceptance-check: %s\n' "$1"
  printf >&2 'usage: acceptance-check.sh --qa <testing-N.md> --dv <development-N.md> [--dv <path>]...\n'
  exit 2
}

QA=""
DV_LIST=""
while [ $# -gt 0 ]; do
  case "$1" in
    --qa) [ $# -ge 2 ] || usage_error "--qa needs a path"; QA="$2"; shift 2 ;;
    --dv) [ $# -ge 2 ] || usage_error "--dv needs a path"; DV_LIST="${DV_LIST}${2}"$'\n'; shift 2 ;;
    -h | --help) awk '/^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; exit 0 ;;
    *) usage_error "unknown argument: $1" ;;
  esac
done
[ -n "$QA" ] || usage_error "--qa is required"
[ -n "$DV_LIST" ] || usage_error "at least one --dv is required"

# Lines of the fenced blocks under `## acceptance-commands`, up to the next H2.
dv_commands() {
  awk '
    /^## / { on = ($0 ~ /^## acceptance-commands[[:space:]]*$/); fence = 0; next }
    !on { next }
    /^```/ { fence = !fence; next }
    fence {
      line = $0; sub(/^[[:space:]]+/, "", line); sub(/[[:space:]]+$/, "", line)
      if (line != "" && line !~ /^#/) print line
    }' "$1"
}

# `<exit>\t<command>` for each `- exit=<n> <command>` row under the QA heading.
qa_rows() {
  awk '
    /^## / { on = ($0 ~ /^## acceptance-commands[[:space:]]*$/); next }
    !on { next }
    /^[[:space:]]*[-*][[:space:]]+exit=[0-9]+[[:space:]]/ {
      line = $0; sub(/^[[:space:]]*[-*][[:space:]]+exit=/, "", line)
      code = line; sub(/[[:space:]].*$/, "", code)
      sub(/^[0-9]+[[:space:]]+/, "", line); sub(/[[:space:]]+$/, "", line)
      gsub(/^`|`$/, "", line)
      print code "\t" line
    }' "$1"
}

[ -r "$QA" ] || usage_error "cannot read QA artifact: $QA"
REQUIRED=""
while IFS= read -r dv; do
  [ -n "$dv" ] || continue
  [ -r "$dv" ] || usage_error "cannot read DV artifact: $dv"
  REQUIRED="${REQUIRED}$(dv_commands "$dv")"$'\n'
done <<< "$DV_LIST"
ROWS="$(qa_rows "$QA")"

required=0 executed=0 failed=0 report=""
while IFS= read -r cmd; do
  [ -n "$cmd" ] || continue
  required=$((required + 1))
  code=""
  while IFS=$'\t' read -r c row; do
    [ "$row" = "$cmd" ] && { code="$c"; break; }
  done <<< "$ROWS"
  if [ -z "$code" ]; then
    report="${report}missing: ${cmd}"$'\n'
  else
    executed=$((executed + 1))
    if [ "$code" != "0" ]; then
      failed=$((failed + 1))
      report="${report}failed: ${cmd}"$'\n'
    fi
  fi
done <<< "$(printf '%s' "$REQUIRED" | awk '!seen[$0]++')"

printf 'acceptance: %d/%d executed, %d failed\n' "$executed" "$required" "$failed"
printf '%s' "$report"
[ "$executed" -eq "$required" ] && [ "$failed" -eq 0 ]
