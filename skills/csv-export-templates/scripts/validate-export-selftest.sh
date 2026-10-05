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
  # Carries a non-zero Buffer in 01, 05, 07 and 13, and TOTAL rows as wide as
  # their headers, so a validator that drops the buffer or a template that
  # shifts a total fails here.
  local pdir="${tmpdir}/pass"
  mkdir -p "${pdir}"

  # shellcheck disable=SC2016  # $ in CSV cost columns are literal, not expansions
  printf '%s\n' \
    'Category;Value Min;Value Max;Notes' \
    'Hourly Rate;$100;;' \
    'Base Hours;60;120;SP Min/Max × 6h multiplier' \
    'Buffer (15%);9;18;Contingency' \
    'Total Hours;69;138;Base + buffer' \
    > "${pdir}/01_project_overview.csv"

  printf '%s\n' \
    'Feature Group;Feature;Subtask;Size;SP Min;SP Max;Hours Min;Hours Max;Priority;Phase' \
    'Auth;Login;OAuth + tests;M;4;7;24;42;P0;1' \
    'Auth;Logout;Session clear + tests;S;2;5;12;30;P1;1' \
    'Profile;Edit;Profile form + tests;M;4;8;24;48;P1;2' \
    > "${pdir}/04_features_breakdown.csv"

  printf '%s\n' \
    'Phase;Week;Milestone;Deliverables;SP Min;SP Max;Hours Min;Hours Max;Dependencies' \
    '1;1-2;Core;Auth;6;12;36;72;-' \
    '2;3-4;Profile;Profile form;4;8;24;48;1' \
    'Buffer;5;Contingency;"Risk mitigation, feedback";;;9;18;All phases' \
    'TOTAL;;;;10;20;69;138;' \
    > "${pdir}/05_roadmap_milestones.csv"

  # shellcheck disable=SC2016  # $ in CSV cost columns are literal, not expansions
  printf '%s\n' \
    'Category;Subcategory;SP Min;SP Max;Hours Min;Hours Max;Rate;Cost Min;Cost Max;Percentage;Notes' \
    'Phase 1;Core;6;12;36;72;$100;$3600;$7200;52%;' \
    'Phase 2;Profile;4;8;24;48;$100;$2400;$4800;35%;' \
    'Subtotal;Development;10;20;60;120;$100;$6000;$12000;87%;' \
    'Buffer;Contingency (15%);;;9;18;$100;$900;$1800;13%;Risk mitigation' \
    'TOTAL;;;;69;138;$100;$6900;$13800;100%;' \
    > "${pdir}/07_budget_estimate.csv"

  # shellcheck disable=SC2016  # $ in CSV cost columns are literal, not expansions
  printf '%s\n' \
    'Phase;Name;Duration;Weeks;SP Min;SP Max;Hours Min;Hours Max;Cost Min;Cost Max;Key Deliverables;Dependencies' \
    '1;Core;2 weeks;1-2;6;12;36;72;$3600;$7200;Auth;-' \
    '2;Profile;2 weeks;3-4;4;8;24;48;$2400;$4800;Profile form;1' \
    'Buffer;Contingency;1 weeks;5;;;9;18;$900;$1800;Risk mitigation;All' \
    'TOTAL;;5 weeks;;10;20;69;138;$6900;$13800;;' \
    > "${pdir}/13_phase_summary.csv"

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

  # ---- Same set, comma-delimited (the /estimate --delimiter path) ----
  local cdir="${tmpdir}/comma"
  mkdir -p "${cdir}"
  local f
  for f in "${pdir}"/*.csv; do
    python3 -c 'import csv, sys
w = csv.writer(sys.stdout, delimiter=",", lineterminator="\n")
w.writerows(csv.reader(open(sys.argv[1], encoding="utf-8", newline=""), delimiter=";"))' \
      "${f}" > "${cdir}/${f##*/}"
  done

  printf >&2 'self-test: running comma fixture with --delimiter , (expect exit 0)...\n'
  if bash "$0" --dir "${cdir}" --delimiter , --out "${tmpdir}/report_comma.csv"; then
    printf >&2 'self-test comma fixture: OK (exit 0)\n'
  else
    printf >&2 'self-test FAIL: comma fixture with --delimiter , returned non-zero\n'
    exit 1
  fi

  # ---- FAILING fixture set ----
  local fdir="${tmpdir}/fail"
  mkdir -p "${fdir}"

  # 04: SP sums disagree with 13, and row 1 has SP Min(5) > SP Max(3)
  printf '%s\n' \
    'Feature Group;Feature;Subtask;Size;SP Min;SP Max;Hours Min;Hours Max;Priority;Phase' \
    'Auth;Login;OAuth + tests;M;5;3;18;30;P0;1' \
    'Auth;Logout;Session clear + tests;XS;1;2;6;12;P1;1' \
    > "${fdir}/04_features_breakdown.csv"

  # 13: phase 1 depends on a phase that does not exist; Buffer leaves week 3 uncovered
  # shellcheck disable=SC2016  # $ in CSV cost columns are literal, not expansions
  printf '%s\n' \
    'Phase;Name;Duration;Weeks;SP Min;SP Max;Hours Min;Hours Max;Cost Min;Cost Max;Key Deliverables;Dependencies' \
    '1;Core;2 weeks;1-2;4;7;24;42;$2400;$4200;Auth;2' \
    'Buffer;Contingency;1 weeks;4;;;4;6;$400;$600;Risk mitigation;All' \
    'TOTAL;;3 weeks;;4;7;28;48;$2800;$4800;;' \
    > "${fdir}/13_phase_summary.csv"

  # 07: Hours Max per phase > 160 trips the cap; TOTAL row one field short
  # shellcheck disable=SC2016  # $ in CSV cost columns are literal, not expansions
  printf '%s\n' \
    'Category;Subcategory;SP Min;SP Max;Hours Min;Hours Max;Rate;Cost Min;Cost Max;Percentage;Notes' \
    'Phase 1;Core;4;7;24;200;$100;$2400;$20000;100%;' \
    'TOTAL;;;24;200;$100;$2400;$20000;100%;' \
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

  # Each seeded defect must surface as its own FAIL row.
  local want
  for want in format/file-07 sum/01-vs-13/Hours-Min range/04/SP-Min-le-Max \
    phase-cap/07/Hours-Max-le-160 phase/13/Weeks-continuous phase/13/Dependencies-valid; do
    if ! grep -q "^${want};FAIL;" "${out_fail}"; then
      printf >&2 'self-test ERROR: no %s FAIL row in report_fail.csv\n' "${want}"
      exit 1
    fi
  done
  printf >&2 'self-test: expected FAIL rows found in report: OK\n'

  printf >&2 'self-test: all checks passed\n'
  exit 0
}
