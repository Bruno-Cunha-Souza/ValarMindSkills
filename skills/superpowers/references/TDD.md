> Reference companion for the [superpowers](../SKILL.md) skill. Ported from `obra/superpowers/skills/test-driven-development` (MIT, Copyright 2025 Jesse Vincent).

# Test-Driven Development

## Iron Law

**NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST.**

Violating the letter of the rule is violating the spirit of the rule.

## When to fire

Always for new features, bug fixes, refactors, or any behavior change. Before writing implementation code.

## The cycle

1. **RED** — write a failing test for the smallest next behavior.
2. **Verify RED** — run the test. Confirm it fails for the right reason. Mandatory; without watching it fail you do not know if the test tests anything.
3. **GREEN** — write the minimum production code that makes the test pass. No extra options. No premature generalization.
4. **Verify GREEN** — run the test. Output pristine, 0 failures.
5. **REFACTOR** — improve naming, structure, duplication. Tests must stay green.
6. **Next behavior** — return to step 1.

## Rules

- One behavior per test. Test name does not contain "and".
- Real code over mocks. Mocks only when the real dependency is genuinely unavailable in test (network, time, randomness, file IO at scale).
- Watching the test fail is **mandatory**.
- GREEN is **minimal** — no "while I'm here" extras, no premature options/flags/configurability.
- If other tests fail after GREEN, fix immediately.
- Bug fixes always start with a failing reproduction test.
- Manual testing is not a substitute. No record, no re-run.
- Wrote code first? **Delete it.** Do not keep as reference. Do not adapt. Do not look at it. Implement fresh from tests.

## Verification checklist (before "done")

- [ ] Failing test existed and was watched fail.
- [ ] Code added makes that test pass.
- [ ] Test name describes one behavior, no "and".
- [ ] Other tests still pass.
- [ ] No leftover scaffolding, debug logs, commented code.

## Stuck?

- Write the wished-for API as a test, then implement.
- Write the assertion first, then the setup.
- Ask the human partner.

## Red flags (rationalizations to refuse)

| Rationalization | Counter |
| :--- | :--- |
| "I already manually tested" | Manual testing is not TDD. No re-run, no proof. Write the test. |
| "Tests after achieve the same purpose" | 30 minutes of tests after ≠ TDD. Coverage yes, proof tests work no. |
| "Keep the code as reference" | Sunk-cost fallacy. Delete. Implement fresh from tests. |
| "I've already spent X hours, deleting is wasteful" | Unverified code is technical debt, not value. Delete. |
| "TDD is dogmatic, I'm being pragmatic" | Violating the letter is violating the spirit. |
| "It's spirit not ritual" | The ritual IS the spirit. Watch tests fail. |
| "The test passes immediately" | Then it does not test new behavior. Make it fail first. |

## Killer quotes

> "If you didn't watch the test fail, you don't know if it tests the right thing."

> "Production code → test exists and failed first. Otherwise → not TDD."

## Example

Bug: form accepts empty email.

```ts
// RED
it("rejects empty email", () => {
  expect(submit({ email: "" }).error).toBe("Email required");
});
// run → FAIL (expected, no validation yet)

// GREEN — minimum
function submit(data) {
  if (!data.email?.trim()) return { error: "Email required" };
  // …existing code…
}
// run → PASS

// REFACTOR if helpful — extract validate(data) only when a 2nd validator arrives.
```
