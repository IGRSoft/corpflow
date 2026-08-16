# Threat Model (SR0)

Lightweight threat modeling for the SR stage. Scope is **the change under review**, not the
whole system: model the boundaries the diff crosses, not every boundary that exists.

Runs at SR0, before the OWASP checklist. Its output is the `## threat-model` section of
`security-review-N.md`, and every finding in `## findings` cites a threat ID from it.

## Step 1 — Trust boundaries

A trust boundary is any point where data or control passes between parties with different
privilege. Enumerate only the ones the diff touches.

| Boundary class | Typical instances |
|----------------|-------------------|
| Process / privilege | User ↔ app, app ↔ OS service, sandbox ↔ host, tenant ↔ tenant |
| Network | Client ↔ server, service ↔ third-party API, ingress from the public internet |
| Storage | In-memory ↔ disk, plaintext ↔ encrypted store, app store ↔ shared/exported store |
| Supply chain | First-party code ↔ dependency, build host ↔ registry, plugin/build-script execution |
| Model | Untrusted content ↔ prompt/instruction, model output ↔ execution or rendering |

For each: name the two sides, the asset that crosses, and who is trusted on each side.

## Step 2 — Attack surface

For each boundary, enumerate the concrete **entry points the diff adds or widens** —
an endpoint, an IPC/URL scheme, a parsed file format, a CLI flag, an exported component, a
new dependency, a new tool granted to an agent. Record the input's origin (who controls it)
and where it lands.

An entry point with no attacker-controlled input is not attack surface; say so and drop it
rather than listing it for completeness.

## Step 3 — STRIDE categorization

Categorize each entry point's plausible threats. STRIDE says *what kind* of threat it is; it
does **not** set severity — severity stays the existing table in `agents/security-reviewer.md
§ Severity Classification`. Never introduce a second severity vocabulary.

| STRIDE | Violates | Ask |
|--------|----------|-----|
| **S**poofing | Authentication | Can the caller claim an identity it does not hold? |
| **T**ampering | Integrity | Can data or code be modified in transit, at rest, or in the build? |
| **R**epudiation | Non-repudiation | Can a security-relevant action happen without an attributable log? |
| **I**nformation disclosure | Confidentiality | Can secrets, PII, or internals leak — including via errors and logs? |
| **D**enial of service | Availability | Can unbounded input, work, or cost be forced? |
| **E**levation of privilege | Authorization | Can a caller reach an operation or object outside its grant? |

Not every category applies to every entry point. Record the ones with a plausible attacker
and a reachable path; drop the rest silently.

## Output shape

One row per threat, in `## threat-model`:

```markdown
| ID | Boundary | Entry point | STRIDE | Attacker-controlled input |
|----|----------|-------------|--------|---------------------------|
| T1 | client ↔ API | `POST /v1/export` | E, I | body `.ownerId` |
```

IDs are `T<n>`, stable within one artifact. Every `## findings` entry opens with the threat
it realizes — `**[T1]** <finding> → <remediation>` — and every Critical/High threat is either
answered by a finding or explicitly recorded as mitigated, with the control that mitigates it.
A threat with neither is an unfinished review.

Findings may also arise from the checklist with no threat-model row behind them. Cite them
`**[—]**` and add the missing row rather than leaving the section stale.

## No material threat surface

SR runs on changes that turn out not to be security-relevant. When the diff crosses no trust
boundary and adds no attacker-controlled input, the whole section is one line:

```markdown
No material threat surface: <what the diff changes and why nothing crosses a boundary>.
```

That is a complete, passing threat model. Do not invent threats to fill the table — a
speculative threat with no reachable path is noise that costs the next reviewer real time.

## Relation to the OWASP checklist

The threat model scopes the checklist; it does not replace it. `owasp-checklist.md § A04`
carries the checkbox this procedure satisfies. Run the checklist at SR1 against the surface
this step identified, plus the always-on passes (secrets, dependencies) which run regardless
of whether any boundary was crossed.
