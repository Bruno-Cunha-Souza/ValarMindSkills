> Reference companion for the [superpowers](../SKILL.md) skill. Ported from `obra/superpowers/skills/dispatching-parallel-agents` (MIT, Copyright 2025 Jesse Vincent).

# Dispatching Parallel Agents

## When to fire

2+ independent tasks that can be worked on without shared state or sequential dependencies. Examples: 3 test files failing for different root causes; multiple unrelated subsystem breaks; refactor sweeps across orthogonal directories.

## When NOT to fire

- Failures may be related (one agent might fight another).
- Full system context required.
- You don't yet know what's broken (investigate first; see [SYSTEMATIC_DEBUGGING](SYSTEMATIC_DEBUGGING.md)).
- Agents would touch shared state.

## Rules

- **One agent per independent problem domain.** Never one agent for "fix everything".
- **Agents never inherit your session's context or history.** You construct exactly what they need.
- Each prompt: focused (one domain), self-contained (all needed context), explicit about expected output (status + summary format).
- Provide specific scope, clear goal, constraints (e.g. "do NOT change production code"), and required summary format.
- Paste actual error messages and test names. Vague references ("fix the race condition") fail.
- **Forbid arbitrary timeout increases.** Instruct agents to find the real cause.

## After agents return

- Review each summary.
- Check for conflicts between agents' changes.
- Run the full test suite.
- Spot-check.

## Red flags

| Rationalization | Counter |
| :--- | :--- |
| "One agent for all the failing tests" | Independent problem domains. One per. |
| "Just say 'fix the race condition'" | Paste error, file:line, repro command. |
| "Bump the timeout from 5s to 30s" | Find the real cause. No arbitrary timeouts. |
| "Agent inherited my context, faster" | They never do. Build the prompt. |

## Killer quotes

> "Dispatch one agent per independent problem domain. Let them work concurrently."

> "They should never inherit your session's context or history — you construct exactly what they need."

> "Do NOT just increase timeouts — find the real issue."

## Example

Real session: 6 failures across 3 files, 3 agents dispatched in parallel. One replaced timeouts with event-based waiting. One fixed an event-structure bug. One waited for async tool execution. Zero conflicts. All 6 tests green after merge.

## Required output format from each agent

```
status: DONE | DONE_WITH_CONCERNS | NEEDS_CONTEXT | BLOCKED
files_changed: [list]
tests_passing: <count>/<total>
summary: <2-3 sentences>
concerns_or_blockers: <if any>
```
