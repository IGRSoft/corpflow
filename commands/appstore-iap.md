---
name: appstore-iap
description: 'Apple-only. Set up App Store Connect in-app purchases and subscriptions for a new app from its bundle ID, driving App Store Connect via browser automation.'
argument-hint: '<bundle ID> [--dry-run]'
model: sonnet
allowed-tools: Read, Glob, Grep, Write, mcp__claude-in-chrome__tabs_context_mcp, mcp__claude-in-chrome__tabs_create_mcp, mcp__claude-in-chrome__navigate, mcp__claude-in-chrome__get_page_text, mcp__claude-in-chrome__read_page, mcp__claude-in-chrome__find, mcp__claude-in-chrome__form_input, mcp__claude-in-chrome__computer, mcp__claude-in-chrome__javascript_tool
related:
  - commands/appstore-info.md
  - commands/docs-release-notes.md
  - agents/release-engineer.md
  - commands/worktask.md
---

# App Store IAP Setup Command

> **Apple-only.** App Store Connect has no equivalent elsewhere; the rest of corpflow is platform-neutral.

From a bundle ID alone: locate or generate `Products.plist` from project source, then create every
one-time IAP and subscription in App Store Connect via browser automation.

## Usage

```
/appstore-iap --bundle <bundle.id>
```

## Options

| Option | Type | Required | Behavior |
|--------|------|----------|----------|
| `--bundle <id>` | string | yes | App bundle ID, e.g. `com.igrsoft.newapp` |
| `--dry-run` | flag | no | Print the generated plist and stop — no App Store Connect changes |

## Examples

```
/appstore-iap --bundle com.igrsoft.newapp             # full setup
/appstore-iap --bundle com.igrsoft.newapp --dry-run   # preview the plist only
/appstore-iap --bundle com.igrsoft.tipjar             # rerun after interruption; Phase 1 reuses the plist
```

## Phase 1 — Locate or Generate Products.plist

### 1.1 — Search

`Products.plist` at the project root or under `Config/`, `Resources/`, `<AppName>/`,
`<AppName>/Resources/`, `Supporting Files/`; also grep `.plist` files for the bundle ID prefix
(e.g. `com.igrsoft.newapp.tip`).

### 1.2 — If found: validate

Require a `Products` array, a `Subscriptions` array, or both. Expand legacy short-form IDs
(no bundle prefix) by prepending `<bundle.id>.`.

### 1.3 — If not found: discover product IDs

Scan source for StoreKit identifiers (`SKProduct`, `SKProductsRequest`, `Product.id`,
`Transaction`, `.appTransaction`, bundle-ID-shaped strings), `.storekit` files (parse directly),
and `Info.plist` / entitlements / build settings.

### 1.4 — Inference rules

| Field | Value |
|-------|-------|
| `Type` | Non-Consumable, Consumable, or Auto-Renewable Subscription — subscriptions sit in a `Subscriptions` group or end in `.monthly`/`.yearly`/`.weekly` |
| `Group` | product ID structure or source grouping |
| `Duration` | `.monthly` → `1 Month`, `.yearly` → `1 Year`, `.weekly` → `1 Week` |
| `PriceUSD` | source value, else default: one-time tip $1.99 small / $7.99 large, $0.99 monthly, $9.99 yearly |
| `Localizations` | English (U.K.) + Ukrainian name and description, from the ID suffix and app purpose (README or source) |
| `ReviewNotes` | `go Settings -> Support the Developer` unless source says otherwise |

### 1.5 — Products.plist template

Write to the project root: standard plist header (`<?xml?>`, `<!DOCTYPE plist …>`,
`<plist version="1.0">`, `<dict>`), the two arrays below, closing tags. One `<dict>` per product,
localization, and group.

```xml
<key>Products</key>
<array>
  <dict>
    <key>ProductID</key>   <string>com.igrsoft.newapp.tip.small</string>
    <key>Type</key>        <string>Non-Consumable</string>
    <key>PriceUSD</key>    <real>1.99</real>
    <key>ReviewNotes</key> <string>go Settings -> Support the Developer</string>
    <key>Localizations</key>
    <array>
      <dict>
        <key>Lang</key> <string>en-GB</string>
        <key>Name</key> <string>Coffee tips</string>
        <key>Desc</key> <string>Give coffee once for developer</string>
      </dict>
    </array>
  </dict>
</array>
```

### 1.6 — Template — Subscriptions array

Groups wrap products; a subscription adds `Duration` to the product keys.

```xml
<key>Subscriptions</key>
<array>
  <dict>
    <key>Group</key> <string>support</string>
    <key>Products</key>
    <array>
      <dict>
        <key>ProductID</key>   <string>com.igrsoft.newapp.support.monthly</string>
        <key>Duration</key>    <string>1 Month</string>
        <key>PriceUSD</key>    <real>0.99</real>
        <key>ReviewNotes</key> <string>go Settings -> Support the Developer</string>
        <key>Localizations</key> <array><!-- same shape as above --></array>
      </dict>
    </array>
  </dict>
</array>
```

### 1.7 — Confirmation gate

Print the generated path and contents, then ask `Proceed with App Store Connect setup using the
above config? (yes / edit first)` and wait. With `--dry-run`, stop here.

## Phase 2 — Create One-time IAPs

`https://appstoreconnect.apple.com/apps` → app (by bundle ID) → **In-App Purchases**.
Per `Products` entry, cheapest `PriceUSD` first:

| # | Action |
|---|--------|
| 2.1 Create | `(+)`/**Create** → `Type` from plist → `Reference Name` = last dot-segment of `ProductID` (`…tip.small` → `tip.small`) → `Product ID` = full `ProductID` → **Create** |
| 2.2 Price | `Price Schedule` → `Add Pricing` → keep base country `United States (USD)` → type the price (e.g. `1.99`) to filter the `Price` dropdown, pick the match → **Next** → **Next** → **Confirm**; never scroll the country list |
| 2.3 Localizations | per entry: `Add Localization` (or `+` next to App Store Localization) → `Display Name` = `Name`, `Description` = `Desc` → **Create**; wrong language default → JS fix below |
| 2.4 Review Notes | click the `Review Notes` textarea, type `ReviewNotes` |
| 2.5 Save | **Save**, then confirm `✓ Saved` before the next IAP |

### Language dropdown fix (2.3)

`form_input` is unreliable for `<select>`:

```javascript
const sel = document.querySelector('select');
const match = Array.from(sel.options).find(o =>
  o.text.toLowerCase().includes('ukrainian') || o.value === 'uk'
);
if (match) { sel.value = match.value; sel.dispatchEvent(new Event('change', { bubbles: true })); }
```

## Phase 3 — Subscription Groups and Subscriptions

**Subscriptions** tab. Per group (3.1): **Create** (Subscription Group) → Reference Name = `Group`
from plist → **Create**. Then per product in the group, repeat Phase 2 with three deltas: no `Type`
field (3.2); `Subscription Duration` = `Duration` (3.3); price lives under `Subscription Prices` →
`Add Subscription Price` (3.4). Steps 3.5–3.7 (localizations, review notes, save) match 2.3–2.5.

## Phase 4 — Verification

Reopen `In-App Purchases` and `Subscriptions`; confirm every product ID, group, and subscription
from the plist is listed; print the report.

## Output Format

```markdown
# App Store IAP Setup — Complete

## Products.plist
| Status | Path |                                                    ✅ Generated | <path>

## One-time IAPs Created
| Product ID | Type | Price | Localizations | Status |            one row per product

## Subscriptions Created
| Group | Product ID | Duration | Price | Localizations | Status |  one row per subscription

## Issues
| Item | Issue |                                                    — | — when clean

## Next Steps
1. Upload review screenshots for IAPs where App Store review requires them
2. `/appstore-info` — generate or update listing metadata
3. Submit for review once metadata is complete
```

## Optimization Rules

| Rule | Reason |
|------|--------|
| Generate the plist first, act second | Data confirmed before any browser action |
| `get_page_text` over screenshots | One call returns every page field |
| Skip the country pricing matrix | Always `--`; go straight to Price Schedule |
| JS for language dropdowns | `form_input` unreliable for `<select>` |
| **Next** without inspecting rows | 175-country lists auto-calculate |
| Confirm `✓ Saved` once per item | Not after every field |
| Cheapest IAP first | Catches price dropdown quirks early |

**Target: 80–120 browser steps** per full run.

## Context Limit Safety

Near the limit: note which product IDs already exist, then rerun with the same `--bundle`. Phase 1
reuses the on-disk plist; check the App Store Connect list before creating so existing items are
skipped.

## Integration

Called by `release-engineer` at the **RE (Release Engineering)** stage, and whenever a new app
needs IAP or subscription monetization. Follow with `/appstore-info` for listing metadata.
