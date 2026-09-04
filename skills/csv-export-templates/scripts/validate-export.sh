#!/usr/bin/env bash
# @description  Validate a 13-file CSV export set against cross-file sum constraints,
#               per-row range consistency, phase hour caps, and format rules.
#               Emits validation_report.csv and exits non-zero when violations found.
# @arg  --dir <path>        Directory containing the 13 CSV files (default: .)
# @arg  --out <file>        Path for validation_report.csv (default: <dir>/validation_report.csv)
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

Commands
  sum-col  --file F --col C [--skip-labels L,L]   print numeric sum of column C
  check-range  --file F --mincol A --maxcol B [--skip-labels L,L]
               print rows where min>max as: LABEL|MIN|MAX
  check-phase-cap  --file F --maxcol C --cap N [--label-col LC] [--skip-labels L,L]
               print phase rows where max>cap as: LABEL|VALUE
  check-format  --file F
               print issues: MISSING_HEADER|UTF8|DELIMITER as: TYPE|DETAIL
  sum-cols2  --file F --col1 C1 --col2 C2 [--skip-labels L,L]
               print two sums separated by TAB (for paired min/max totals)
"""
import sys
import csv
import argparse
import io

SKIP_DEFAULT = {"TOTAL", "Buffer", "Subtotal", ""}


def _open(path: str):
    return open(path, encoding="utf-8-sig", newline="")


def _reader(fh):
    return csv.reader(fh, delimiter=";")


def _skip_set(arg: str | None) -> set[str]:
    if not arg:
        return SKIP_DEFAULT
    return SKIP_DEFAULT | set(arg.split(","))


def _col_index(header: list[str], name: str) -> int:
    name_l = name.strip().lower()
    for i, h in enumerate(header):
        if h.strip().lower() == name_l:
            return i
    raise SystemExit(f"Column not found: {name!r} in header {header!r}")


def cmd_sum_col(args: argparse.Namespace) -> None:
    skip = _skip_set(args.skip_labels)
    total = 0.0
    with _open(args.file) as fh:
        rd = _reader(fh)
        header = next(rd)
        ci = _col_index(header, args.col)
        for row in rd:
            if not row:
                continue
            label = row[0].strip() if row else ""
            if label in skip:
                continue
            cell = row[ci].strip() if ci < len(row) else ""
            if cell == "":
                continue
            try:
                total += float(cell)
            except ValueError:
                pass
    print(f"{total:.6g}")


def cmd_sum_cols2(args: argparse.Namespace) -> None:
    skip = _skip_set(args.skip_labels)
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
            label = row[0].strip() if row else ""
            if label in skip:
                continue

            def _val(ci: int) -> float:
                cell = row[ci].strip() if ci < len(row) else ""
                if cell == "":
                    return 0.0
                try:
                    return float(cell)
                except ValueError:
                    return 0.0

            t1 += _val(c1)
            t2 += _val(c2)
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
    # UTF-8 check (try decode entire file)
    try:
        with open(path, "rb") as fb:
            raw = fb.read()
        raw.decode("utf-8-sig")
    except UnicodeDecodeError as e:
        issues.append(f"UTF8|{e}")
    # Delimiter + header check
    try:
        with _open(path) as fh:
            first_line = fh.readline()
        if ";" not in first_line:
            issues.append(f"DELIMITER|first line has no semicolon: {first_line[:80]!r}")
        else:
            # Verify header row has >= 2 non-empty fields
            rd = csv.reader(io.StringIO(first_line), delimiter=";")
            cols = [c.strip() for c in next(rd)]
            non_empty = [c for c in cols if c]
            if len(non_empty) < 2:
                issues.append(f"MISSING_HEADER|only {len(non_empty)} header column(s)")
    except Exception as e:  # noqa: BLE001
        issues.append(f"FORMAT_ERROR|{e}")
    for iss in issues:
        print(iss)


def main() -> None:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd")

    p = sub.add_parser("sum-col")
    p.add_argument("--file", required=True)
    p.add_argument("--col", required=True)
    p.add_argument("--skip-labels", default=None)

    p = sub.add_parser("sum-cols2")
    p.add_argument("--file", required=True)
    p.add_argument("--col1", required=True)
    p.add_argument("--col2", required=True)
    p.add_argument("--skip-labels", default=None)

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

    args = ap.parse_args()
    if args.cmd == "sum-col":
        cmd_sum_col(args)
    elif args.cmd == "sum-cols2":
        cmd_sum_cols2(args)
    elif args.cmd == "check-range":
        cmd_check_range(args)
    elif args.cmd == "check-phase-cap":
        cmd_check_phase_cap(args)
    elif args.cmd == "check-format":
        cmd_check_format(args)
    else:
        ap.print_help()
        sys.exit(2)


main()
PY

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Write one row to the report CSV (semicolon-delimited, no quoting needed for
# our internal strings which never contain semicolons).
_rpt() {
  printf '%s\n' "$*" >> "${REPORT_FILE}"
}

# Run the embedded Python validator subcommand.
# Usage: _py <subcommand> [args...]
_py() {
  python3 <(printf '%s' "${PY_VALIDATOR}") "$@"
}

# Resolve file by prefix number within DIR, return path or empty string.
_find_file() {
  local prefix="$1"
  local f
  f=$(find "${DIR}" -maxdepth 1 -name "${prefix}_*.csv" | head -n 1)
  printf '%s' "${f}"
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
usage() {
  cat >&2 << 'USAGE'
Usage: validate-export.sh [--dir <csv-dir>] [--out <report.csv>] [--self-test]

  --dir <path>   Directory containing the 13 export CSV files (default: .)
  --out <file>   Output path for validation_report.csv
                 (default: <dir>/validation_report.csv)
  --self-test    Run built-in fixture tests and exit
USAGE
  exit 2
}

DIR="."
OUT=""
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

# Sourced HERE, not at the top: the harness is test code the production path
# never runs. `[ -r ]` first, not a bare `.`: sourcing a missing file with the
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
[[ "${SELF_TEST_MODE}" -eq 1 ]] && _self_test

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
F07=$(_find_file "07")
F13=$(_find_file "13")

FAILURES=0

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
  _rpt "${check};${status};${detail}"
  if [[ "${status}" == "FAIL" ]]; then
    FAILURES=$((FAILURES + 1))
  fi
}

# ---------------------------------------------------------------------------
# 1. Format checks (all four files must exist and be valid)
# ---------------------------------------------------------------------------
for pair in "01:${F01}" "04:${F04}" "07:${F07}" "13:${F13}"; do
  local_num="${pair%%:*}"
  local_file="${pair#*:}"
  if [[ -z "${local_file}" ]]; then
    _check "format/file-${local_num}" "FAIL" "file ${local_num}_*.csv not found in ${DIR}"
  else
    fmt_issues=$(_py check-format --file "${local_file}")
    if [[ -n "${fmt_issues}" ]]; then
      while IFS= read -r line; do
        [[ -z "${line}" ]] && continue
        _check "format/file-${local_num}" "FAIL" "${line}"
      done <<< "${fmt_issues}"
    else
      _check "format/file-${local_num}" "PASS" "${local_file##*/}"
    fi
  fi
done

# Abort further numeric checks if any file is missing
if [[ "${FAILURES}" -gt 0 ]]; then
  # Check if we have minimum files to proceed
  if [[ -z "${F04}" || -z "${F13}" ]]; then
    printf >&2 'error: required files 04 and/or 13 missing; cannot proceed with sum checks\n'
    printf >&2 'validation_report written to %s\n' "${REPORT_FILE}"
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# 2. Sum equality: 04 SP Min/Max  vs  13 SP Min/Max
# ---------------------------------------------------------------------------
if [[ -n "${F04}" && -n "${F13}" ]]; then
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
fi

# ---------------------------------------------------------------------------
# 3. Sum equality: 07 Hours Min/Max  vs  13 Hours Min/Max
# ---------------------------------------------------------------------------
if [[ -n "${F07}" && -n "${F13}" ]]; then
  read -r hr07_min hr07_max < <(_py sum-cols2 --file "${F07}" \
    --col1 "Hours Min" --col2 "Hours Max")
  read -r hr13_min hr13_max < <(_py sum-cols2 --file "${F13}" \
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
# 4. Sum equality: 01 overview Total Hours  vs  13 Hours Min/Max
# ---------------------------------------------------------------------------
if [[ -n "${F01}" && -n "${F13}" ]]; then
  # 01 has "Category;Value Min;Value Max;Notes" — find row where Category="Total Hours"
  # We use a custom skip (don't skip "Total Hours" label)
  ov01_min=$(_py sum-col --file "${F01}" --col "Value Min" \
    --skip-labels "Project Name,Platform,Team Size,Hourly Rate,Total SP Min,Total SP Max,Base Hours,Buffer (15%),Timeline,Budget,T-Shirt Size,Complexity Score,Risk Level,Backend,Test Coverage Target")
  ov01_max=$(_py sum-col --file "${F01}" --col "Value Max" \
    --skip-labels "Project Name,Platform,Team Size,Hourly Rate,Total SP Min,Total SP Max,Base Hours,Buffer (15%),Timeline,Budget,T-Shirt Size,Complexity Score,Risk Level,Backend,Test Coverage Target")

  # 13 totals already computed above
  if [[ -z "${hr13_min:-}" ]]; then
    read -r hr13_min hr13_max < <(_py sum-cols2 --file "${F13}" \
      --col1 "Hours Min" --col2 "Hours Max")
  fi

  if [[ "${ov01_min}" == "${hr13_min}" ]]; then
    _check "sum/01-vs-13/Hours-Min" "PASS" "both=${ov01_min}"
  else
    _check "sum/01-vs-13/Hours-Min" "FAIL" "01=${ov01_min} 13=${hr13_min}"
  fi

  if [[ "${ov01_max}" == "${hr13_max}" ]]; then
    _check "sum/01-vs-13/Hours-Max" "PASS" "both=${ov01_max}"
  else
    _check "sum/01-vs-13/Hours-Max" "FAIL" "01=${ov01_max} 13=${hr13_max}"
  fi
fi

# ---------------------------------------------------------------------------
# 5. Per-row range: SP Min <= SP Max (file 04)
# ---------------------------------------------------------------------------
if [[ -n "${F04}" ]]; then
  sp_range_violations=$(_py check-range --file "${F04}" \
    --mincol "SP Min" --maxcol "SP Max")
  if [[ -z "${sp_range_violations}" ]]; then
    _check "range/04/SP-Min-le-Max" "PASS" "all rows OK"
  else
    while IFS= read -r line; do
      [[ -z "${line}" ]] && continue
      _check "range/04/SP-Min-le-Max" "FAIL" "row=${line}"
    done <<< "${sp_range_violations}"
  fi

  hr_range_violations=$(_py check-range --file "${F04}" \
    --mincol "Hours Min" --maxcol "Hours Max")
  if [[ -z "${hr_range_violations}" ]]; then
    _check "range/04/Hours-Min-le-Max" "PASS" "all rows OK"
  else
    while IFS= read -r line; do
      [[ -z "${line}" ]] && continue
      _check "range/04/Hours-Min-le-Max" "FAIL" "row=${line}"
    done <<< "${hr_range_violations}"
  fi
fi

# ---------------------------------------------------------------------------
# 6. Per-row range: SP Min <= SP Max and Hours Min <= Hours Max (file 13)
# ---------------------------------------------------------------------------
if [[ -n "${F13}" ]]; then
  sp13_range=$(_py check-range --file "${F13}" --mincol "SP Min" --maxcol "SP Max")
  if [[ -z "${sp13_range}" ]]; then
    _check "range/13/SP-Min-le-Max" "PASS" "all rows OK"
  else
    while IFS= read -r line; do
      [[ -z "${line}" ]] && continue
      _check "range/13/SP-Min-le-Max" "FAIL" "row=${line}"
    done <<< "${sp13_range}"
  fi

  hr13_range=$(_py check-range --file "${F13}" --mincol "Hours Min" --maxcol "Hours Max")
  if [[ -z "${hr13_range}" ]]; then
    _check "range/13/Hours-Min-le-Max" "PASS" "all rows OK"
  else
    while IFS= read -r line; do
      [[ -z "${line}" ]] && continue
      _check "range/13/Hours-Min-le-Max" "FAIL" "row=${line}"
    done <<< "${hr13_range}"
  fi
fi

# ---------------------------------------------------------------------------
# 7. Phase cap: no phase Hours Max > 160 (file 13, per phase row)
# ---------------------------------------------------------------------------
if [[ -n "${F13}" ]]; then
  cap_violations=$(_py check-phase-cap --file "${F13}" \
    --maxcol "Hours Max" --cap 160 --label-col "Phase" \
    --skip-labels "TOTAL,Buffer")
  if [[ -z "${cap_violations}" ]]; then
    _check "phase-cap/13/Hours-Max-le-160" "PASS" "all phases OK"
  else
    while IFS= read -r line; do
      [[ -z "${line}" ]] && continue
      _check "phase-cap/13/Hours-Max-le-160" "FAIL" "phase=${line}"
    done <<< "${cap_violations}"
  fi
fi

# ---------------------------------------------------------------------------
# 8. Per-row range: Hours Min <= Hours Max (file 07)
# ---------------------------------------------------------------------------
if [[ -n "${F07}" ]]; then
  hr07_range=$(_py check-range --file "${F07}" --mincol "Hours Min" --maxcol "Hours Max")
  if [[ -z "${hr07_range}" ]]; then
    _check "range/07/Hours-Min-le-Max" "PASS" "all rows OK"
  else
    while IFS= read -r line; do
      [[ -z "${line}" ]] && continue
      _check "range/07/Hours-Min-le-Max" "FAIL" "row=${line}"
    done <<< "${hr07_range}"
  fi

  # Phase cap for 07 as well (budget rows represent phases)
  cap07=$(_py check-phase-cap --file "${F07}" \
    --maxcol "Hours Max" --cap 160 \
    --skip-labels "TOTAL,Buffer,Subtotal")
  if [[ -z "${cap07}" ]]; then
    _check "phase-cap/07/Hours-Max-le-160" "PASS" "all rows OK"
  else
    while IFS= read -r line; do
      [[ -z "${line}" ]] && continue
      _check "phase-cap/07/Hours-Max-le-160" "FAIL" "row=${line}"
    done <<< "${cap07}"
  fi
fi

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
