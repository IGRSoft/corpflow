---
name: appstore-info
description: Scaffold App Store publishing folder and generate bilingual EN/UA listing content from README
argument-hint: <app name or bundle ID>
model: sonnet
---

# App Store Info Command

Scaffold the `AppStore/` publishing folder and generate all required App Store listing fields in English and Ukrainian, sourced from the project README. If no README exists, it is generated from source code before proceeding.

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

## Steps

When invoked, execute these steps in order:

### Step 1 — README Pre-check

Check whether `README.md` exists at the project root.

- **If missing**: Inspect the source tree to detect the project type (look for `.xcodeproj`, `.xcworkspace`, `Package.swift`, `package.json`, `pubspec.yaml`, `build.gradle`, etc.). Read key source files to understand the app's purpose, features, and technology stack, then create a concise `README.md` with at minimum: App Name, Description, Key Features, Requirements, Installation/Usage.
- **If present**: Read it to extract app metadata for the listing files.

### Step 2 — Scaffold Folder Structure

Create the following structure under the project root (skip any path that already exists):

```
AppStore/
├── en/
│   └── info.md
├── ua/
│   └── info.md
├── images/
└── changelog.md
```

- `images/` is created as an empty directory for screenshots and promotional artwork.
- `changelog.md` is created with a starter template if it does not already exist.

### Step 3 — Generate `AppStore/en/info.md`

Populate all App Store Connect listing fields in English using content extracted from README.md:

```markdown
# App Store Listing — English (EN)

## App Name
<!-- Max 30 characters -->
[App Name]

## Subtitle
<!-- Max 30 characters -->
[Short value proposition]

## Promotional Text
<!-- Max 170 characters. Can be updated without a new app submission. -->
[Current promotion or highlight]

## Description
<!-- Max 4000 characters -->
[Full app description — features, benefits, use cases]

## Keywords
<!-- Max 100 characters total, comma-separated -->
[keyword1, keyword2, keyword3, ...]

## Support URL
[https://your-support-url.com]

## Marketing URL
<!-- Optional -->
[https://your-marketing-url.com]

## Privacy Policy URL
[https://your-privacy-policy-url.com]

## What's New
<!-- Max 4000 characters. See AppStore/changelog.md for history. -->
[Latest release highlights]

## Age Rating
[4+]

## Primary Category
[e.g., Productivity]

## Secondary Category
<!-- Optional -->
[e.g., Utilities]
```

### Step 4 — Generate `AppStore/ua/info.md`

Translate and adapt the English content into Ukrainian. All field names stay in English; values are in Ukrainian. Follow the same structure as `en/info.md`. Ensure natural-sounding Ukrainian phrasing rather than literal translation.

### Step 5 — Print Summary Report

Output a summary of what was created or skipped.

## Examples

```
# Generate all files for the current project
/appstore-info

# Preview without writing files
/appstore-info --dry-run

# Generate Ukrainian listing only
/appstore-info --lang ua

# Generate README only (no AppStore folder)
/appstore-info --readme-only

# Run against a specific project directory
/appstore-info --path ~/projects/MyApp
```

## Output Format

```markdown
# App Store Info — Summary

## README
| Status | File |
|--------|------|
| ✅ Found | README.md |

## Files Created

| Status | File |
|--------|------|
| ✅ Created | AppStore/en/info.md |
| ✅ Created | AppStore/ua/info.md |
| ✅ Created | AppStore/images/ |
| ✅ Created | AppStore/changelog.md |

## App Metadata Extracted

| Field | Value |
|-------|-------|
| App Name | [Detected name] |
| Primary Category | [Detected or inferred] |
| Keywords | [Comma-separated list] |

## Next Steps

1. Review and customise `AppStore/en/info.md`
2. Review and customise `AppStore/ua/info.md`
3. Add screenshots and promotional artwork to `AppStore/images/`
4. Update `AppStore/changelog.md` with release history
5. Fill in placeholder URLs (Support URL, Privacy Policy URL)
```

## Integration

This command is used:
- At the **RE stage** — prepare App Store metadata before submission
- When releasing a new app or significant version
- When adding Ukrainian localisation to an existing App Store listing
- Alongside `/release-notes` to populate the "What's New" field

## Related

- [release-engineer](../agents/release-engineer.md) - Release Engineering stage
- [technical-writer](../agents/technical-writer.md) - Documentation
- [release-notes](./release-notes.md) - Generate "What's New" content
- [readme-update](./readme-update.md) - Keep README in sync
- [workflow](./workflow.md) - RE stage in release workflow
