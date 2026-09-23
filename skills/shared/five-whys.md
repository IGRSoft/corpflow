---
name: five-whys
---

# Five Whys Analysis

Chain "why?" from the symptom down to the systemic cause.

## Process

1. **Define the problem** — state the issue or symptom precisely.
2. **Ask "why?" five times** — each answer becomes the subject of the next why; answer 5 is the root cause.
3. **Validate the root cause** — verify the chain holds and that fixing it prevents recurrence; accept multiple root causes when they exist.
4. **Develop solutions** — address the root cause, not the symptom, and add preventive/systemic measures.

## Example

**Problem**: Application crashes when processing large files

1. **Why?** → Runs out of memory
2. **Why?** → Loads the entire file into memory at once
3. **Why?** → The parser wasn't designed for streaming
4. **Why?** → Initial requirements only specified small files
5. **Why?** → Requirements gathering didn't consider future growth

**Root Cause**: Incomplete requirements gathering process
**Solution**: Streaming parser plus an improved requirements process

## Best Practices

Blame-free (focus on process, not people) · look for systemic issues · document the analysis · involve relevant stakeholders · test that the solution addresses the root cause.
