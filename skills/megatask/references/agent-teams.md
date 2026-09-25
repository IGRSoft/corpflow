# Agent Teams Mode (not used)

Megatask does not use agent teams. Nothing in `commands/megatask.md` or `skills/megatask/SKILL.md`
sets `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`: every issue runs as its own `/worktask` under the
Task-based orchestrator, and `hooks/megatask-monitor.sh` settles completions. The Claude Code
event and payload reference for teams stays in
`../../agent-coordination/references/hook-monitoring.md § Agent Teams Lifecycle Hooks`.
