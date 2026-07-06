# Live dispatch stage prompts

One `<stage>.txt` per pipeline stage (PL, AR, TL, DV, DR, SR, QA, DC, FN, ST). Each
file is **section [5] (the dynamic task text) ONLY**. At dispatch time,
`BenchmarkLive/Preamble.assembleStagePrompt` PREPENDS the production
cache-prefix sections — [1] contract-reminder, [2] worktask-header, [3] state-json,
[4] stage-contract — in binding order (REQ-1 / AC-1), so the live A/B measures the
same cache-prefix byte layout production ships (not a bare flat prompt). The
assembled `[1][2][3][4][5]` string is fed on stdin to:

```
claude -p --model <m> --effort <e> \
  --permission-mode default --output-format <json|stream-json> --agent <agent>
```

(Subprocess specifies `cwd=<workdir>` since `claude -p` has no `--cwd` flag.
`stream-json` is the default capture — it additionally yields the per-stage
coverage manifest; see `benchmark/README.md`.)

The marker literals (`<<<contract-reminder>>>`, `<<<worktask-header>>>`,
`<<<state-json>>>`, `<<<stage-contract>>>`, `<<<task>>>`) match
`skills/worktask/references/cache-lint.sh` exactly, so a captured live prompt-log
can be linted by the SAME `prefix_lint` that guards production.

The benchmark workload is a **real runnable SwiftUI multiplatform Tic-Tac-Toe
app** (macOS 15+ / iOS 18+: main menu / game / leaderboard / settings screens,
sound, AI opponent, animated transitions, Swift Testing suite — Swift 6 +
SwiftPM + Apple SDKs ONLY, no third-party packages, no network). The live A/B
measures the FULL worktask pipeline authoring that app end-to-end, with REAL
tokens/cost summed per stage, budget-capped, plus per-stage agent/skill/command
coverage manifests. Each prompt names the plugin surface its stage is expected
to exercise; `PromptCoverageLintTests` (benchmark/harness) pins those tokens
offline, and the live manifest verifies the invocations actually happened.

These prompts are deterministic and contain NO secrets. They are only
ever read on an opt-in `--live` run (never `make benchmark` / `make test`).
