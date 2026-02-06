# SVG Mockup Templates

Wireframe-style SVG mockup generation templates, design tokens, and component patterns for the Designer agent.

## When to Generate

**Generate mockups when:**
- Task triggers design detection (score >= 5)
- New UI screens or components are being created
- Existing UI is being redesigned or significantly modified

**Do NOT generate mockups for:**
- Backend-only tasks (APIs, databases, infrastructure)
- Minor copy or styling tweaks
- Tasks explicitly marked as "no UI"

## Design Token System

Use these tokens consistently across all mockups:

| Token | Value | Usage |
|-------|-------|-------|
| Background | `#FFFFFF` | Primary background |
| Surface | `#F5F5F5` | Secondary surfaces, input fields |
| Text Primary | `#333333` | Headings, body text |
| Text Secondary | `#666666` | Subtitles, captions |
| Text Placeholder | `#999999` | Input placeholders |
| Border | `#CCCCCC` | Dividers, outlines |
| Accent | `#4A90E2` | Interactive elements, links |
| Error | `#D32F2F` | Error states, destructive actions |
| Success | `#388E3C` | Success states, confirmations |
| Spacing Unit | `8px` | All spacing in multiples of 8 |
| Font Family | `system-ui, -apple-system, sans-serif` | All text |
| Title Size | `24px / weight 700` | Screen titles |
| Heading Size | `20px / weight 600` | Section headings |
| Body Size | `16px / weight 400` | Body text, inputs |
| Caption Size | `14px / weight 400` | Labels, helpers |

## SVG Structure

**Standard viewports:**
- Mobile: `viewBox="0 0 375 667"`
- Tablet: `viewBox="0 0 768 1024"`

**Required elements:**
- `<title>` and `<desc>` for accessibility
- Semantic `<g id="section-name">` grouping
- `font-family="system-ui, -apple-system, sans-serif"` on all text

**Base template:**

```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 375 667">
  <title>Screen Name</title>
  <desc>Brief description of what this mockup shows</desc>
  <rect width="375" height="667" fill="#FFFFFF"/>

  <g id="header">
    <rect width="375" height="88" fill="#FFFFFF"/>
    <text x="187.5" y="68" font-family="system-ui, -apple-system, sans-serif"
          font-size="20" font-weight="600" fill="#333333"
          text-anchor="middle">Screen Title</text>
    <line x1="0" y1="88" x2="375" y2="88" stroke="#CCCCCC" stroke-width="1"/>
  </g>

  <g id="content" transform="translate(0, 88)">
    <!-- Content elements -->
  </g>
</svg>
```

## Component Patterns

Reuse these SVG patterns for consistent mockups:

**Navigation Bar:**
```svg
<g id="navbar">
  <rect width="375" height="88" fill="#FFFFFF"/>
  <text x="16" y="68" font-family="system-ui" font-size="17" fill="#4A90E2">← Back</text>
  <text x="187.5" y="68" font-family="system-ui" font-size="17" font-weight="600"
        fill="#333333" text-anchor="middle">Title</text>
  <text x="359" y="68" font-family="system-ui" font-size="17" fill="#4A90E2"
        text-anchor="end">Done</text>
  <line x1="0" y1="88" x2="375" y2="88" stroke="#CCCCCC" stroke-width="1"/>
</g>
```

**Primary Button:**
```svg
<g id="primary-button">
  <rect x="32" y="0" width="311" height="48" rx="8" fill="#4A90E2"/>
  <text x="187.5" y="28" font-family="system-ui" font-size="16" font-weight="600"
        fill="#FFFFFF" text-anchor="middle">Button Text</text>
</g>
```

**Text Input Field:**
```svg
<g id="text-input">
  <text x="32" y="0" font-family="system-ui" font-size="14" font-weight="600"
        fill="#333333">Label</text>
  <rect x="32" y="8" width="311" height="48" rx="8" fill="#F5F5F5"
        stroke="#CCCCCC" stroke-width="1"/>
  <text x="40" y="36" font-family="system-ui" font-size="16"
        fill="#999999">Placeholder text</text>
</g>
```

**Text Input (Error State):**
```svg
<g id="text-input-error">
  <text x="32" y="0" font-family="system-ui" font-size="14" font-weight="600"
        fill="#333333">Label</text>
  <rect x="32" y="8" width="311" height="48" rx="8" fill="#FFF5F5"
        stroke="#D32F2F" stroke-width="2"/>
  <text x="32" y="72" font-family="system-ui" font-size="14"
        fill="#D32F2F">Error message</text>
</g>
```

**Card:**
```svg
<g id="card">
  <rect x="16" y="0" width="343" height="120" rx="12" fill="#FFFFFF"
        stroke="#CCCCCC" stroke-width="1"/>
  <text x="32" y="32" font-family="system-ui" font-size="18" font-weight="600"
        fill="#333333">Card Title</text>
  <text x="32" y="56" font-family="system-ui" font-size="14"
        fill="#666666">Card description text</text>
</g>
```

**List Item:**
```svg
<g id="list-item">
  <rect x="16" y="0" width="343" height="64" fill="#FFFFFF"/>
  <text x="32" y="30" font-family="system-ui" font-size="16" fill="#333333">Item Title</text>
  <text x="32" y="48" font-family="system-ui" font-size="14" fill="#666666">Subtitle</text>
  <text x="343" y="32" font-family="system-ui" font-size="14" fill="#4A90E2"
        text-anchor="end">→</text>
  <line x1="16" y1="64" x2="359" y2="64" stroke="#CCCCCC" stroke-width="1"/>
</g>
```

**Empty State:**
```svg
<g id="empty-state">
  <circle cx="187.5" cy="200" r="40" fill="none" stroke="#CCCCCC" stroke-width="2"/>
  <text x="187.5" y="280" font-family="system-ui" font-size="20" font-weight="600"
        fill="#333333" text-anchor="middle">No Items Yet</text>
  <text x="187.5" y="304" font-family="system-ui" font-size="14" fill="#666666"
        text-anchor="middle">Get started by adding your first item</text>
</g>
```

## Naming Convention

**Pattern**: `mockup-[feature]-[screen]-[variant].svg`

Examples:
- `mockup-login-screen.svg` — Default login
- `mockup-login-screen-error.svg` — Login with validation errors
- `mockup-profile-edit-form.svg` — Profile editing
- `mockup-dashboard-empty-state.svg` — Dashboard with no data

## Storage

Save to `.context/images/` with workspace-aware path resolution:

```typescript
const task = TaskGet({ taskId: currentTaskId });
const workspacePath = task.metadata?.workspace_path;
const imagesPath = workspacePath
  ? `${workspacePath}/.context/images`
  : `.context/images`;

Write({
  file_path: `${imagesPath}/mockup-feature-screen.svg`,
  content: svgContent
});
```

## Mockup Generation Workflow

1. **Analyze requirements** — Identify key screens, interactive elements, states
2. **Determine scope** — Select 1-2 mockups covering primary screens and critical states
3. **Generate SVGs** — Use component patterns and design tokens
4. **Save to `.context/images/`** — Use naming convention, workspace-aware paths
5. **Reference in output** — List all mockups with descriptions in design documentation

## Reference Format in Documentation

When documenting mockups, use this format in planning.md:

```markdown
## Visual Mockups

Generated SVG mockups (see `.context/images/`):

- **`mockup-login-screen.svg`** — Default login with email/password fields
- **`mockup-login-screen-error.svg`** — Login with validation errors

### Design Specifications

(Reference: `mockup-login-screen.svg`)

**Layout:**
- Navigation bar: 88pt height
- Form container: starts at 120pt from top
- Input fields: 311pt width, 48pt height, 24pt gap
- Primary button: 311pt width, 48pt height, 32pt below last input

**States to Implement:**
1. Default (empty fields)
2. Error (validation failed)
3. Loading (authentication in progress)
```

## Quality Checklist

Before completing design work:

- [ ] All critical screens have mockups
- [ ] Key states represented (default, error, empty, loading)
- [ ] Design tokens used consistently
- [ ] File names follow naming convention
- [ ] Mockups saved to correct path (workspace-aware)
- [ ] All mockups referenced in design documentation
- [ ] Accessibility tags included (`<title>`, `<desc>`)

## Related

- `agents/designer.md` - Designer agent
- `skills/task-folder-organization.md` - Context folder structure
