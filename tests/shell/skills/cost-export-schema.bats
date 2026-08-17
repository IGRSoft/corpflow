#!/usr/bin/env bats
# tests/shell/skills/cost-export-schema.bats
# Target: the `--export` CSV contract in commands/cost-report.md § CSV Export,
# and the golden export under tests/fixtures/skills/cost-export/.
#
# `/cost-report` is a prompt spec, not an executable — there is no aggregator to
# run. What is falsifiable is the agreement between the three artefacts a run has
# to reconcile: the JSONL the hook writes, the CSV the spec tells the model to
# write, and the `### By Stage` markdown table the same numbers are printed in.
# Each test below pins one of those joins, so a schema edit that touches only one
# of the three turns this red instead of shipping a silently divergent export.
#
# The strict-CSV assertions parse with python's csv module at delimiter=';' —
# the parse a spreadsheet import performs, and the only way an unquoted delimiter
# shows up as the column shift it actually causes rather than as a byte diff.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

DOC="commands/cost-report.md"
RATES="skills/shared/model-selection.md"

HEADER='stage;tokens;model;cost;% of total'

setup() {
  export FIX="${FIXTURES}/skills/cost-export"
  export CSV="${FIX}/cost-report.csv"
  export DOC_ABS="${PLUGIN_ROOT}/${DOC}"
  export RATES_ABS="${PLUGIN_ROOT}/${RATES}"
}

@test "header: the golden CSV header is the exact column schema, in order" {
  run head -1 "$CSV"
  assert_success
  assert_output "$HEADER"
}

@test "doc parity: the § CSV Example block is byte-identical to the golden CSV" {
  # Two copies of the schema exist by necessity — the spec has to show the model
  # what to emit, the fixture has to be checkable. This is the join that keeps
  # editing one from leaving the other behind.
  run python3 - "$DOC_ABS" "$CSV" <<'PY'
import re, sys
doc, csvf = (open(p, encoding="utf-8").read() for p in sys.argv[1:3])
m = re.search(r"### CSV Example\n+```csv\n(.*?)```", doc, re.S)
if not m:
    sys.exit("no ```csv block under '### CSV Example' in the command doc")
if m.group(1) != csvf:
    sys.exit("doc example != fixture\n--- doc ---\n%s--- fixture ---\n%s" % (m.group(1), csvf))
PY
  assert_success
}

@test "shape: five semicolon-delimited fields per row, one row per stage with logs" {
  run python3 - "$CSV" "$FIX/logs" <<'PY'
import csv, glob, io, json, os, sys
raw = open(sys.argv[1], "rb").read()
assert not raw.startswith(b"\xef\xbb\xbf"), "UTF-8 BOM would land in the first header cell"
raw.decode("utf-8")
assert b"\r" not in raw, "CR in line endings; fixtures are LF (tests/fixtures/README.md)"
assert raw.endswith(b"\n"), "no trailing newline"

rows = list(csv.reader(io.StringIO(raw.decode("utf-8")), delimiter=";"))
assert all(len(r) == 5 for r in rows), "ragged row: %r" % [r for r in rows if len(r) != 5]

stages = {json.loads(l)["stage"] for f in glob.glob(os.path.join(sys.argv[2], "*.jsonl"))
          for l in open(f, encoding="utf-8") if l.strip()}
got = [r[0] for r in rows[1:]]
assert set(got) == stages, "rows %s vs stages with logs %s" % (got, sorted(stages))
assert len(got) == len(set(got)), "a stage appears twice: %s" % got
PY
  assert_success
}

@test "numbers: tokens and % of total derive from the fixture JSONL" {
  run python3 - "$CSV" "$FIX/logs" <<'PY'
import csv, decimal, glob, io, json, os, sys
tok = {}
for f in glob.glob(os.path.join(sys.argv[2], "*.jsonl")):
    for l in open(f, encoding="utf-8"):
        if l.strip():
            r = json.loads(l)
            tok[r["stage"]] = tok.get(r["stage"], 0) + r["input_tokens"] + r["output_tokens"]
total = sum(tok.values())
rows = list(csv.DictReader(io.StringIO(open(sys.argv[1], encoding="utf-8").read()), delimiter=";"))
for r in rows:
    s = r["stage"]
    assert r["tokens"] == str(tok[s]), "%s tokens %s != %d" % (s, r["tokens"], tok[s])
    pct = (decimal.Decimal(tok[s]) * 100 / total).quantize(decimal.Decimal("1"), decimal.ROUND_HALF_UP)
    assert r["% of total"] == str(pct), "%s pct %s != %s" % (s, r["% of total"], pct)
PY
  assert_success
}

@test "numbers: cost derives from the § Cost Tiers rate, bare and half-up to 3dp" {
  # Rates are read from model-selection.md rather than hardcoded: the doc forbids
  # restating them, so a rate change must break this fixture loudly, not drift.
  run python3 - "$CSV" "$RATES_ABS" <<'PY'
import csv, io, re, sys
from decimal import Decimal, ROUND_HALF_UP
rates = dict(re.findall(r"\|\s*\*\*(\w+)\*\*\s*\|[^|]*\|\s*~?\$([0-9.]+)", open(sys.argv[2], encoding="utf-8").read()))
assert rates, "no § Cost Tiers rate table parsed out of model-selection.md"
for r in csv.DictReader(io.StringIO(open(sys.argv[1], encoding="utf-8").read()), delimiter=";"):
    assert re.fullmatch(r"\d+", r["tokens"]), "tokens %r is not a bare integer" % r["tokens"]
    assert re.fullmatch(r"\d+\.\d{3}", r["cost"]), "cost %r is not a bare 3dp number" % r["cost"]
    assert re.fullmatch(r"\d{1,3}", r["% of total"]), "%% of total %r carries a sign" % r["% of total"]
    rate = rates.get(r["model"])
    assert rate, "model %r has no rate row" % r["model"]
    want = (Decimal(r["tokens"]) * Decimal(rate) / 1000000).quantize(Decimal("0.001"), ROUND_HALF_UP)
    assert r["cost"] == str(want), "%s cost %s != %s at $%s/1M" % (r["stage"], r["cost"], want, rate)
PY
  assert_success
}

@test "parity: every CSV cell equals its ### By Stage markdown cell" {
  # The gate the export exists to serve: a spreadsheet must show what the report
  # showed. Markdown's $ , and % are presentation and are stripped, nothing else.
  run python3 - "$CSV" "$DOC_ABS" <<'PY'
import csv, io, sys
doc = open(sys.argv[2], encoding="utf-8").read().splitlines()
i = doc.index("### By Stage")
md = []
for ln in doc[i + 1:]:
    if not ln.startswith("|"):
        break
    c = [x.strip() for x in ln.strip("|").split("|")]
    if c[0] in ("Stage", "-------") or set(c[0]) <= {"-"} or c[1] == "-":
        continue
    md.append([c[0], c[1].replace(",", ""), c[2], c[3].lstrip("$"), c[4].rstrip("%")])
rows = [r for r in csv.reader(io.StringIO(open(sys.argv[1], encoding="utf-8").read()), delimiter=";")][1:]
assert md, "no data rows parsed out of the ### By Stage table"
assert md == rows, "markdown %s != csv %s" % (md, rows)
PY
  assert_success
}

@test "escaping: a delimiter-bearing model is quoted and shifts no column" {
  run python3 - "$FIX/escaping/cost-report.csv" "$FIX/escaping/logs" <<'PY'
import csv, glob, io, json, os, sys
raw = open(sys.argv[1], encoding="utf-8").read()
assert '"sonnet;fallback"' in raw, "the delimiter-bearing cell is not quoted in the file"
rows = list(csv.DictReader(io.StringIO(raw), delimiter=";"))
assert len(rows) == 1 and len(rows[0]) == 5, "quoting shifted columns: %r" % rows
model = json.loads(open(glob.glob(os.path.join(sys.argv[2], "*.jsonl"))[0], encoding="utf-8").readline())["model"]
assert rows[0]["model"] == model, "%r != source value %r" % (rows[0]["model"], model)
assert rows[0]["cost"] == "0.012" and rows[0]["% of total"] == "100", "columns after the quoted cell moved: %r" % rows[0]
PY
  assert_success
}

@test "drift: § CSV Export cites csv-export-templates instead of restating it" {
  # The mitigation for schema drift is a citation, so it is the citation that is
  # asserted — a copied delimiter/encoding table would pass every test above.
  run python3 - "$DOC_ABS" <<'PY'
import re, sys
doc = open(sys.argv[1], encoding="utf-8").read()
sec = doc[doc.index("## CSV Export"):doc.index("## Alert Thresholds")]
assert "skills/csv-export-templates/SKILL.md" in sec, "§ CSV Export cites no format source"
for restated in ("Semicolon (;)", "| Delimiter |", "| Encoding |"):
    assert restated not in sec, "§ CSV Export restates the format table (%r) instead of citing it" % restated
PY
  assert_success
}
