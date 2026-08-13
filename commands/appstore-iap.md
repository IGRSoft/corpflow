---
name: appstore-iap
description: 'Apple-only. Set up App Store Connect in-app purchases and subscriptions for a new app from its bundle ID, driving App Store Connect via browser automation.'
argument-hint: <bundle ID>
model: sonnet
allowed-tools: Read, Glob, Grep, Write, mcp__claude-in-chrome__tabs_context_mcp, mcp__claude-in-chrome__tabs_create_mcp, mcp__claude-in-chrome__navigate, mcp__claude-in-chrome__get_page_text, mcp__claude-in-chrome__read_page, mcp__claude-in-chrome__find, mcp__claude-in-chrome__form_input, mcp__claude-in-chrome__computer, mcp__claude-in-chrome__javascript_tool
related:
  - commands/appstore-info.md
  - commands/docs-release-notes.md
  - agents/release-engineer.md
  - commands/worktask.md
---

# App Store IAP Setup Command

> **Apple-only.** This command targets App Store Connect and has no equivalent on other
> platforms. The rest of the corpflow plugin is platform-neutral.

Set up all In-App Purchases and Subscription Groups in App Store Connect for a new app.
Provide only the bundle ID — the command locates or generates the `Products.plist` automatically
by inspecting the project source, then drives the entire App Store Connect setup via browser automation.

## Usage

```
/appstore-iap --bundle <bundle.id>
```

## Options

- `--bundle <id>` — App bundle ID (required). Example: `com.igrsoft.newapp`
- `--dry-run` — Preview all planned actions without making changes in App Store Connect

## Examples

```
/appstore-iap --bundle com.igrsoft.newapp
/appstore-iap --bundle com.igrsoft.newapp --dry-run
```

## Steps

---

### Phase 1 — Locate or Generate Products.plist

#### 1.1 — Search for existing plist

Search the local filesystem for a `Products.plist` associated with the target bundle ID.
Look in common locations relative to the project root:

```
Products.plist
Config/Products.plist
Resources/Products.plist
<AppName>/Products.plist
<AppName>/Resources/Products.plist
Supporting Files/Products.plist
```

Also search for any `.plist` file containing the bundle ID prefix as a string
(e.g. files referencing `com.igrsoft.newapp.tip`).

#### 1.2 — If found: read and validate

Parse the plist. Confirm it contains at least one of:
- `Products` array with product entries
- `Subscriptions` array with group entries

If the plist exists but uses the legacy short-form (product IDs without bundle prefix),
expand each ID by prepending `<bundle.id>.`.

#### 1.3 — If not found: generate Products.plist

Inspect the project source to discover all IAP and subscription product IDs. Look for:

- Swift/ObjC: `SKProduct`, `SKProductsRequest`, `Product.id`, `StoreKit` identifiers,
  `Transaction`, `.appTransaction`, any string matching the bundle ID pattern
- Any existing `StoreKit Configuration File` (`.storekit`) — parse it directly if present
- `Info.plist`, entitlements files, or build settings referencing IAP product IDs

##### Inference rules

From the discovered product IDs, infer:
- **Type**: Non-Consumable, Consumable, or Auto-Renewable Subscription
  (subscriptions typically appear in a `Subscriptions` group or have `.monthly`/`.yearly`/`.weekly` suffix)
- **Subscription Group**: infer from product ID structure or source grouping
- **Duration**: infer from suffix (`.monthly` → `1 Month`, `.yearly` → `1 Year`, `.weekly` → `1 Week`)
- **Price**: use standard tier defaults if not found in source:
  - Tips/small one-time: $1.99
  - Tips/large one-time: $7.99
  - Monthly subscription: $0.99
  - Yearly subscription: $9.99
- **Localizations**: generate English (U.K.) and Ukrainian display names and descriptions
  based on the product ID suffix and app purpose (inferred from README or source)
- **Review Notes**: default to `"go Settings -> Support the Developer"` unless source indicates otherwise

##### Products.plist template — header

Write the generated `Products.plist` to the project root using this format:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
```

##### Products.plist template — Products array

```xml
<!-- …continued: Products array -->
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
        <dict>
          <key>Lang</key> <string>uk</string>
          <key>Name</key> <string>Кавова підтримка</string>
          <key>Desc</key> <string>Почастуйте розробника кавою</string>
        </dict>
      </array>
    </dict>
  </array>
```

##### Products.plist template — Subscriptions group

```xml
<!-- …continued: Subscriptions array -->
  <key>Subscriptions</key>
  <array>
    <dict>
      <key>Group</key> <string>support</string>
      <key>Products</key>
      <array>
        <dict>
          <key>ProductID</key>    <string>com.igrsoft.newapp.support.monthly</string>
          <key>Duration</key>     <string>1 Month</string>
          <key>PriceUSD</key>     <real>0.99</real>
          <key>ReviewNotes</key>  <string>go Settings -> Support the Developer</string>
```

##### Products.plist template — subscription localizations & closing

```xml
<!-- …continued: subscription Localizations + closing tags -->
          <key>Localizations</key>
          <array>
            <dict>
              <key>Lang</key> <string>en-GB</string>
              <key>Name</key> <string>Monthly Tips</string>
              <key>Desc</key> <string>Give small coffee for developer each month</string>
            </dict>
            <dict>
              <key>Lang</key> <string>uk</string>
              <key>Name</key> <string>Щомісячна підтримка</string>
              <key>Desc</key> <string>Щомісячна кава для розробника</string>
            </dict>
          </array>
        </dict>
      </array>
    </dict>
  </array>

</dict>
</plist>
```

#### Confirmation gate

Print the generated file path and contents, then pause and ask the user to confirm before proceeding:

```
Products.plist generated at: /path/to/project/Products.plist

[preview of file]

Proceed with App Store Connect setup using the above config? (yes / edit first)
```

If `--dry-run` is set, stop here after generating and printing the plist.

---

### Phase 2 — Create One-time IAPs

Navigate to App Store Connect:
```
https://appstoreconnect.apple.com/apps
```
Find the app by bundle ID, open it, then go to **In-App Purchases**.

**For each entry in the plist `Products` array (cheapest `PriceUSD` first):**

#### 2.1 — Create
- Click `(+)` / `Create`
- Set `Type` from plist entry
- Set `Reference Name` to the last dot-segment of `ProductID`
  (e.g. `com.igrsoft.newapp.tip.small` → `tip.small`)
- Set `Product ID` to the full `ProductID` from plist
- Click **Create**

#### 2.2 — Set Price
- Scroll to `Price Schedule` → click `Add Pricing`
- Base country defaults to `United States (USD)` — leave it
- In the `Price` dropdown, type the price to filter (e.g. `1.99`), select the match
- Click **Next** (do not scroll or inspect the country list)
- Click **Next** on the country confirmation screen
- Click **Confirm**

#### 2.3 — Add Localizations

For each localization entry in the plist:
- Click `Add Localization` (or `+` next to App Store Localization)
- If the language dropdown shows the wrong default, correct it via JavaScript:
  ```javascript
  const sel = document.querySelector('select');
  const match = Array.from(sel.options).find(o =>
    o.text.toLowerCase().includes('ukrainian') || o.value === 'uk'
  );
  if (match) { sel.value = match.value; sel.dispatchEvent(new Event('change', { bubbles: true })); }
  ```
- Fill `Display Name` with `Name` from plist
- Fill `Description` with `Desc` from plist
- Click **Create**
- Repeat for remaining localizations

#### 2.4 — Add Review Notes
- Scroll to `Review Notes` textarea, click, type `ReviewNotes` from plist

#### 2.5 — Save
- Click **Save** — confirm `✓ Saved` before moving to the next IAP

---

### Phase 3 — Create Subscription Groups and Subscriptions

Navigate to **Subscriptions** for the same app.

**For each group in the plist `Subscriptions` array:**

**3.1 — Create Group**
- Click **Create** (Subscription Group)
- Enter the `Group` value from plist as Reference Name
- Click **Create**

**For each product in the group:**

**3.2 — Create Subscription**
- Click **Create** inside the group
- `Reference Name`: last dot-segment of `ProductID`
- `Product ID`: full `ProductID` from plist
- Click **Create**

**3.3 — Set Duration**
- Set `Subscription Duration` dropdown to the `Duration` value from plist

**3.4 — Set Price**
- Scroll to `Subscription Prices` → click `Add Subscription Price`
- Select price matching `PriceUSD`, click **Next** → **Next** → **Confirm**

**3.5 — Add Localizations** — same JS-assisted flow as Step 2.3

**3.6 — Add Review Notes** — same as Step 2.4

**3.7 — Save** — click **Save**, confirm `✓ Saved`

---

### Phase 4 — Verification

- Navigate to `In-App Purchases` — confirm all product IDs from the plist are listed
- Navigate to `Subscriptions` — confirm all groups and subscriptions are listed
- Print the summary report

---

## Output Format

```markdown
# App Store IAP Setup — Complete

## Products.plist
| Status | Path |
|--------|------|
| ✅ Generated | /path/to/project/Products.plist |

## One-time IAPs Created

| Product ID | Type | Price | Localizations | Status |
|------------|------|-------|---------------|--------|
| com.igrsoft.newapp.tip.small | Non-Consumable | $1.99 | en-GB, uk | ✅ Created |
| com.igrsoft.newapp.tip.large | Non-Consumable | $7.99 | en-GB, uk | ✅ Created |

## Subscriptions Created

| Group | Product ID | Duration | Price | Localizations | Status |
|-------|------------|----------|-------|---------------|--------|
| support | com.igrsoft.newapp.support.monthly | 1 Month | $0.99 | en-GB, uk | ✅ Created |

## Issues
| Item | Issue |
|------|-------|
| — | — |

## Next Steps
1. Upload review screenshots for each IAP if App Store review requires them
2. Run `/appstore-info` to generate or update App Store listing metadata
3. Submit app for review once all metadata is complete
```

## Optimization Rules

| Rule | Reason |
|------|--------|
| Generate plist first, act second | All data is confirmed before any browser action |
| `get_page_text` over screenshots | Extracts all page fields in one call |
| Skip country pricing matrix | Always shows `--`; go straight to Price Schedule |
| JS for language dropdowns | `form_input` is unreliable for `<select>` — use `dispatchEvent` |
| Click Next without inspecting rows | 175-country lists auto-calculate; no need to scroll |
| Confirm `✓ Saved` once per item | Not after every individual field |
| Cheapest IAP first | Catches price dropdown quirks early |

**Target: 80–120 browser steps** per full run.

## Context Limit Safety

If the context limit is approached mid-run:
1. Note which product IDs already exist in App Store Connect
2. Start a new session with the same `--bundle` argument
3. The plist already exists on disk — Phase 1 will find and reuse it
4. Skip already-created items by checking the App Store Connect IAP list before creating

## Integration

Used by:
- `release-engineer` agent at the **RE (Release Engineering)** stage
- When launching any new app that needs IAP or subscription monetization
