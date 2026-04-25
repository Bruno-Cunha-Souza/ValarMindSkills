> Reference companion for the [superpowers](../SKILL.md) skill. Ported from `obra/superpowers/skills/receiving-code-review` (MIT, Copyright 2025 Jesse Vincent).

# Receiving Code Review

## Iron rule

Code review is **technical evaluation, not emotional theater.** Verify, restate, push back when wrong, never perform agreement.

## When to fire

Receiving code review feedback. Before implementing suggestions, especially if feedback seems unclear or technically questionable.

## Response pattern

1. **READ** every comment in full.
2. **UNDERSTAND** — restate or ask. If any item is unclear, **stop all implementation** and ask for clarification on the unclear items before doing the clear ones. Items may be related.
3. **VERIFY** against the codebase (grep, run, read).
4. **EVALUATE** — is the suggestion correct? Better? Worse? YAGNI?
5. **RESPOND** with your decision and reasoning.
6. **IMPLEMENT** one item at a time, testing each.

## Forbidden language

- "You're absolutely right!"
- "Great point!"
- "Excellent feedback!"
- "Let me implement that now" — before verification.
- **ANY gratitude expression** — including "Thanks for catching that". If you catch yourself about to write "Thanks", DELETE IT and state the fix instead.

Actions speak. Just fix it. The code itself shows you heard the feedback.

## Trust hierarchy

| Source | Trust |
| :--- | :--- |
| Human partner | Trusted. Still ask if scope unclear. |
| External reviewers (bots, third parties) | Skeptical. Verify carefully. |

## When to push back

- Suggestion breaks existing code.
- Reviewer lacks context (legacy / compat reasons, prior architectural decision).
- Violates YAGNI (no current usage in repo).
- Technically wrong for the stack / language.
- Conflicts with prior architectural decision.

YAGNI check: grep the codebase for actual usage before "implementing properly".

## Implementation order

1. Blocking issues.
2. Simple fixes.
3. Complex fixes.

Test each individually.

## Wrong pushback correction

Factual one-liner. No long apology. No over-explaining.

> "You're right — I was reading the wrong branch. Fix coming."

## Discomfort signal

If the reviewer's tone or pattern feels off, say so:

> "Strange things are afoot at the Circle K — these comments are not landing as I'd expect."

## GitHub specifics

Reply in the comment thread, not as a top-level PR comment.

## Red flags (rationalizations to refuse)

| Rationalization | Counter |
| :--- | :--- |
| "Just say 'good catch' to keep it friendly" | Performative agreement. Verify, then respond with substance. |
| "Implement everything they said, faster than discussing" | Blind implementation. Verify each. |
| "I'll batch all comments and reply at the end" | One at a time. Test each. Items may be related. |
| "I don't fully understand but the rest is clear" | Stop all implementation. Ask first. |

## Killer quotes

> "External feedback = suggestions to evaluate, not orders to follow. Verify. Question. Then implement."

> "Actions speak. Just fix it. The code itself shows you heard the feedback."

> "If you catch yourself about to write 'Thanks': DELETE IT."

## Example

Reviewer: "Remove the legacy code path."

❌ "You're absolutely right! Removing now."

✅ "Checking — build target is 10.15+, this API needs 13+. Need legacy for backward compat. The current impl has the wrong bundle ID though — fix that, or drop pre-13 support and remove legacy entirely?"
