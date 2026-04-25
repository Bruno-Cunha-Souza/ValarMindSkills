> Reference companion for the [superpowers](../SKILL.md) skill. Ported from `obra/superpowers/skills/requesting-code-review` (MIT, Copyright 2025 Jesse Vincent).

# Requesting Code Review

## When to fire

- After each task in [SUBAGENT_DRIVEN](SUBAGENT_DRIVEN.md) — mandatory.
- After each batch (~3 tasks) in [EXECUTING_PLANS](EXECUTING_PLANS.md).
- Before merge to `main` in ad-hoc work.
- Completing major features.

Review early, review often. The reviewer gets precisely crafted context — never your session's history.

## Procedure

1. **Get base/head SHAs.**
   ```bash
   BASE_SHA=$(git rev-parse HEAD~1)   # or origin/main
   HEAD_SHA=$(git rev-parse HEAD)
   ```
2. **Dispatch a code-review subagent.** In this repo, activate the `valarmindskills:code-review` skill (or `valarmindskills:github-pr-review` for a GitHub PR) via the Skill tool, or dispatch a `general-purpose` Agent with the skill's procedure inlined into its prompt. Provide:
   - `WHAT_WAS_IMPLEMENTED` — 2-4 sentence summary of behavior change.
   - `PLAN_OR_REQUIREMENTS` — pointer to the plan or spec.
   - `BASE_SHA`, `HEAD_SHA`.
   - `DESCRIPTION` — repro / how to verify.
3. **Reviewer returns findings ranked Critical / Important / Minor.**
4. **Act on feedback:**
   - **Critical** → fix immediately.
   - **Important** → fix before proceeding.
   - **Minor** → note for later.
5. **Push back** if the reviewer is wrong. Provide technical reasoning. Reference the failing/passing test that proves you. See [RECEIVING_REVIEW](RECEIVING_REVIEW.md).

## Constraints

- Never skip review because "it's simple".
- Never ignore Critical.
- Never proceed with unfixed Important.
- Never argue with valid technical feedback.

## Red flags

| Rationalization | Counter |
| :--- | :--- |
| "Too simple to review" | Especially this one. Cheap insurance. |
| "Will review at the end of all 12 tasks" | Reviewer's blast radius is the whole batch. Review per task / per ~3. |
| "Reviewer is wrong but I'll concede to keep peace" | Performative concession. Push back with reasoning. |

## Killer quotes

> "Review early, review often."

> "The reviewer gets precisely crafted context for evaluation — never your session's history."

## Example

Mid-plan: implementer finishes Task 4. Dispatch reviewer with summary + plan reference + BASE/HEAD SHAs. Reviewer returns Important: missing progress indicators on long loop; Minor: magic number 100. Fix Important. Note Minor in plan. Continue to Task 5.
