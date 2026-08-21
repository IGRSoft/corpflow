---
name: appstore-info
description: 'Apple-only. Scaffold the App Store publishing folder and generate bilingual EN/UA listing content from README.'
argument-hint: '[--lang en|ua|all] [--path <dir>] [--readme-only] [--dry-run]'
model: sonnet
allowed-tools: Read, Glob, Grep, Write
related:
  - agents/release-engineer.md
  - agents/technical-writer.md
  - commands/docs-release-notes.md
  - commands/docs-readme.md
  - commands/worktask.md
---

# App Store Info Command

> **Apple-only.** This command targets the Apple App Store listing format and has no
> equivalent on other platforms. The rest of the corpflow plugin is platform-neutral.

Scaffold the `AppStore/` publishing folder and generate every required App Store listing field in English and Ukrainian from the project README — generating the README from source code first if it is missing.

## Usage

```
/appstore-info
/appstore-info --lang <en|ua|all>
/appstore-info --path <project-root>
/appstore-info --readme-only
/appstore-info --dry-run
```

## Options

- `--path <dir>` - Project root directory (default: current working directory)
- `--lang <en|ua|all>` - Generate listing for specified language(s) (default: all)
- `--readme-only` - Only generate/update README.md, skip AppStore folder creation
- `--dry-run` - Preview all output without writing any files

## Step 1 — README Pre-check

- **Present**: read `README.md` for the listing metadata.
- **Missing**: detect the project type (`.xcodeproj`, `.xcworkspace`, `Package.swift`, `package.json`, `pubspec.yaml`, `build.gradle`, …), read key sources for purpose, features, and stack, then write a concise `README.md` covering at minimum App Name, Description, Key Features, Requirements, Installation/Usage.

## Step 2 — Scaffold Folder Structure

Create under the project root, skipping any path that already exists: `AppStore/en/info.md`, `AppStore/ua/info.md`, `AppStore/images/` (empty directory for screenshots and promotional artwork), and `AppStore/changelog.md` (starter template).

## Step 3 — Generate `AppStore/en/info.md`

Title the file `# App Store Listing — English (EN)`, then emit one `##` section per row below, in order, each carrying its Comment as an HTML comment and its value from README.md (bracketed placeholder where unknown).

### `info.md` template — listing fields

| Section | Comment | Value |
|---------|---------|-------|
| `## App Name` | Max 30 characters | `[App Name]` |
| `## Subtitle` | Max 30 characters | `[Short value proposition]` |
| `## Promotional Text` | Max 170 characters. Can be updated without a new app submission. | `[Current promotion or highlight]` |
| `## Description` | Max 4000 characters | `[Full app description — features, benefits, use cases]` |
| `## Keywords` | Max 100 characters total, comma-separated | `[keyword1, keyword2, keyword3, ...]` |

### `info.md` template — URLs, release info & categories

| Section | Comment | Value |
|---------|---------|-------|
| `## Support URL` | — | `[https://your-support-url.com]` |
| `## Marketing URL` | Optional | `[https://your-marketing-url.com]` |
| `## Privacy Policy URL` | — | `[https://your-privacy-policy-url.com]` |
| `## What's New` | Max 4000 characters. See AppStore/changelog.md for history. | `[Latest release highlights]` |
| `## Age Rating` | — | `[4+]` |
| `## Primary Category` | — | `[e.g., Productivity]` |
| `## Secondary Category` | Optional | `[e.g., Utilities]` |

## Step 4 — Generate `AppStore/ua/info.md`

Same structure and field names as `en/info.md` (names stay English, values Ukrainian). Adapt rather than translate literally — the Ukrainian must sound natural.

## Step 5 — Print Summary Report

Report what was created or skipped, per § Output Format.

## Examples

```
/appstore-info                         # generate all files for the current project
/appstore-info --dry-run               # preview without writing files
/appstore-info --lang ua               # Ukrainian listing only
/appstore-info --readme-only           # README only, no AppStore folder
/appstore-info --path ~/projects/MyApp # specific project directory
```

## Output Format

```markdown
# App Store Info — Summary

## README                    ← table: Status | File
## Files Created             ← table: Status | File (one row per scaffolded path)
## App Metadata Extracted    ← table: Field | Value (App Name, Primary Category, Keywords)
## Next Steps                ← review en/ua info.md → add artwork to AppStore/images/ →
                               update AppStore/changelog.md → fill placeholder URLs
```

## Integration

**RE stage** — prepare App Store metadata before submission: a new app or significant version, added Ukrainian localisation, or alongside `/docs-release-notes` to fill "What's New".
