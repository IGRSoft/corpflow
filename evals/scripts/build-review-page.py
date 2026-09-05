#!/usr/bin/env python3
"""build-review-page — emit a self-contained trace-labelling page.

Traces are embedded rather than fetched: the page is opened over file://, where a
fetch of a sibling JSON is blocked, and the responses are gitignored anyway.

Labels live in localStorage and export as JSONL. Nothing is written back to the
repo by the page — a browser cannot, and a label is a human judgement that should
land in evals/ deliberately rather than as a side effect of clicking.

Usage: build-review-page.py [--eval-set PATH] [--responses DIR] [--out PATH]
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import sys

import importlib.util

_ENGINE_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "eval-engine.py")
_spec = importlib.util.spec_from_file_location("eval_engine", _ENGINE_PATH)
engine = importlib.util.module_from_spec(_spec)
sys.modules["eval_engine"] = engine
_spec.loader.exec_module(engine)

PAGE = """<!doctype html>
<meta charset="utf-8">
<title>__SKILL_NAME__ trace review</title>
<style>
:root{--bg:#fbfaf8;--fg:#1d1c1a;--mut:#6b6862;--line:#e2ded7;--card:#fff;
--pass:#1a7f4b;--fail:#b3261e;--defer:#8a6d1f;--accent:#2f5fa8}
@media (prefers-color-scheme:dark){:root{--bg:#17181a;--fg:#e8e6e3;--mut:#9b9792;
--line:#2e3033;--card:#1e2022;--pass:#4ec98a;--fail:#f2837a;--defer:#d8b44a;--accent:#7aa6e8}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.6 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}
header{position:sticky;top:0;z-index:9;background:var(--bg);border-bottom:1px solid var(--line);
padding:10px 20px;display:flex;gap:14px;align-items:center;flex-wrap:wrap}
.count{font-variant-numeric:tabular-nums;color:var(--mut)}
.wrap{display:grid;grid-template-columns:minmax(0,1fr) 320px;gap:18px;padding:18px 20px;align-items:start}
@media(max-width:900px){.wrap{grid-template-columns:minmax(0,1fr)}}
.card{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:16px 18px}
.side{position:sticky;top:60px}
h1{font-size:15px;margin:0;font-weight:650}
h2{font-size:16px;margin:18px 0 6px}
h3{font-size:14px;margin:14px 0 4px}
.prompt{border-left:3px solid var(--accent);padding:8px 12px;background:color-mix(in oklab,var(--accent) 8%,transparent);
border-radius:0 6px 6px 0;margin-bottom:14px}
.prompt b{color:var(--mut);font-weight:600;font-size:12px;letter-spacing:.04em;text-transform:uppercase;display:block}
button{font:inherit;padding:7px 14px;border-radius:7px;border:1px solid var(--line);background:var(--card);
color:var(--fg);cursor:pointer}
button:hover{border-color:var(--mut)}
.p{border-color:var(--pass);color:var(--pass)}.f{border-color:var(--fail);color:var(--fail)}
.d{border-color:var(--defer);color:var(--defer)}
.on.p{background:var(--pass);color:#fff}.on.f{background:var(--fail);color:#fff}.on.d{background:var(--defer);color:#fff}
textarea{width:100%;min-height:80px;font:inherit;padding:9px;border-radius:7px;border:1px solid var(--line);
background:var(--bg);color:var(--fg);resize:vertical}
table{border-collapse:collapse;width:100%;margin:8px 0;font-size:14px;display:block;overflow-x:auto}
th,td{border:1px solid var(--line);padding:5px 9px;text-align:left}
th{background:color-mix(in oklab,var(--fg) 5%,transparent)}
code{background:color-mix(in oklab,var(--fg) 7%,transparent);padding:1px 5px;border-radius:4px;font-size:13px}
pre{background:color-mix(in oklab,var(--fg) 6%,transparent);padding:10px;border-radius:7px;overflow-x:auto}
pre code{background:none;padding:0}
.tag{font-size:11px;padding:2px 8px;border-radius:99px;border:1px solid var(--line);color:var(--mut);
text-transform:uppercase;letter-spacing:.04em}
.k{color:var(--mut);font-size:12px}
select{font:inherit;padding:6px;border-radius:6px;border:1px solid var(--line);background:var(--card);color:var(--fg)}
.done{color:var(--pass)}.miss{color:var(--fail)}
ul{margin:6px 0;padding-left:20px}
.exp{width:100%;min-height:150px;font-family:ui-monospace,monospace;font-size:12px}
</style>
<header>
  <h1>__SKILL_NAME__ review</h1>
  <span class="count" id="pos"></span>
  <span class="count" id="tally"></span>
  <select id="filter">
    <option value="all">all traces</option>
    <option value="unlabeled">unlabeled only</option>
    <option value="dev">dev split</option>
    <option value="test">test split</option>
    <option value="clarify">expected clarify</option>
  </select>
  <button onclick="nav(-1)">&larr;</button><button onclick="nav(1)">&rarr;</button>
  <button class="p" onclick="mark('pass')">Pass <span class="k">1</span></button>
  <button class="f" onclick="mark('fail')">Fail <span class="k">2</span></button>
  <button class="d" onclick="mark('defer')">Defer <span class="k">d</span></button>
  <button onclick="undo()">Undo <span class="k">u</span></button>
  <button onclick="exportLabels()">Export</button>
</header>
<div class="wrap">
  <main>
    <div class="card">
      <div class="prompt"><b>Request</b><span id="prompt"></span></div>
      <div id="body"></div>
    </div>
  </main>
  <aside class="side">
    <div class="card">
      <h3 style="margin-top:0">Your verdict</h3>
      <div id="verdict" class="k">unlabeled</div>
      <textarea id="note" placeholder="What went wrong? Observations, not explanations."></textarea>
      <h3>Case</h3>
      <div id="meta" class="k"></div>
      <h3>Grounded on</h3>
      <div id="ground" class="k"></div>
      <h3>Harness said</h3>
      <div id="harness" class="k"></div>
      <details><summary class="k">Deferred criteria</summary><div id="deferred" class="k"></div></details>
      <details><summary class="k">Keys</summary>
        <div class="k">&larr;/&rarr; navigate &middot; 1 pass &middot; 2 fail &middot; d defer &middot; u undo</div>
      </details>
    </div>
  </aside>
</div>
<script id="data" type="application/json">__DATA__</script>
<script>
const TRACES = JSON.parse(document.getElementById('data').textContent);
// Keyed on the eval-set version, not just the skill. Browsers share one
// localStorage partition across file:// pages, so a version-blind key let notes
// from an older capture restore into a newer labelling session: 8 notes came back
// tagged [v050] and 10 named assertions the capture never fired. The verdicts were
// regenerated and matched; only the free text was stale, which is the hard kind to
// notice.
// Scoped by SKILL and eval-set version. Browsers keep one localStorage
// partition across all file:// pages, so a key missing either dimension is a
// silent cross-store read: a skill-blind key would have merged two eval sets
// that happened to share a version, and a version-blind one once restored
// eight notes from an older capture naming assertions it never fired.
const KEY = '__SKILL_NAME__-labels-__EVAL_SET_VERSION__';
let labels = JSON.parse(localStorage.getItem(KEY) || '{}');
let history = [];
let idx = 0;

const esc = s => s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');

// Minimal markdown: the traces are plans, so headings, tables, code, lists and
// bold carry all the structure a reviewer judges.
function md(src){
  const lines = esc(src).split('\\n');
  let out = [], inCode = false, inTable = false, inList = false;
  const closeList = () => { if(inList){ out.push('</ul>'); inList = false; } };
  const closeTable = () => { if(inTable){ out.push('</table>'); inTable = false; } };
  for (let raw of lines){
    if (/^```/.test(raw)){ closeList(); closeTable();
      out.push(inCode ? '</code></pre>' : '<pre><code>'); inCode = !inCode; continue; }
    if (inCode){ out.push(raw); continue; }
    let l = raw.replace(/`([^`]+)`/g,'<code>$1</code>')
               .replace(/\\*\\*([^*]+)\\*\\*/g,'<strong>$1</strong>');
    if (/^\\s*\\|/.test(l)){
      const cells = l.trim().replace(/^\\||\\|$/g,'').split('|');
      if (/^[\\s|:-]+$/.test(l)) continue;
      if (!inTable){ out.push('<table>'); inTable = true;
        out.push('<tr>'+cells.map(c=>'<th>'+c.trim()+'</th>').join('')+'</tr>'); continue; }
      out.push('<tr>'+cells.map(c=>'<td>'+c.trim()+'</td>').join('')+'</tr>'); continue;
    }
    closeTable();
    let m = l.match(/^(#{1,4})\\s+(.*)/);
    if (m){ closeList(); out.push('<h'+(m[1].length+1)+'>'+m[2]+'</h'+(m[1].length+1)+'>'); continue; }
    if (/^\\s*[-*]\\s+/.test(l)){ if(!inList){ out.push('<ul>'); inList = true; }
      out.push('<li>'+l.replace(/^\\s*[-*]\\s+/,'')+'</li>'); continue; }
    closeList();
    if (!l.trim()){ continue; }
    out.push('<p>'+l+'</p>');
  }
  closeList(); closeTable(); if(inCode) out.push('</code></pre>');
  return out.join('\\n');
}

function visible(){
  const f = document.getElementById('filter').value;
  return TRACES.filter(t =>
    f === 'all' ? true :
    f === 'unlabeled' ? !labels[t.id] :
    f === 'clarify' ? t.expected === 'clarify' : t.split === f);
}

function render(){
  const list = visible();
  if (!list.length){ document.getElementById('body').innerHTML = '<p>No traces match.</p>'; return; }
  idx = Math.max(0, Math.min(idx, list.length - 1));
  const t = list[idx];
  document.getElementById('prompt').textContent = t.prompt;
  document.getElementById('body').innerHTML = md(t.response);
  document.getElementById('pos').textContent = `${idx+1} / ${list.length}`;
  const done = Object.keys(labels).length;
  document.getElementById('tally').innerHTML =
    `<span class="done">${done} labeled</span> &middot; <span class="miss">${TRACES.length-done} left</span>`;
  document.getElementById('meta').innerHTML =
    `<span class="tag">${t.type}</span> <span class="tag">${t.grounding}</span> ` +
    `<span class="tag">${t.route}</span> <span class="tag">${t.split}</span><br>` +
    `case ${t.id} &middot; expects <b>${t.expected}</b> &middot; ${t.chars} chars &middot; $${t.cost}`;
  document.getElementById('ground').innerHTML =
    t.ground.length ? t.ground.map(p=>`<code>${p}</code>`).join('<br>') : '<i>nothing — expects a question</i>';
  document.getElementById('harness').innerHTML = t.failed.length
    ? `<span class="miss">FAIL</span> ${t.failed.map(f=>`<code>${f}</code>`).join(' ')}`
    : `<span class="done">${t.status.toUpperCase()}</span>`;
  document.getElementById('deferred').innerHTML = '<ul>'+t.deferred.map(d=>`<li>${d}</li>`).join('')+'</ul>';
  const lab = labels[t.id];
  document.getElementById('verdict').innerHTML = lab
    ? `<b class="${lab.verdict==='pass'?'done':'miss'}">${lab.verdict.toUpperCase()}</b>` : 'unlabeled';
  document.getElementById('note').value = lab ? (lab.note||'') : '';
  document.querySelectorAll('header button').forEach(b=>b.classList.remove('on'));
  if (lab) document.querySelector('header button.'+lab.verdict[0])?.classList.add('on');
}

function mark(verdict){
  const t = visible()[idx]; if(!t) return;
  history.push(JSON.parse(JSON.stringify(labels)));
  labels[t.id] = {verdict, note: document.getElementById('note').value.trim(),
                  split: t.split, type: t.type, grounding: t.grounding, route: t.route};
  save(); nav(1);
}
function undo(){ if(!history.length) return; labels = history.pop(); save(); render(); }
function save(){ localStorage.setItem(KEY, JSON.stringify(labels)); render(); }
function nav(d){
  const t = visible()[idx];
  if (t && labels[t.id]) labels[t.id].note = document.getElementById('note').value.trim();
  localStorage.setItem(KEY, JSON.stringify(labels));
  idx += d; render();
}
function exportLabels(){
  const rows = TRACES.filter(t=>labels[t.id]).map(t=>JSON.stringify({
    case_id: t.id, verdict: labels[t.id].verdict, note: labels[t.id].note,
    split: t.split, type: t.type, grounding: t.grounding, route: t.route,
    harness_status: t.status, harness_failed: t.failed}));
  const ta = document.createElement('textarea');
  ta.className = 'exp'; ta.value = rows.join('\\n');
  const d = document.createElement('div'); d.className = 'card';
  d.innerHTML = '<h3>Labels as JSONL — copy into evals/</h3>';
  d.appendChild(ta);
  document.querySelector('main').prepend(d);
  ta.select();
}
document.getElementById('filter').onchange = () => { idx = 0; render(); };
document.getElementById('note').oninput = () => {
  const t = visible()[idx];
  if (t && labels[t.id]){ labels[t.id].note = document.getElementById('note').value;
    localStorage.setItem(KEY, JSON.stringify(labels)); }
};
addEventListener('keydown', e => {
  if (e.target.tagName === 'TEXTAREA') return;
  if (e.key === 'ArrowRight') nav(1);
  else if (e.key === 'ArrowLeft') nav(-1);
  else if (e.key === '1') mark('pass');
  else if (e.key === '2') mark('fail');
  else if (e.key.toLowerCase() === 'd') mark('defer');
  else if (e.key.toLowerCase() === 'u') undo();
});
render();
</script>
"""


def main(argv) -> int:
    p = argparse.ArgumentParser(prog="build-review-page")
    p.add_argument("--eval-set", default=os.path.join(engine.REPO, "skills", "request-plan", "evals", "evals.json"))
    p.add_argument("--responses", default=None)
    p.add_argument("--grades", default=None, help="eval-grade --json output, for the harness column")
    p.add_argument("--only", default=None,
                   help="JSON list of case ids — the stratified subset worth labelling first")
    # Default names the only eval set that exists; the storage key inside the page
    # is derived from the set's own skill_name, so a second set cannot collide here.
    p.add_argument("--out", default=os.path.join(engine.REPO, "evals", "review", "request-plan-review.html"))
    args = p.parse_args(argv)

    eval_set = engine.load_eval_set(args.eval_set)
    cases = {c["id"]: c for c in eval_set["evals"]}
    responses = engine.responses_dir(args.eval_set, args.responses)

    grades = {}
    if args.grades and os.path.exists(args.grades):
        with open(args.grades, encoding="utf-8") as f:
            grades = {r["case_id"]: r for r in json.load(f)["results"]}

    only = None
    if args.only:
        with open(args.only, encoding="utf-8") as f:
            only = set(json.load(f))

    traces = []
    for path in sorted(glob.glob(os.path.join(responses, "*.json")),
                       key=lambda x: int(os.path.basename(x)[:-5])):
        with open(path, encoding="utf-8") as f:
            rec = json.load(f)
        case = cases.get(rec["case_id"])
        if case is None or (only is not None and rec["case_id"] not in only):
            continue
        grade = grades.get(rec["case_id"], {})
        traces.append({
            "id": rec["case_id"], "prompt": case["prompt"], "response": rec["response"],
            "split": case.get("split", "?"), "expected": case.get("expected_outcome", "plan"),
            "ground": case.get("grounding", []), "deferred": case.get("deferred", []),
            "chars": len(rec["response"]),
            "cost": round(rec.get("usage", {}).get("cost_usd") or 0, 2),
            "status": grade.get("status", "ungraded"), "failed": grade.get("failed", []),
            **case.get("dimensions", {}),
        })

    if not traces:
        sys.stderr.write(f"build-review-page: no responses found in {responses}\n")
        return 1

    payload = json.dumps(traces, ensure_ascii=False).replace("</script>", "<\\/script>")
    version = str(eval_set.get("eval_set_version") or "unversioned")
    skill = str(eval_set.get("skill_name") or "unnamed")
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as f:
        f.write(PAGE.replace("__DATA__", payload)
                    .replace("__EVAL_SET_VERSION__", version)
                    .replace("__SKILL_NAME__", skill))
    print(f"{len(traces)} traces -> {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
