> Reference companion for the [superpowers](../SKILL.md) skill. Ported from `obra/superpowers/skills/subagent-driven-development` (MIT, Copyright 2025 Jesse Vincent).

# Subagent-Driven Development

## When to fire

Executing an implementation plan with independent tasks in the current session. Pick this over [EXECUTING_PLANS](EXECUTING_PLANS.md) when staying in-session is preferred.

## Required upfront

[GIT_WORKTREES](GIT_WORKTREES.md). Subagents should use [TDD](TDD.md). After all tasks: [FINISHING_BRANCH](FINISHING_BRANCH.md).

Never start work on `main` / `master` without explicit user consent.

## Procedure

### Setup

- Read the plan once. Extract **all** tasks with full text + scene-setting context.
- Create tasks via `TaskCreate` with all tasks.
- **Do not** make subagents read the plan. Provide complete task text directly. Plan files drift; copies are immutable.

### Per task

1. **Dispatch implementer.** Fresh subagent. Provide full task text + repo context (paths, conventions). Cheap/fast model for mechanical 1-2 file work; standard for multi-file integration; most capable for design/review.
2. **Answer questions** the implementer asks. Do not let it guess.
3. **Implementer** implements, tests, commits, self-reviews. Returns status.
4. **Status handling:**
   - `DONE` — proceed to spec review.
   - `DONE_WITH_CONCERNS` — read concerns first, address or document, then proceed.
   - `NEEDS_CONTEXT` — supply missing context and re-dispatch with it.
   - `BLOCKED` — diagnose: more context, more capable model, smaller pieces, or escalate.
5. **Dispatch spec reviewer.** Compare implementation to spec. Output: list of compliance gaps.
6. **Fix gaps if any.** Spec compliance must be clean before quality review.
7. **Dispatch code-quality reviewer.** Output: list of quality issues by severity.
8. **Fix issues if any.** Critical and Important fixed; Minor noted.
9. **Mark task complete.**

### After all tasks

- Dispatch a final code reviewer for the whole implementation.
- Invoke [FINISHING_BRANCH](FINISHING_BRANCH.md).

## Two-stage review — order is fixed

1. **Spec compliance FIRST.**
2. **Code quality SECOND.**

Never start code-quality review while spec compliance has open issues.

## Constraints

- Fresh subagent per task. **Never let context leak between tasks.**
- Never dispatch multiple **implementation** subagents in parallel — conflicts.
- Never accept "close enough" on spec compliance.
- Never let self-review replace actual review.
- Never move to next task with open review issues.
- Never manually fix failed-subagent work in your own context — pollutes your context. Re-dispatch.

## Red flags

| Rationalization | Counter |
| :--- | :--- |
| "Skip spec review, the code looks right" | Spec first. Always. |
| "Implementer self-reviewed, no need" | Self-review is not review. |
| "I'll just patch this in my context" | Context pollution. Re-dispatch. |
| "Force the same model with the same prompt to retry" | Diagnose. More context, smaller piece, more capable model, or escalate. |
| "Run two implementers in parallel for speed" | File conflicts. One at a time. |

## Killer quotes

> "Fresh subagent per task + two-stage review (spec then quality) = high quality, fast iteration."

> "Never ignore an escalation or force the same model to retry without changes."

> "Don't try to fix manually (context pollution)."

## Example

Task 2: implementer adds a `--json` flag spec did not request, skips progress reporting. Spec reviewer flags both. Implementer fixes. Code reviewer flags magic number 100. Implementer extracts `PROGRESS_INTERVAL`. Both reviewers re-approve. Task complete.
