#!/usr/bin/env bash
# @description  Validate a 13-file CSV export set against cross-file sum constraints,
#               per-row range consistency, phase hour caps, week continuity,
#               phase dependencies, and format rules.
#               Emits validation_report.csv and exits non-zero when violations found.
# @arg  --dir <path>        Directory containing the 13 CSV files (default: .)
# @arg  --out <file>        Path for validation_report.csv (default: <dir>/validation_report.csv)
# @arg  --delimiter <char>  Field delimiter of the export files (default: ;)
# @arg  --self-test         Run built-in fixture tests; no network/external deps needed
# @exitcode  0  All checks passed
# @exitcode  1  One or more validation failures
# @exitcode  2  Usage / missing-file error
# minimum: bash 4.x, python3 (stdlib only), shellcheck-clean, shfmt-formatted
set -Eeuo pipefail
shopt -s inherit_errexit 2> /dev/null || true
IFS=$'\n\t'
trap 'printf >&2 "error: %s:%d: exit %d\n" "${BASH_SOURCE[0]}" "$LINENO" "$?"' ERR

# ---------------------------------------------------------------------------
# Python3 CSV parser (heredoc — embedded to handle semicolons + quoted fields)
# ---------------------------------------------------------------------------
# Language: Python 3 stdlib only.  Invoked as: python3 <(cat <<'PY' ...) --op ...
# All CSV parsing goes through python3 csv.reader so quoted-semicolons are safe.

read -r -d '' PY_VALIDATOR << 'PY' || true
"""
Embedded CSV validator.  Invoked with subcommands by the outer bash script.

Global option
  --delimiter D   field delimiter of the export files (default ;)

Commands
  row-values  --file F --label L --col1 C1 --col2 C2
               print C1 and C2 of the first row labelled L, TAB-separated
               (nothing when no row carries that label)
  sum-cols2  --file F --col1 C1 --col2 C2 [--skip-labels L,L] [--keep-labels L,L]
               print two sums separated by TAB (for paired min/max totals)
  check-range  --file F --mincol A --maxcol B [--skip-labels L,L]
               print rows where min>max as: LABEL|MIN|MAX
  check-phase-cap  --file F --maxcol C --cap N [--label-col LC] [--skip-labels L,L]
               print phase rows where max>cap as: LABEL|VALUE
  check-format  --file F
               print issues as TYPE|DETAIL, TYPE one of
               UTF8|DELIMITER|MISSING_HEADER|WIDTH|FORMAT_ERROR
  check-weeks  --file F --col C
               print week-range gaps and malformed ranges as: LABEL|DETAIL
  check-deps  --file F --col C
               print dependencies on missing or later phases as: LABEL|DETAIL
"""
import sys
import csv
import argparse
import re

SKIP_DEFAULT = {"TOTAL", "Buffer", "Subtotal", ""}
DELIM = ";"
DELIM_NAMES = {";": "semicolon", ",": "comma", "\t": "tab", "|": "pipe"}

# "3", "1-2", "W1-W2", "Week 1 - Week 2"; an en dash is accepted for the separator.
WEEK_RE = re.compile(
    r"^\s*(?:w(?:eek)?\s*)?(\d+)\s*(?:[-\u2013]\s*(?:w(?:eek)?\s*)?(\d+))?\s*$", re.I
)
PHASE_REF_RE = re.compile(r"^(?:phase\s*)?(\d+)$", re.I)


def _delim_name(d: str) -> str:
    return DELIM_NAMES.get(d, f"U+{ord(d):04X}")


def _open(path: str):
    return open(path, encoding="utf-8-sig", newline="")


def _reader(fh):
    return csv.reader(fh, delimiter=DELIM)


def _skip_set(skip: str | None, keep: str | None = None) -> set[str]:
    out = set(SKIP_DEFAULT)
    if skip:
        out |= set(skip.split(","))
    if keep:
        out -= set(keep.split(","))
    return out


def _col_index(header: list[str], name: str) -> int:
    name_l = name.strip().lower()
    for i, h in enumerate(header):
        if h.strip().lower() == name_l:
            return i
    raise SystemExit(f"Column not found: {name!r} in header {header!r}")


def _num(cell: str) -> float:
    cell = cell.strip()
    if cell == "":
        return 0.0
    try:
        return float(cell)
    except ValueError:
        return 0.0


def cmd_row_values(args: argparse.Namespace) -> None:
    with _open(args.file) as fh:
        rd = _reader(fh)
        header = next(rd)
        c1 = _col_index(header, args.col1)
        c2 = _col_index(header, args.col2)
        for row in rd:
            if row and row[0].strip() == args.label:
                v1 = _num(row[c1]) if c1 < len(row) else 0.0
                v2 = _num(row[c2]) if c2 < len(row) else 0.0
                print(f"{v1:.6g}\t{v2:.6g}")
                return


def cmd_sum_cols2(args: argparse.Namespace) -> None:
    skip = _skip_set(args.skip_labels, args.keep_labels)
    t1 = 0.0
    t2 = 0.0
    with _open(args.file) as fh:
        rd = _reader(fh)
        header = next(rd)
        c1 = _col_index(header, args.col1)
        c2 = _col_index(header, args.col2)
        for row in rd:
            if not row:
                continue
            if row[0].strip() in skip:
                continue
            t1 += _num(row[c1]) if c1 < len(row) else 0.0
            t2 += _num(row[c2]) if c2 < len(row) else 0.0
    print(f"{t1:.6g}\t{t2:.6g}")


def cmd_check_range(args: argparse.Namespace) -> None:
    skip = _skip_set(args.skip_labels)
    with _open(args.file) as fh:
        rd = _reader(fh)
        header = next(rd)
        mi = _col_index(header, args.mincol)
        xi = _col_index(header, args.maxcol)
        # label col: first column by default
        for row in rd:
            if not row:
                continue
            label = row[0].strip()
            if label in skip:
                continue
            mn_s = row[mi].strip() if mi < len(row) else ""
            mx_s = row[xi].strip() if xi < len(row) else ""
            if mn_s == "" or mx_s == "":
                continue
            try:
                mn = float(mn_s)
                mx = float(mx_s)
            except ValueError:
                continue
            if mn > mx:
                print(f"{label}|{mn_s}|{mx_s}")


def cmd_check_phase_cap(args: argparse.Namespace) -> None:
    skip = _skip_set(args.skip_labels)
    cap = float(args.cap)
    with _open(args.file) as fh:
        rd = _reader(fh)
        header = next(rd)
        xi = _col_index(header, args.maxcol)
        lci = _col_index(header, args.label_col) if args.label_col else 0
        for row in rd:
            if not row:
                continue
            label = row[lci].strip() if lci < len(row) else row[0].strip()
            if label in skip:
                continue
            mx_s = row[xi].strip() if xi < len(row) else ""
            if mx_s == "":
                continue
            try:
                mx = float(mx_s)
            except ValueError:
                continue
            if mx > cap:
                print(f"{label}|{mx_s}")


def cmd_check_format(args: argparse.Namespace) -> None:
    path = args.file
    issues: list[str] = []
    try:
        with open(path, "rb") as fb:
            raw = fb.read()
        raw.decode("utf-8-sig")
    except UnicodeDecodeError as e:
        issues.append(f"UTF8|{e}")
    else:
        try:
            with _open(path) as fh:
                first_line = fh.readline()
            if DELIM not in first_line:
                # Named, not quoted or previewed: the report is semicolon-delimited.
                seen = max(DELIM_NAMES, key=first_line.count)
                hint = (
                    f" (looks {DELIM_NAMES[seen]}-delimited)"
                    if first_line.count(seen)
                    else ""
                )
                issues.append(f"DELIMITER|first line has no {_delim_name(DELIM)}{hint}")
            else:
                with _open(path) as fh:
                    rd = _reader(fh)
                    header = next(rd)
                    non_empty = [c for c in header if c.strip()]
                    if len(non_empty) < 2:
                        issues.append(
                            f"MISSING_HEADER|only {len(non_empty)} header column(s)"
                        )
                    # A short row shifts every later cell under the wrong header in
                    # a spreadsheet, so field count is checked even though the sum
                    # checks read cells by index and tolerate it.
                    for row in rd:
                        if row and len(row) != len(header):
                            issues.append(
                                f"WIDTH|line {rd.line_num} ({row[0].strip()}): "
                                f"{len(row)} fields, header has {len(header)}"
                            )
        except Exception as e:  # noqa: BLE001
            issues.append(f"FORMAT_ERROR|{e}")
    for iss in issues:
        print(iss)


def cmd_check_weeks(args: argparse.Namespace) -> None:
    # Overlap is allowed (parallel phases); a week no row covers is not.
    skip = SKIP_DEFAULT - {"Buffer"}
    with _open(args.file) as fh:
        rd = _reader(fh)
        header = next(rd)
        wi = _col_index(header, args.col)
        max_end: int | None = None
        for row in rd:
            if not row:
                continue
            label = row[0].strip()
            if label in skip:
                continue
            cell = row[wi].strip() if wi < len(row) else ""
            m = WEEK_RE.match(cell)
            if not m:
                print(f"{label}|week range {cell!r} is not N or N-M")
                continue
            start = int(m.group(1))
            end = int(m.group(2)) if m.group(2) else start
            if start > end:
                print(f"{label}|week range {cell} ends before it starts")
            if max_end is not None and start > max_end + 1:
                print(f"{label}|week range {cell} leaves a gap after week {max_end}")
            max_end = end if max_end is None else max(max_end, end)


def cmd_check_deps(args: argparse.Namespace) -> None:
    # Only phase references ("2", "Phase 2") are checked; "-", "All" and
    # free-text dependencies carry nothing to resolve.
    skip = SKIP_DEFAULT - {"Buffer"}
    with _open(args.file) as fh:
        rd = _reader(fh)
        header = next(rd)
        di = _col_index(header, args.col)
        rows = [r for r in rd if r and r[0].strip() not in skip]
    phases = {int(r[0].strip()) for r in rows if r[0].strip().isdigit()}
    for row in rows:
        label = row[0].strip()
        cell = row[di].strip() if di < len(row) else ""
        for token in cell.split(","):
            m = PHASE_REF_RE.match(token.strip())
            if not m:
                continue
            ref = int(m.group(1))
            if ref not in phases:
                print(f"{label}|depends on phase {ref}, which does not exist")
            elif label.isdigit() and ref >= int(label):
                print(f"{label}|depends on phase {ref}, which does not come earlier")


def main() -> None:
    global DELIM
    ap = argparse.ArgumentParser()
    ap.add_argument("--delimiter", default=";")
    sub = ap.add_subparsers(dest="cmd")

    p = sub.add_parser("row-values")
    p.add_argument("--file", required=True)
    p.add_argument("--label", required=True)
    p.add_argument("--col1", required=True)
    p.add_argument("--col2", required=True)

    p = sub.add_parser("sum-cols2")
    p.add_argument("--file", required=True)
    p.add_argument("--col1", required=True)
    p.add_argument("--col2", required=True)
    p.add_argument("--skip-labels", default=None)
    p.add_argument("--keep-labels", default=None)

    p = sub.add_parser("check-range")
    p.add_argument("--file", required=True)
    p.add_argument("--mincol", required=True)
    p.add_argument("--maxcol", required=True)
    p.add_argument("--skip-labels", default=None)

    p = sub.add_parser("check-phase-cap")
    p.add_argument("--file", required=True)
    p.add_argument("--maxcol", required=True)
    p.add_argument("--cap", required=True, type=float)
    p.add_argument("--label-col", default=None)
    p.add_argument("--skip-labels", default=None)

    p = sub.add_parser("check-format")
    p.add_argument("--file", required=True)

    p = sub.add_parser("check-weeks")
    p.add_argument("--file", required=True)
    p.add_argument("--col", required=True)

    p = sub.add_parser("check-deps")
    p.add_argument("--file", required=True)
    p.add_argument("--col", required=True)

    args = ap.parse_args()
    DELIM = args.delimiter
    handlers = {
        "row-values": cmd_row_values,
        "sum-cols2": cmd_sum_cols2,
        "check-range": cmd_check_range,
        "check-phase-cap": cmd_check_phase_cap,
        "check-format": cmd_check_format,
        "check-weeks": cmd_check_weeks,
        "check-deps": cmd_check_deps,
    }
    if args.cmd not in handlers:
        ap.print_help()
        sys.exit(2)
    handlers[args.cmd](args)


main()
PY

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Write one row to the report CSV. The report is always semicolon-delimited,
# whatever --delimiter says, so callers can parse it without knowing the export.
_rpt() {
  printf '%s\n' "$*" >> "${REPORT_FILE}"
}

# Run the embedded Python validator subcommand.
# Usage: _py <subcommand> [args...]
_py() {
  python3 <(printf '%s' "${PY_VALIDATOR}") --delimiter "${DELIM}" "$@"
}

# Resolve file by prefix number within DIR, return path or empty string.
_find_file() {
  local prefix="$1"
  local f
  f=$(find "${DIR}" -maxdepth 1 -name "${prefix}_*.csv" | sort | head -n 1)
  printf '%s' "${f}"
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
usage() {
  cat >&2 << 'USAGE'
Usage: validate-export.sh [--dir <csv-dir>] [--out <report.csv>] [--delimiter <char>] [--self-test]

  --dir <path>        Directory containing the 13 export CSV files (default: .)
  --out <file>        Output path for validation_report.csv
                      (default: <dir>/validation_report.csv)
  --delimiter <char>  Field delimiter of the export files (default: ;).
                      The report itself is always semicolon-delimited.
  --self-test         Run built-in fixture tests and exit
USAGE
  exit 2
}

DIR="."
OUT=""
DELIM=";"
SELF_TEST_MODE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)
      [[ $# -ge 2 ]] || usage
      DIR="$2"
      shift 2
      ;;
    --out)
      [[ $# -ge 2 ]] || usage
      OUT="$2"
      shift 2
      ;;
    --delimiter)
      [[ $# -ge 2 ]] || usage
      DELIM="$2"
      shift 2
      ;;
    --self-test)
      SELF_TEST_MODE=1
      shift
      ;;
    -h | --help) usage ;;
    *)
      printf >&2 'Unknown argument: %s\n' "$1"
      usage
      ;;
  esac
done

# csv.reader takes exactly one character, and a quote or line break cannot
# separate fields.
if [[ "${#DELIM}" -ne 1 || "${DELIM}" == '"' || "${DELIM}" == $'\n' || "${DELIM}" == $'\r' ]]; then
  printf >&2 'error: --delimiter must be one character other than a quote or line break\n'
  exit 2
fi

if [[ "${SELF_TEST_MODE}" -eq 1 ]]; then
  # Sourced HERE, not at the top and only on this branch: the harness is test
  # code the scan path never runs, and a production run must not fail on its
  # absence. `[ -r ]` first, not a bare `.`: sourcing a missing file with the
  # `.` builtin is a special-builtin error that exits the shell immediately,
  # bypassing an `if ! . …` guard entirely.
  SELFTEST_LIB_PATH="$(dirname "${BASH_SOURCE[0]}")/validate-export-selftest.sh"
  if [ -r "$SELFTEST_LIB_PATH" ]; then
    # shellcheck source=validate-export-selftest.sh
    # shellcheck disable=SC1090
    . "$SELFTEST_LIB_PATH"
  else
    printf >&2 'validate-export: self-test harness unreachable at %s — plugin install broken\n' \
      "$SELFTEST_LIB_PATH"
    exit 2
  fi
  _self_test
fi

[[ -d "${DIR}" ]] || {
  printf >&2 'error: directory not found: %s\n' "${DIR}"
  exit 2
}

if [[ -z "${OUT}" ]]; then
  OUT="${DIR}/validation_report.csv"
fi

REPORT_FILE="${OUT}"

# ---------------------------------------------------------------------------
# Locate files
# ---------------------------------------------------------------------------
F01=$(_find_file "01")
F04=$(_find_file "04")
F05=$(_find_file "05")
F07=$(_find_file "07")
F13=$(_find_file "13")

FAILURES=0
# Set when a file the numeric checks parse cannot be split into fields at all.
PARSE_BLOCKED=0

# ---------------------------------------------------------------------------
# Initialize report
# ---------------------------------------------------------------------------
printf 'check;status;detail\n' > "${REPORT_FILE}"

# ---------------------------------------------------------------------------
# Helper: record a check result
# ---------------------------------------------------------------------------
_check() {
  local check="$1"
  local status="$2"
  local detail="${3:-}"
  # A delimiter inside a quoted first line would add a report column.
  _rpt "${check};${status};${detail//;/,}"
  if [[ "${status}" == "FAIL" ]]; then
    FAILURES=$((FAILURES + 1))
  fi
}

# ---------------------------------------------------------------------------
# 1. Format checks: every NN_*.csv present, and 01/04/07/13 must exist
# ---------------------------------------------------------------------------
for num in 01 02 03 04 05 06 07 08 09 10 11 12 13; do
  files=$(find "${DIR}" -maxdepth 1 -name "${num}_*.csv" | sort)
  if [[ -z "${files}" ]]; then
    case "${num}" in
      01 | 04 | 07 | 13)
        _check "format/file-${num}" "FAIL" "file ${num}_*.csv not found in ${DIR}"
        ;;
    esac
    continue
  fi
  while IFS= read -r file; do
    fmt_issues=$(_py check-format --file "${file}")
    if [[ -z "${fmt_issues}" ]]; then
      _check "format/file-${num}" "PASS" "${file##*/}"
      continue
    fi
    while IFS= read -r line; do
      [[ -z "${line}" ]] && continue
      _check "format/file-${num}" "FAIL" "${line}"
      case "${num}:${line%%|*}" in
        01:WIDTH | 04:WIDTH | 05:WIDTH | 07:WIDTH | 13:WIDTH) ;;
        01:* | 04:* | 05:* | 07:* | 13:*) PARSE_BLOCKED=1 ;;
      esac
    done <<< "${fmt_issues}"
  done <<< "${files}"
done

if [[ -z "${F04}" || -z "${F13}" || "${PARSE_BLOCKED}" -eq 1 ]]; then
  printf >&2 "error: files 04/13 missing or unparseable with delimiter '%s'; skipping content checks\n" "${DELIM}"
  printf >&2 'validation_report written to %s\n' "${REPORT_FILE}"
  exit 1
fi

# ---------------------------------------------------------------------------
# 2. Sum equality: 04 SP Min/Max  vs  13 SP Min/Max
# ---------------------------------------------------------------------------
read -r sp04_min sp04_max < <(_py sum-cols2 --file "${F04}" \
  --col1 "SP Min" --col2 "SP Max")
read -r sp13_min sp13_max < <(_py sum-cols2 --file "${F13}" \
  --col1 "SP Min" --col2 "SP Max")

if [[ "${sp04_min}" == "${sp13_min}" ]]; then
  _check "sum/04-vs-13/SP-Min" "PASS" "both=${sp04_min}"
else
  _check "sum/04-vs-13/SP-Min" "FAIL" "04=${sp04_min} 13=${sp13_min}"
fi

if [[ "${sp04_max}" == "${sp13_max}" ]]; then
  _check "sum/04-vs-13/SP-Max" "PASS" "both=${sp04_max}"
else
  _check "sum/04-vs-13/SP-Max" "FAIL" "04=${sp04_max} 13=${sp13_max}"
fi

# ---------------------------------------------------------------------------
# 3. Sum equality: 07 Hours Min/Max  vs  13 Hours Min/Max (base hours, both
#    without their Buffer, Subtotal and TOTAL rows)
# ---------------------------------------------------------------------------
read -r hr13_min hr13_max < <(_py sum-cols2 --file "${F13}" \
  --col1 "Hours Min" --col2 "Hours Max")

if [[ -n "${F07}" ]]; then
  read -r hr07_min hr07_max < <(_py sum-cols2 --file "${F07}" \
    --col1 "Hours Min" --col2 "Hours Max")

  if [[ "${hr07_min}" == "${hr13_min}" ]]; then
    _check "sum/07-vs-13/Hours-Min" "PASS" "both=${hr07_min}"
  else
    _check "sum/07-vs-13/Hours-Min" "FAIL" "07=${hr07_min} 13=${hr13_min}"
  fi

  if [[ "${hr07_max}" == "${hr13_max}" ]]; then
    _check "sum/07-vs-13/Hours-Max" "PASS" "both=${hr07_max}"
  else
    _check "sum/07-vs-13/Hours-Max" "FAIL" "07=${hr07_max} 13=${hr13_max}"
  fi
fi

# ---------------------------------------------------------------------------
# 4. Sum equality: 01 Total Hours  vs  13 phase rows + Buffer row
#    01's Total Hours is base + buffer, so 13's Buffer row counts here.
# ---------------------------------------------------------------------------
if [[ -n "${F01}" ]]; then
  ov01=$(_py row-values --file "${F01}" --label "Total Hours" \
    --col1 "Value Min" --col2 "Value Max")
  read -r tot13_min tot13_max < <(_py sum-cols2 --file "${F13}" \
    --col1 "Hours Min" --col2 "Hours Max" --keep-labels "Buffer")

  if [[ -z "${ov01}" ]]; then
    _check "sum/01-vs-13/Hours-Min" "FAIL" "01 has no Total Hours row"
    _check "sum/01-vs-13/Hours-Max" "FAIL" "01 has no Total Hours row"
  else
    read -r ov01_min ov01_max <<< "${ov01}"
    if [[ "${ov01_min}" == "${tot13_min}" ]]; then
      _check "sum/01-vs-13/Hours-Min" "PASS" "both=${ov01_min}"
    else
      _check "sum/01-vs-13/Hours-Min" "FAIL" "01=${ov01_min} 13=${tot13_min}"
    fi

    if [[ "${ov01_max}" == "${tot13_max}" ]]; then
      _check "sum/01-vs-13/Hours-Max" "PASS" "both=${ov01_max}"
    else
      _check "sum/01-vs-13/Hours-Max" "FAIL" "01=${ov01_max} 13=${tot13_max}"
    fi
  fi
fi

# Run one validator subcommand and record its violation lines as one check.
# Assigned, not passed as an argument, so a validator crash stops the run
# instead of reading as an empty, passing result.
# Usage: _check_lines <check-id> <pass-detail> <fail-prefix> <subcommand> [args...]
_check_lines() {
  local check="$1" pass_detail="$2" prefix="$3" violations line
  shift 3
  violations=$(_py "$@")
  if [[ -z "${violations}" ]]; then
    _check "${check}" "PASS" "${pass_detail}"
    return
  fi
  while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    _check "${check}" "FAIL" "${prefix}=${line}"
  done <<< "${violations}"
}

# ---------------------------------------------------------------------------
# 5. Per-row range: SP Min <= SP Max and Hours Min <= Hours Max (file 04)
# ---------------------------------------------------------------------------
_check_lines "range/04/SP-Min-le-Max" "all rows OK" "row" \
  check-range --file "${F04}" --mincol "SP Min" --maxcol "SP Max"
_check_lines "range/04/Hours-Min-le-Max" "all rows OK" "row" \
  check-range --file "${F04}" --mincol "Hours Min" --maxcol "Hours Max"

# ---------------------------------------------------------------------------
# 6. Per-row range: SP Min <= SP Max and Hours Min <= Hours Max (file 13)
# ---------------------------------------------------------------------------
_check_lines "range/13/SP-Min-le-Max" "all rows OK" "row" \
  check-range --file "${F13}" --mincol "SP Min" --maxcol "SP Max"
_check_lines "range/13/Hours-Min-le-Max" "all rows OK" "row" \
  check-range --file "${F13}" --mincol "Hours Min" --maxcol "Hours Max"

# ---------------------------------------------------------------------------
# 7. Phase cap: no phase Hours Max > 160 (file 13, per phase row)
# ---------------------------------------------------------------------------
_check_lines "phase-cap/13/Hours-Max-le-160" "all phases OK" "phase" \
  check-phase-cap --file "${F13}" --maxcol "Hours Max" --cap 160 \
    --label-col "Phase" --skip-labels "TOTAL,Buffer"

# ---------------------------------------------------------------------------
# 8. Per-row range and phase cap (file 07; budget rows represent phases)
# ---------------------------------------------------------------------------
if [[ -n "${F07}" ]]; then
  _check_lines "range/07/Hours-Min-le-Max" "all rows OK" "row" \
    check-range --file "${F07}" --mincol "Hours Min" --maxcol "Hours Max"
  _check_lines "phase-cap/07/Hours-Max-le-160" "all rows OK" "row" \
    check-phase-cap --file "${F07}" --maxcol "Hours Max" --cap 160 \
      --skip-labels "TOTAL,Buffer,Subtotal"
fi

# ---------------------------------------------------------------------------
# 9. Phase constraints: week ranges continuous, dependencies resolve
#    (file 13 always, file 05 when present)
# ---------------------------------------------------------------------------
# Usage: _check_phases <file-number> <file> <week-column>
_check_phases() {
  [[ -z "$2" ]] && return 0
  _check_lines "phase/$1/Weeks-continuous" "all rows OK" "row" \
    check-weeks --file "$2" --col "$3"
  _check_lines "phase/$1/Dependencies-valid" "all rows OK" "row" \
    check-deps --file "$2" --col "Dependencies"
}
_check_phases 13 "${F13}" "Weeks"
_check_phases 05 "${F05}" "Week"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf >&2 'validation_report written to %s\n' "${REPORT_FILE}"

if [[ "${FAILURES}" -gt 0 ]]; then
  printf >&2 '%d check(s) FAILED — see %s\n' "${FAILURES}" "${REPORT_FILE}"
  exit 1
fi

printf >&2 'All checks PASSED\n'
exit 0
