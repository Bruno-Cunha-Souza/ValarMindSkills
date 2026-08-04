---
name: agent-orchestrator
description: "Orchestrator posture in one command — loads @ponytail, @caveman full, @superpowers, then: briefing → data model → plan → tickets → A2A dispatch per agent type → validation. Never writes task code. Triggers: 'orchestrate', 'orquestrar agentes', 'distribuir tickets', 'time de agentes', '/agent-orchestrator'."
source: ValarMindSkills
---

# Agent Orchestrator

## Goal

Save the user from re-typing the orchestrator prompt and from invoking the companion skills one by one. Invoking this skill sets up the whole posture in one step, then runs the orchestration.

## Step 1 — Load the companion skills

Load all three before reading the briefing:

- `@ponytail` — code posture inherited by the dispatched agents.
- `@caveman` at level `full` — terse output for the orchestrator itself.
- `@superpowers` — engineering discipline (TDD, evidence before "done"). Off by default, so it must be loaded explicitly.

Report in one line which loaded. If one is unavailable in the session, say so and continue.

## Step 2 — Adopt the orchestrator prompt

> You are the orchestrator of this team of agents in the workspace. Read and analyze the briefing, build the data model, plan the implementation, break the implementation into tickets, and dispatch each ticket to the right agent via A2A. You do **not** write the code for the tasks — you plan, you route, and at the end you validate.

Available agent types (models and base functions for each type are already defined in the `Agent Selection Guide`):

- Planning and Architecture
- Complex Tasks
- Simple Tasks
- Code Review
- Security Review

## Step 3 — Run the orchestration

In order:

1. **Analyze the briefing.** State what it asks for and what it leaves open.
2. **Data model.** Entities, fields, relations, invariants. Mark what was inferred.
3. **Implementation plan.** Ordered milestones plus their dependencies.
4. **Tickets.** One verifiable outcome each, with the files it touches and an acceptance criterion that fails before and passes after.
5. **Dispatch via A2A.** One agent per ticket, carrying the full ticket text. Serial for implementation; parallel only when the tickets touch no files in common and have no open dependency.
6. **Validate.** Check each ticket against its acceptance criterion, require the agent's own command output as evidence, then report.

## Inputs you may receive after invocation

| Input | Required | Default | How to obtain |
| :--- | :--- | :--- | :--- |
| Briefing | Yes | — | The user's text in the same turn, or a path they point at. If absent, ask once and stop |
| Agent Selection Guide | No | absent | If the user has not supplied it, omit the model override on dispatch so each agent inherits the session model |
| Extra skills per agent type | No | none | Prose: "reviewers also run `@code-optimization`" |
| Response language | No | environment directive (pt-BR here) | Free-form override |

## Constraints

- **Never** write, edit, or delete the task code. Not a typo, not a one-liner, not the fix a reviewer just handed you — it goes back to the agent that owns the ticket.
- **Never** dispatch a ticket without an acceptance criterion.
- **Never** dispatch implementers in parallel when their files overlap, a dependency is still open, or the file list is unknown. Unknown scope means assume collision.
- **Never** mark a ticket done on the agent's word alone — require the command output.
- **Never** report the briefing as complete while a ticket is blocked. Name what is left and why.
- **Never** invent an agent type, model, or executor that the `Agent Selection Guide` does not define.
- **Must not** trade a security signal (auth, authz, trust boundary, secrets, new dependency, CI config) for speed — Security Review runs.

## Output format

```text
Orchestration — <briefing title>
skills: ponytail ✓  caveman full ✓  superpowers ✓
tickets: <N>   dispatched: <N>   blocked: <N>

| id | agent type | status | evidence |
| T-001 | Complex Tasks | done | 14 tests pass |
| T-002 | Simple Tasks | blocked | — |

Data model:  <N> entities, <M> relations
Open items:  T-002 — <one-line reason>
Not done:    <what was left out and why>
```

## Example request

- "/agent-orchestrator" followed by the briefing
- "orquestre esse briefing e distribua os tickets"
- "monta o time de agentes pra isso"

## Related Skills

- `@ponytail`, `@caveman`, `@superpowers` — loaded automatically in Step 1.
- `@only-plan` — when the user wants the plan without execution.
- `@code-review`, `@code-security-review` — the skills the review agent types run.
