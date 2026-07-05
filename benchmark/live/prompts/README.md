# Live dispatch stage prompts (DV0e)

One `<stage>.txt` per pipeline stage (PL, AR, TL, DV, DR, SR, QA, DC, FN, ST). Each
file is **section [5] (the dynamic task text) ONLY**. At dispatch time,
`benchmark/live/preamble.py::assemble_stage_prompt` PREPENDS the production
cache-prefix sections — [1] contract-reminder, [2] worktask-header, [3] state-json,
[4] stage-contract — in binding order (REQ-1 / AC-1), so the live A/B measures the
same cache-prefix byte layout production ships (not a bare flat prompt). The
assembled `[1][2][3][4][5]` string is fed on stdin to:

```
claude -p --model <m> --effort <e> \
  --permission-mode default --output-format json --agent <agent>   # assembled prompt on stdin
```

(Subprocess specifies `cwd=<workdir>` since `claude -p` has no `--cwd` flag.)

The marker literals (`<<<contract-reminder>>>`, `<<<worktask-header>>>`,
`<<<state-json>>>`, `<<<stage-contract>>>`, `<<<task>>>`) match
`skills/worktask/references/cache-lint.sh` exactly, so a captured live prompt-log
can be linted by the SAME `prefix_lint` that guards production.

The benchmark workload is a **real runnable Python Tic-Tac-Toe app** (CLI + optional
curses TUI, stdlib `unittest`, no third-party deps — Python 3.14). The live A/B
measures the FULL worktask pipeline authoring that app end-to-end, with REAL
tokens/cost summed per stage and budget-capped.

These prompts are deterministic, stdlib-only, and contain NO secrets. They are only
ever read on an opt-in `--live` run (never `make benchmark` / `make test`).
