---
name: create-pr
description: >
  Generate a conventional commit message from staged changes and workflow
  artifacts, commit the changes, and open a pull request to the parent branch.
  Use this skill whenever the user wants to commit and submit a PR — especially
  after finishing a workflow stage or feature. Trigger on: "create a PR",
  "commit and PR", "push and open PR", "submit my changes", "finish and create PR".
argument-hint: '[--draft] [--base <branch>]'
allowed-tools: Read, Glob, Grep, Bash(git *), Bash(gh *)
model: sonnet
---

# Create PR

Generate a commit message, commit staged changes, and open a PR to the parent branch.

## Steps

### 1. Gather Context

**Workflow artifacts** (read if present, skip gracefully if not):
- Find the latest planning file via Glob (`planning-*.md`)
- Find the latest developer-review file via Glob (`developer-review-*.md`)
- Find the latest testing file via Glob (`testing-*.md`)
- Find `state.json` via Glob for issue ref and stage verdicts

**Git state**:
- `git status` — staged/unstaged files
- `git diff --staged` — what's staged
- `git diff HEAD` — all local changes (fallback if nothing staged)
- `git log --oneline -5` — recent commit style for this repo
- Current branch: `git branch --show-current`

### 2. Generate Commit Message

Follow `skills/shared/git-conventions.md` (Conventional Commits 1.0.0):

```
#<issue> <type>[scope][!]: <short summary>   (max 72 chars)

[Optional body: explain WHY]

[Optional footer: issue refs, breaking changes]
```

**Determine type** from workflow context or git diff:
- Planning goal mentions new feature → `feat`
- Planning goal mentions bug/crash → `fix`
- Only tests changed → `test`
- Only docs changed → `docs`
- Only build/CI changed → `build`/`ci`
- Structural refactor, no behaviour change → `refactor`
- Default → `feat`

**Determine scope** (optional, keep short):
- Single module/component → use its name
- Cross-cutting changes → omit scope

**Issue ref**: Extract from `state.json → metadata.issue` or first `#` reference in planning file header. Omit if not found.

**Breaking change**: Add `!` suffix if planning file or developer-review notes breaking API changes.

Rules:
- Present tense, capitalise summary, no trailing period
- Never add "Generated with" or "Co-Authored-By" footers

### 3. Stage and Commit

1. Show the user the generated commit message and a summary of what will be committed.
2. If nothing is staged (`git diff --cached --quiet`), stage tracked changes: `git add -u`
3. Confirm with the user before committing (unless `--auto` flag passed).
4. Commit using a heredoc to preserve formatting:

```bash
git commit -m "$(cat <<'EOF'
<message>
EOF
)"
```

### 4. Push Branch

```bash
git push -u origin HEAD
```

If push fails due to upstream divergence, report the error and stop — do not force-push.

### 5. Determine Base Branch

Priority order:
1. `--base <branch>` argument (if provided)
2. `git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@'`
3. Fallback: `master`

### 6. Check for Existing PR

```bash
gh pr list --head "$(git branch --show-current)" --json number,url --jq '.[0]'
```

If a PR already exists, print its URL and stop — do not create a duplicate.

### 7. Create Pull Request

**PR title**: Same as commit summary line (without issue prefix).

**PR body** — build from available sources in this priority order:
```markdown
## Motivation
<from planning goal, or summarised from git diff>

## Changes
<bullet list from git diff --stat or complete-summary artifact>

## Test plan
<from QA verdict in testing artifact, or generic checklist>

## Notes
<DR verdict, risks, follow-ups if available; omit section if nothing to add>

Closes #<issue>
```

The trailing `Closes #<issue>` line is **mandatory** when the workflow has a linked issue (resolved per `agents/project-manager.md § FN Stage` PR-issue-link validator). Omit only when no issue number is resolvable from any source.

Create PR:
```bash
gh pr create \
  --base "<base-branch>" \
  --title "<title>" \
  --body "$(cat <<'EOF'
## Motivation
<...>

## Changes
<...>

## Test plan
<...>

## Notes
<...>

Closes #<issue>
EOF
)" \
  [--draft if --draft flag passed]
```

Print the resulting PR URL.

## Options

| Flag | Effect |
|------|--------|
| `--draft` | Create PR as draft |
| `--base <branch>` | Override base branch detection |

## Safety Rules

- Never force-push
- Never commit `.env`, credentials, or `*.key` files
- If merge conflicts detected (`git status` shows "both modified"), stop and report
- Confirm commit message with user before committing (unless `--auto`)

## Related

- `skills/shared/git-conventions.md` — Commit format reference
- `agents/project-manager.md` — FN stage PR creation (full workflow)
- `create-release-notes.md` — Post-PR release notes
