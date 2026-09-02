---
name: appstore
description: 'Store publishing front door — listing metadata, screenshots, or in-app purchases; delegates to the platform plugin''s release engineer (Apple App Store, Google Play).'
argument-hint: '--task <listing|screenshots|iap> [--platform apple|android] [--lang en|ua] [--path <dir>] [--dry-run]'
model: haiku
allowed-tools: Read, Glob, Grep, Task
version: 0.1.0
related:
  - skills/shared/routing-matrix.md
  - skills/shared/platform-detection.md
  - skills/cross-plugin-handoff/SKILL.md
  - agents/release-engineer.md
---

# App Store Publishing

Front door for store publishing. Parses the arguments and hands off — every store flow lives in the
platform plugin that ships to that store, because App Store Connect and Play Console differ field by
field and a shared implementation would be true of neither.

This command **writes nothing**. It holds no `Write` grant: the three commands it replaces each had
one, and none of that writing happens here any more.

## Usage

```
/appstore --task listing
/appstore --task screenshots --platform apple --lang ua
/appstore --task iap --platform apple --bundle com.example.app --dry-run
```

## Options

| Option | Required | Effect |
|--------|----------|--------|
| `--task <listing\|screenshots\|iap>` | yes | The job. `listing` is store-listing metadata, `screenshots` the graphic assets, `iap` the in-app purchase products. |
| `--platform <apple\|android>` | no | Skips detection. Give it in a repo that carries markers for both. |
| everything else | no | Passed through verbatim to the target: `--lang`, `--path`, `--dry-run`, `--bundle`, `--apple-platform`, `--android-form-factor`. |

`--apple-platform` selects an Apple **device class** (`ios`, `macos`, `tvos`, `watchos`) and is
deliberately distinct from the plugin-wide `--platform`. Pass it through; never fold one into the
other.

## What this command does

Dispatch `Task(corpflow:release-engineer)` with the parsed arguments and let it work.

Platform detection, alias resolution, and the sibling dispatch all belong to the agent, not here:
routing policy has exactly one home (`skills/shared/routing-matrix.md`), and no test reads a command
body against it, so a second copy of the resolution rules here would drift unobserved.

Chain depth is session → `release-engineer` (1) → the platform's release engineer (2), inside the
depth-3 cap (`skills/agent-coordination/SKILL.md § Three independent ceilings`).

## Where the work happens

| Platform | Target agent | Commands it runs |
|----------|--------------|------------------|
| apple | `apple-developer:apple-release-engineer` | `/apple-developer:gen-appstore-listing`, `gen-appstore-screenshots`, `gen-appstore-iap` |
| android | `android-developer:and-release-engineer` | `/android-developer:gen-playstore-listing`, `gen-playstore-screenshots` |

Only platforms with a store have a target. `--task iap --platform android` is not supported yet —
Play Billing product setup is not ported.

## Refusals

The agent stops and reports rather than guessing when:

- both apple and android markers are present, or neither is, and no `--platform` was given;
- the resolved plugin is not installed — it names the plugin, the alias, and the direct
  `/<plugin>:<command>` to run instead, and records one `plugin_unavailable` audit row;
- the request is `--task iap` on android.

None of these fall back to doing the work inline. Writing to a live store account on a guessed
platform is the failure this design exists to prevent.

## Relationship to the pipeline

`/appstore` runs **outside** the worktask pipeline and patches no `state.json`. The RE stage is
unchanged: `agents/release-engineer.md` still owns it, and the platform release engineers are
RE-stage *consultation* exactly as the platform architects are for AR.
