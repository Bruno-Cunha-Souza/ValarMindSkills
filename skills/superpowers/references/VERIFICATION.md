> Reference companion for the [superpowers](../SKILL.md) skill. Ported from `obra/superpowers/skills/verification-before-completion` (MIT, Copyright 2025 Jesse Vincent).

# Verification Before Completion

## Iron Law

**NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE.**

If you have not run the verification command in this message, you cannot claim it passes. Violating the letter of this rule is violating the spirit of this rule.

## When to fire

About to claim work is complete, fixed, or passing. Before committing, opening a PR, or saying "done".

## The gate

1. **Identify** the verification command (test runner, build, lint, custom).
2. **Run** the full command fresh, in this message.
3. **Read** full output, exit code, failure count.
4. **Verify** the output confirms the claim.
5. **Then** make the claim, citing evidence.

## What counts

| Claim | Required evidence |
| :--- | :--- |
| "Tests pass" | Test command output, 0 failures. Not previous run. Not "should pass". |
| "Build succeeds" | Build command exit 0. Linter passing is not a substitute. |
| "Bug fixed" | Test of the **original symptom**, fresh run, observed pass. Not assumption that the patch landed. |
| "Regression test in place" | Red-Green-Revert-Red-Restore-Green sequence. One green run is not enough. |
| "Subagent finished" | Independent verification via `git diff` and behavior. Subagent self-report is a claim, not evidence. |
| "Requirements met" | Line-by-line checklist against the plan. "Tests pass" ≠ "requirements met". |

## Forbidden language before verification

"should", "probably", "seems to", "Great!", "Perfect!", "Done!", "Complete!", "All set!", or any wording implying success.

Applies to exact phrases, paraphrases, synonyms, and any implication of success — even if you change the words.

## Regression test verification

- Write the regression test.
- Run it. Pass with the fix in place.
- **Revert the fix.** Run again. **MUST FAIL.**
- Restore the fix. Run again. Pass.
- Now you can claim "regression covered".

## Red flags (rationalizations to refuse)

| Rationalization | Counter |
| :--- | :--- |
| "Should work now" | Run the command. |
| "I'm confident" | Confidence is not evidence. |
| "Just this once" | Especially this once. |
| "Linter passed, build is fine" | Linter is not the build. Run the build. |
| "Agent said it succeeded" | Agent reports are claims, not evidence. Verify via diff and behavior. |
| "I'm tired" | The bug does not care. Run it. |
| "Partial check is enough" | Then partially claim. "Tests in module X pass." |
| "Different words so the rule does not apply" | Applies to all wordings implying success. |

## Killer quotes

> "Claiming work is complete without verification is dishonesty, not efficiency."

> "Run the command. Read the output. THEN claim the result. This is non-negotiable."

> "Confidence ≠ evidence."

## Examples

✅ "All tests pass — `npm test` ran, 34/34 passed, exit 0."
❌ "Should pass now."

✅ "Regression covered. Wrote test, ran (pass). Reverted fix, ran (FAIL with `Cannot read properties of undefined`). Restored fix, ran (pass)."
❌ "I have written a regression test."
