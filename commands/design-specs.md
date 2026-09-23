---
name: design-specs
description: Generate developer-ready design specifications for components, screens, or features
argument-hint: <component or screen name>
allowed-tools: Read, Glob, Grep, Write
related:
  - agents/designer.md
  - commands/design-review.md
---

# Design Specifications Command

Developer-ready specification for a component, screen, or feature — measured values, design-system tokens, states, and platform notes.

## Options

| Option | Values | Effect |
|--------|--------|--------|
| `--format` | `markdown`, `figma`, `json` | Output format (default: markdown) |
| `--platform` | `apple`, `android`, `web`, `all` | Target platform (default: all) |
| `--include-assets` | flag | Include asset export list |

```
/design-specs [target] [options]
/design-specs ProfileCard
/design-specs "Onboarding flow" --platform apple --include-assets
/design-specs NavigationBar --format json
```

## Procedure

1. **Analyze and specify** — map the target's structure, its design-system token usage and its platform-specific variations, then fill the template below in `--format`.
2. **Hand off** — every slot in § Specification Template holds a measured value or `n/a: <reason>`, and every colour, spacing and type value either names the design-system token it comes from or is flagged as a one-off. With `--include-assets`, each asset carries an export row with size and scale. A `[bracketed placeholder]` left anywhere means the spec is not deliverable.

## Specification Template

The three blocks below are one document, split only to stay skimmable.

```markdown
# Design Specifications: [Component/Screen]

## Overview
- **Component**: [Name]
- **Version**: [Design system version]
- **Last Updated**: [Date]
- **Designer**: [Name/Agent]

## Visual Specifications

### Layout
- Width / Height: [value or constraint]
- Padding / Margin: [top, right, bottom, left]

### Typography
- Font / Size / Weight / Line Height: [token or value]
- Color: [token]

### Colors
- Background / Text / Border / Accent: [token]

### Spacing
- Internal / External spacing: [token]
```

### Template — states and responsive behavior

```markdown
## States

<!-- one subsection per state, describing the visual delta from Default -->
### Default
### Hover (if applicable)
### Active/Pressed
### Disabled — include Opacity: [value]
### Error (if applicable) — Border color: [token], Helper text color: [token]

## Responsive Behavior

<!-- widths in the platform's own unit: pt (Apple), dp (Android), CSS px (web) -->
### Compact (< 375) — [Adjustments]
### Regular (375-768) — [Default behavior]
### Large (> 768) — [Adjustments]
```

### Template — accessibility, animation, assets

```markdown
## Accessibility

- Min touch target: [44x44pt Apple / 48x48dp Android / 24x24 CSS px web]
- Color contrast: [ratio]
- Screen reader label: [text]
- Focus indicator: [description]

## Animation (if applicable)

- Duration: [ms] · Easing: [curve] · Properties: [what animates]

## Implementation Notes

- [Platform-specific considerations] · [Known edge cases] · [Dependencies]

## Assets Required

### Pencil Mockups (Auto-Generated)
- [ ] Pencil Mockups — `.context/designs/mockup-*.pen` plus their `snapshot_layout()`
      exports, referenced in the specifications above

### Additional Assets
- [ ] [Asset name] - [format/size]
```

## Platform-Specific Sections

Emit only the sections selected by `--platform`; `all` emits every section.

| Platform | Sections |
|----------|----------|
| Apple | SwiftUI component mapping; UIKit / AppKit considerations; Dynamic Type support; safe area handling |
| Android | Jetpack Compose composable and Material 3 component mapping; units (`dp` layout, `sp` type); theming (`MaterialTheme` color roles, typography scale, shape scale); window size classes (compact / medium / expanded) and insets |
| Web | CSS tokens; breakpoint values; browser support notes |

Target: $ARGUMENTS
