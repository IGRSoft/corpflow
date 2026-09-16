#!/usr/bin/env bash
# @description control-byte-lib.sh — the control-byte predicate shared by the PostToolUse
#   anchor preflight hook, the handoff harness gate and control-byte-lint.sh.
#
#   Flags 0x00-0x08, 0x0B, 0x0C and 0x0E-0x1F. Tab, LF, CR, DEL and every byte from 0x80 up
#   pass, so UTF-8 text is never flagged. Text is chosen by extension, never by sniffing
#   content: a raw NUL is exactly what makes content sniffers call a file binary.
#
#   Sources nothing, sets no options, does no work at load.
#
#   Symbols: CB_TEXT_EXTS, cb_is_lintable, cb_scan_file.
#
# Minimum shell: bash 3.2+ (macOS default).

# Anti-execution guard — MUST be the first statement.
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  printf >&2 'control-byte-lib.sh: this is a library — source it, do not execute it directly\n'
  exit 2
fi

# Include guard: a double source is a no-op rather than a re-definition.
[ -n "${_CORPFLOW_CONTROL_BYTE_LIB:-}" ] && return 0
_CORPFLOW_CONTROL_BYTE_LIB=1

# Not `readonly`: consumer bats suites source this file more than once per process.
CB_TEXT_EXTS='md markdown sh bash bats zsh py json jsonl yml yaml toml txt tsv csv swift env html css js mjs ts tsx xml ini cfg conf'

# cb_is_lintable <path> -> rc 0 when the extension is on CB_TEXT_EXTS and the path is not vendored.
cb_is_lintable() {
  local _p="${1:-}" _base _ext
  [ -n "$_p" ] || return 1
  case "$_p" in
    tests/vendor/* | */tests/vendor/*) return 1 ;;
  esac
  _base="${_p##*/}"
  case "$_base" in
    *.*) ;;
    *) return 1 ;;
  esac
  _ext=$(printf '%s' "${_base##*.}" | LC_ALL=C tr '[:upper:]' '[:lower:]')
  [ -n "$_ext" ] || return 1
  case " $CB_TEXT_EXTS " in
    *" $_ext "*) return 0 ;;
  esac
  return 1
}

# cb_scan_file <file> [label] -> `label:offset:0xHH` per hit (0-based offset, first 20 hits).
#
# rc 0 clean, 1 hit, 2 not a readable regular file or the scan could not complete.
cb_scan_file() {
  local _f="${1:-}" _label="${2:-${1:-}}" _rc=0
  { [ -f "$_f" ] && [ -r "$_f" ]; } || return 2
  # od and cmp would parse a dash-led name as an option.
  case "$_f" in -*) _f="./$_f" ;; esac

  # LC_ALL=C: BSD tr aborts on some high bytes under a UTF-8 locale.
  # shellcheck disable=SC2094  # both ends only read the file; nothing writes it
  if LC_ALL=C tr -d '\000-\010\013\014\016-\037' < "$_f" | cmp -s - "$_f"; then
    return 0
  fi

  # od -v: without it a run of identical lines collapses to `*` and every later offset shifts.
  # The awk hit rc is 3, never 1, so a pipefail caller cannot mistake an od failure for a hit;
  # it keeps reading past the print cap because an early exit would SIGPIPE od. The label
  # rides in ENVIRON because `awk -v` decodes backslash escapes in the value.
  LC_ALL=C od -An -v -tu1 "$_f" | CB_SCAN_LABEL="$_label" LC_ALL=C awk '
    {
      for (i = 1; i <= NF; i++) {
        b = $i + 0
        if (b < 9 || b == 11 || b == 12 || (b >= 14 && b < 32)) {
          if (++hits <= 20) printf "%s:%d:0x%02X\n", ENVIRON["CB_SCAN_LABEL"], off, b
        }
        off++
      }
    }
    END { exit (hits > 0 ? 3 : 0) }' || _rc=$?

  # tr and cmp disagreed, so a clean od pass means the scan itself failed: report, never pass.
  [ "$_rc" -eq 3 ] && return 1
  return 2
}
