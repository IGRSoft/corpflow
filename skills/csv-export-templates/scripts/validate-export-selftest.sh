#!/usr/bin/env bash
# validate-export-selftest.sh — the `--self-test` harness for validate-export.sh.
#
# SOURCED, never executed: validate-export.sh loads this file only on the `--self-test`
# path, so the production path never pays for it. Sourcing leaves the caller's
# `$0` and every function it has already defined in scope — this file reads the
# caller's helpers and is not standalone.
#
# Contract: defines `_self_test`, which owns the exit for this invocation.

# ---------------------------------------------------------------------------
# Self-test
# ---------------------------------------------------------------------------
_self_test() {
  local tmpdir
  tmpdir=$(mktemp -d)
  # shellcheck disable=SC2064  # we want tmpdir expanded now, not at trap time
  trap "rm -rf -- '${tmpdir}'" EXIT INT TERM

  printf >&2 'self-test: creating fixture CSVs in %s\n' "${tmpdir}"

  # ---- PASSING fixture set ----
  local pdir="${tmpdir}/pass"
  mkdir -p "${pdir}"

  # 04_features_breakdown.csv  (SP Min/Max cols; 2 data rows)
  printf '%s\n' \
    'Feature Group;Feature;Subtask;Size;SP Min;SP Max;Hours Min;Hours Max;Priority;Phase' \
    'Auth;Login;OAuth + tests;M;3;5;18;30;P0;1' \
    'Auth;Logout;Session clear + tests;XS;1;2;6;12;P1;1' \
    > "${pdir}/04_features_breakdown.csv"
  # SP Min sum=4, SP Max sum=7, Hours Min sum=24, Hours Max sum=42

  # 13_phase_summary.csv  (matching totals)
  # shellcheck disable=SC2016  # $ in CSV cost columns are literal, not expansions
  printf '%s\n' \
    'Phase;Name;Duration;Weeks;SP Min;SP Max;Hours Min;Hours Max;Cost Min;Cost Max;Key Deliverables;Dependencies' \
    '1;Core;2 weeks;1-2;4;7;24;42;$2400;$4200;Auth;-' \
    'TOTAL;;2 weeks;;4;7;24;42;$2400;$4200;;' \
    > "${pdir}/13_phase_summary.csv"

  # 07_budget_estimate.csv  (Hours Min/Max totals matching 13)
  # shellcheck disable=SC2016  # $ in CSV cost columns are literal, not expansions
  printf '%s\n' \
    'Category;Subcategory;SP Min;SP Max;Hours Min;Hours Max;Rate;Cost Min;Cost Max;Percentage;Notes' \
    'Phase 1;Core;4;7;24;42;$100;$2400;$4200;100%;' \
    'TOTAL;;;4;7;24;42;$100;$2400;$4200;100%;' \
    > "${pdir}/07_budget_estimate.csv"

  # 01_project_overview.csv  (Total Hours row matching 13 summary)
  printf '%s\n' \
    'Category;Value Min;Value Max;Notes' \
    'Total Hours;24;42;Base + buffer' \
    > "${pdir}/01_project_overview.csv"

  printf >&2 'self-test: running PASS fixture (expect exit 0)...\n'
  local out_pass="${tmpdir}/report_pass.csv"
  # `$0`, not BASH_SOURCE: this file is sourced, so BASH_SOURCE[0] names the
  # harness, which has no entry point. `$0` is still the caller.
  if bash "$0" --dir "${pdir}" --out "${out_pass}"; then
    printf >&2 'self-test PASS fixture: OK (exit 0)\n'
  else
    printf >&2 'self-test FAIL: PASS fixture returned non-zero\n'
    exit 1
  fi

  # ---- FAILING fixture set ----
  local fdir="${tmpdir}/fail"
  mkdir -p "${fdir}"

  # 04: SP Max > 13 summary (mismatch), plus a row where Min>Max
  printf '%s\n' \
    'Feature Group;Feature;Subtask;Size;SP Min;SP Max;Hours Min;Hours Max;Priority;Phase' \
    'Auth;Login;OAuth + tests;M;5;3;18;30;P0;1' \
    'Auth;Logout;Session clear + tests;XS;1;2;6;12;P1;1' \
    > "${fdir}/04_features_breakdown.csv"
  # SP Min sum=6, SP Max sum=5 (also row 1 has SP Min(5)>SP Max(3))

  # 13: still says 4/7 — mismatch on both sides
  # shellcheck disable=SC2016  # $ in CSV cost columns are literal, not expansions
  printf '%s\n' \
    'Phase;Name;Duration;Weeks;SP Min;SP Max;Hours Min;Hours Max;Cost Min;Cost Max;Key Deliverables;Dependencies' \
    '1;Core;2 weeks;1-2;4;7;24;42;$2400;$4200;Auth;-' \
    'TOTAL;;2 weeks;;4;7;24;42;$2400;$4200;;' \
    > "${fdir}/13_phase_summary.csv"

  # 07: Hours Max per phase > 160 to trip the cap
  # shellcheck disable=SC2016  # $ in CSV cost columns are literal, not expansions
  printf '%s\n' \
    'Category;Subcategory;SP Min;SP Max;Hours Min;Hours Max;Rate;Cost Min;Cost Max;Percentage;Notes' \
    'Phase 1;Core;4;7;24;200;$100;$2400;$4200;100%;' \
    'TOTAL;;;4;7;24;200;$100;$2400;$4200;100%;' \
    > "${fdir}/07_budget_estimate.csv"

  # 01: deliberately mismatched totals
  printf '%s\n' \
    'Category;Value Min;Value Max;Notes' \
    'Total Hours;99;99;Base + buffer' \
    > "${fdir}/01_project_overview.csv"

  printf >&2 'self-test: running FAIL fixture (expect exit 1)...\n'
  local out_fail="${tmpdir}/report_fail.csv"
  if bash "$0" --dir "${fdir}" --out "${out_fail}"; then
    printf >&2 'self-test FAIL: FAIL fixture returned 0 (should have been 1)\n'
    exit 1
  else
    printf >&2 'self-test FAIL fixture: OK (exit 1 as expected)\n'
  fi

  # Verify report has FAIL rows (format: check;FAIL;detail — FAIL is col 2)
  if grep -q ';FAIL;' "${out_fail}"; then
    printf >&2 'self-test: FAIL rows found in report: OK\n'
  else
    printf >&2 'self-test ERROR: no FAIL rows in report_fail.csv\n'
    exit 1
  fi

  printf >&2 'self-test: all checks passed\n'
  exit 0
}
