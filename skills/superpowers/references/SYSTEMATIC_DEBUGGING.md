> Reference companion for the [superpowers](../SKILL.md) skill. Ported from `obra/superpowers/skills/systematic-debugging` (MIT, Copyright 2025 Jesse Vincent).

# Systematic Debugging

## Iron Law

**NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST.**

If Phase 1 is not complete, you cannot propose fixes. Symptom fixes are failure.

## When to fire

Any bug, test failure, or unexpected behavior — before proposing a fix. Especially under time pressure or after prior fixes did not stick.

## Phase 1 — Root cause

- Read the error message in full. Quoted, not paraphrased.
- Reproduce consistently. Find the minimal repro.
- Check recent changes (`git log -p`, `git blame` on the failing line).
- Multi-component system? **Add diagnostic instrumentation at every component boundary BEFORE proposing fixes.** Trace data flow backward to source.
- Output of each layer recorded; failure boundary identified.

## Phase 2 — Pattern analysis

- Find similar working code.
- Read the reference completely. No skimming.
- Enumerate every difference, however small.
- Understand dependencies (versions, config, env).

## Phase 3 — Hypothesis

- State **one** specific hypothesis: "X is the root cause because Y."
- Test the smallest possible change.
- One variable at a time.
- Did not work? Form a **new** hypothesis. Do not stack fixes.

## Phase 4 — Implementation

- Write a failing test that reproduces the bug (use [TDD](TDD.md)).
- Implement a single fix at the root cause.
- No "while I'm here" extras.
- Verify (use [VERIFICATION](VERIFICATION.md)).

## Stop rule

3+ fix attempts → STOP. Question the architecture. Pattern of new symptoms after each fix = wrong architecture, not a failed hypothesis. Do not try fix #4.

## Honesty

When you do not know, say so. Do not pretend.

## Partner signals (return to Phase 1)

- "Is that not happening?"
- "Will it show us…?"
- "Stop guessing"
- "Ultrathink this"
- "We're stuck?"

## Red flags (rationalizations to refuse)

| Rationalization | Counter |
| :--- | :--- |
| "Quick fix for now, investigate later" | "Later" is "never". Phase 1. |
| "Just try changing X and see" | That is guessing. Form a hypothesis first. |
| "It's probably X, let me fix that" | Probably is not evidence. Trace it. |
| "I'll write the test after" | TDD says before. Reproduction test first. |
| "This pattern looks similar enough" | Read the reference completely. Enumerate every difference. |

## Killer quotes

> "Symptom fixes are failure."

> "95% of 'no root cause' cases are incomplete investigation."

## Example — multi-layer signing failure

Bad: "Code signing fails. Probably the cert. Let me try a different cert." → fix #2, #3, #4 — each adds a new symptom.

Good:

1. Log secrets at workflow layer → present.
2. Log env vars at build script → present.
3. Log keychain state at signing script → cert imported.
4. Run codesign with `--verbose=4` → reveals "no identity found".

Boundary identified: workflow ✓ → build script ✗ at codesign call. Hypothesis: keychain not in search path for the build user. Test fix: add `security list-keychains -s`. Verify. Done.
