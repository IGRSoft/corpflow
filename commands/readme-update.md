---
name: readme-update
description: Update README files based on code changes, keeping documentation in sync with implementation
argument-hint: '[--path README.md]'
model: haiku
allowed-tools: Read, Glob, Grep, Write, Edit, Bash(git log:*)
---

# README Update Command

Update README files based on code changes, keeping documentation in sync with implementation.

## Usage

```
/readme-update
/readme-update --path <directory>
/readme-update --section [installation|usage|api|contributing]
```

## Options

- `--path <dir>` - Update README in specific directory
- `--section <name>` - Update specific section only
- `--from-changes` - Generate from recent git changes
- `--validate` - Check README accuracy without updating
- `--platform <apple|android|web|all>` - Target platform context (default: all)

## Examples

```
/readme-update
/readme-update --path packages/auth
/readme-update --section installation --from-changes
```

## Output Format

### Update Report
```markdown
# README Update Report

## Files Updated

| File | Sections Changed | Status |
|------|------------------|--------|
| README.md | Installation, Usage | ✅ Updated |
| packages/auth/README.md | API, Examples | ✅ Updated |
| packages/ui/README.md | No changes | ⏭️ Skipped |

---

## Changes Made

### README.md

#### Installation Section
**Before**:
```bash
npm install
```

**After**:
```bash
npm install

# Required environment variables
cp .env.example .env
```

**Reason**: New environment variables added in recent changes

#### Usage Section
**Added**: Dark mode configuration example
```javascript
// Enable dark mode
app.configure({
  theme: 'dark' // or 'light' or 'system'
});
```

**Reason**: New feature added

---

### packages/auth/README.md

#### API Section
**Added**: SSO endpoints documentation
```markdown
### SSO Authentication

#### POST /auth/sso/callback
Handle OAuth callback from identity provider.

| Parameter | Type | Description |
|-----------|------|-------------|
| provider | string | OAuth provider (okta, azure) |
| code | string | Authorization code |
```

**Reason**: New SSO feature implemented

---

## Validation Results

| Check | Status | Details |
|-------|--------|---------|
| Links | ⚠️ | 2 broken internal links |
| Code Examples | ✅ | All examples valid |
| Version Numbers | ✅ | Up to date |
| Dependencies | ⚠️ | Missing new peer dep |

### Issues to Fix Manually

1. **Broken Link**: `docs/api.md` → should be `docs/api/README.md`
2. **Missing Dependency**: Add `@auth/core` to peer dependencies list
```

### README Template
```markdown
# Package Name

Brief description of the package.

## Installation

```bash
npm install package-name
```

## Quick Start

```javascript
import { feature } from 'package-name';

// Basic usage
const result = feature.doSomething();
```

## Features

- Feature 1
- Feature 2
- Feature 3

## API Reference

### `function(param)`

Description of the function.

**Parameters**
| Name | Type | Default | Description |
|------|------|---------|-------------|
| param | string | - | Parameter description |

**Returns**: `ReturnType` - Description

**Example**
```javascript
const result = function('value');
```

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| option1 | string | 'default' | Option description |

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md)

## License

MIT
```

## Section Templates

| Section | Auto-Generated From |
|---------|---------------------|
| Installation | package.json dependencies |
| Usage | Code examples in tests |
| API | JSDoc comments |
| Configuration | Config schema/types |
| Contributing | CONTRIBUTING.md template |

## Integration

This command works with:
- `/doc-audit` - Find README issues
- `/api-docs` - Link API documentation
- `/release-notes` - Update for releases

## Related

- [technical-writer](../agents/technical-writer.md) - Documentation expertise
- [doc-audit](./doc-audit.md) - Documentation audit
- [workflow](./workflow.md) - DC stage documentation
