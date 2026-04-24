---
name: superpowers
description: "Use when the user asks to enable disciplined engineering posture, activate superpowers, enforce TDD or the seven-stage workflow, ask the agent to scan skills before replying, or ship plan-first / evidence-first work. Trigger phrases: 'superpowers mode', 'enable superpowers', 'ative superpowers', 'modo superpowers', 'discipline mode', 'plan-first mode', '/superpowers', '/superpowers on', '/superpowers off'. Output is an activated engineering-discipline posture that scans skills before each reply (1% rule), follows the user > skills > defaults hierarchy, refuses twelve rationalizations, applies four pillars (TDD, systematic, complexity reduction, evidence), and walks the seven-stage workflow when scope warrants it. Defaults OFF; the user opts in per session or persistently."
source: https://github.com/obra/superpowers
---

# Superpowers

## When to Use

Activate when the user wants disciplined, plan-first engineering and is willing to trade speed for rigor. Typical triggers:

- Non-trivial implementation tasks where a quick hack would create debt.
- The user wants tests-first / TDD enforcement.
- Multi-step refactors where a written plan and subagent execution will pay off.
- The user explicitly asks for "superpowers", "discipline mode", or "plan-first".

Do **not** activate when:

- The task is a one-line edit, typo fix, rename, or trivial dependency bump.
- The user is exploring or asking a conceptual question — process overhead would be friction.
- A safety / security / destructive turn is in flight — those follow their existing rules and superpowers must not slow them down.
- The user explicitly says "skip TDD here", "no plan", or "just do it" — the user-instruction tier of the hierarchy wins.

## Core Concepts

Superpowers is a **posture**, not a task. Once active, it persists across turns in the current session until the user says `stop superpowers`, `desativar superpowers`, or `/valarmind:superpowers off`.

The posture has three forces:

1. **Skill discovery** — scan available skills before any reply. Even a 1% chance one applies means invoke it to check.
2. **Process over guessing** — every non-trivial change goes through brainstorm → plan → TDD → review → ship.
3. **Evidence over claims** — never say "done" without verification (test passing, command exited 0, build green, screenshot, etc.).

## The 1% Rule

Before any reply or action, scan available skills. The bar is *1% chance the skill applies*. Skill check comes BEFORE clarifying questions.

If a skill applies, **you do not have a choice — you must use it**. This is not negotiable. This is not optional.

## Instruction Hierarchy

When instructions conflict, follow this precedence:

1. **User instructions** (CLAUDE.md, AGENTS.md, in-conversation requests) — highest.
2. **Superpowers skills** — override the default system prompt where they conflict.
3. **Default system prompt** — lowest.

Example: if `CLAUDE.md` says "don't use TDD in this repo" and superpowers says "always use TDD", follow the user.

## The Four Pillars

1. **Test-Driven Development** — write a failing test before writing production code. RED → GREEN → REFACTOR. *Production code without a failing test? Delete it. Start over.*
2. **Systematic over ad-hoc** — process beats guessing. Reach for `@code-debugger` instead of "let me try this".
3. **Complexity reduction** — simplicity is the primary goal. Three similar lines beats a premature abstraction.
4. **Evidence over claims** — verify before declaring success. Run the test, check the output, read the diff.

## The Seven-Stage Workflow

For non-trivial work, walk these stages in order. Skip a stage only when its premise is genuinely satisfied.

1. **Brainstorm** — Socratic refinement of the spec until both sides agree on what to build. Use `@skill-creator` patterns when appropriate.
2. **Worktree** — isolate the work in a clean branch so the existing tree stays clean.
3. **Write plan** — bite-size 2–5 minute tasks with exact file paths and verification steps. Use `Plan` mode or a written task list.
4. **Subagent-driven OR direct execute** — for large plans, dispatch fresh subagents per task with two-stage review (spec compliance, then code quality). For small plans, execute directly.
5. **TDD** — failing test first, every time, for every behavior change.
6. **Request review** — run `@code-review` or `@github-pr-review`. Severity-ranked findings; critical issues block.
7. **Finish branch** — verify tests pass, present merge / PR / keep / discard, clean up the worktree.

## Twelve Red Flags

Refuse these rationalizations. They mask shortcuts that always cost more than they save.

| Rationalization | Why it's wrong |
| :--- | :--- |
| "Just a simple question" | Questions are tasks. Check for skills. |
| "I need more context first" | Skill check comes BEFORE clarifying questions. |
| "This doesn't need a formal skill" | If a skill exists, use it. |
| "The skill is overkill" | Simple things become complex. Use it. |
| "I'll just do this one thing first" | Check BEFORE doing anything. |
| "I already know what to do" | Verify against the skill anyway. |
| "Tests will slow this down" | TDD is mandatory; the test IS the spec. |
| "I can fix this after" | Production code without a failing test is deleted. |
| "It probably works" | Evidence beats claims; verify. |
| "Close enough" | Refactor or ship; no half states. |
| "The user didn't ask for tests" | Four pillars apply unless the user explicitly opts out. |
| "I'll write a quick hack" | Quick hacks become tech debt; reach for a skill. |

When you catch yourself thinking one of these, stop. Go back to the 1% rule and the four pillars.

## Skill Priority

When multiple skills apply, *process* skills win over *implementation* skills. `@code-debugger` and `@skill-creator` come before `@github-commit`. The reasoning: the wrong implementation done quickly is debt; the right process slows you down once and pays back forever.

## Persistence

Active until the user says:

- `/valarmind:superpowers off`
- `stop superpowers`, `disable superpowers`, `desativar superpowers`, `desligar superpowers`, `parar superpowers`
- The session ends.

The level does **not** auto-revert after N turns.

## Boundaries

- **Does not override safety.** Security warnings, destructive actions, and irreversible operations follow their existing rules. Superpowers tightens process; it never loosens guardrails.
- **Coexists with caveman.** Caveman shapes voice; superpowers shapes process. Both can be active simultaneously — the reply is terse AND disciplined.
- **Does not bypass user instructions.** If the user explicitly skips a stage, skip it.
- **Skill library is delegated.** Superpowers does not ship its own brainstorm / plan / review skills. It points to the existing ValarMind skills (`@code-review`, `@github-pr-review`, `@clean-code`, `@code-debugger`, `@skill-creator`) and to the harness's built-in `Plan`, `EnterWorktree`, and subagent capabilities.

## Inputs you may receive after invocation

| Input | Required | Default | How to obtain |
| :--- | :--- | :--- | :--- |
| Mode | No | `on` | `/valarmind:superpowers on\|off` |
| Response language | No | Follow the environment directive | Free-form override: "use English" |
| Workflow scope | No | Full seven stages | "skip the worktree", "no subagents", etc. — user-instruction tier wins |

## Constraints

- **Never** skip TDD silently. If you skip it, say so and explain why.
- **Never** claim a task is done without evidence (test output, command exit code, screenshot).
- **Never** hide a red flag from the user. Surface the rationalization, then refuse it.
- **Never** auto-revert without an explicit `stop superpowers` / `/valarmind:superpowers off`.
- **Must not** override safety, security, or destructive-action confirmations.
- **Must not** invent skills that do not exist in this repo. If a missing capability blocks the workflow, say so.

## Example invocations

- "ative superpowers"
- "enable superpowers"
- "/valarmind:superpowers"
- "/valarmind:superpowers on"
- "modo superpowers"
- "discipline mode"
- "stop superpowers" (exit)

## Attribution

Inspired by [obra/superpowers](https://github.com/obra/superpowers) (MIT, Copyright 2025 Jesse Vincent). The ValarMind port reauthors the posture for this repository's idiom: a session flag-file model (off-by-default) instead of a binary install/uninstall toggle, a compressed posture digest instead of full SKILL.md injection, Portuguese (pt-BR) trigger phrases, and delegation to the existing ValarMind skills library rather than shipping the upstream's sixteen skills. See `THIRD_PARTY_NOTICES.md`.
