> Reference companion for the [superpowers](../SKILL.md) skill. Ported from `obra/superpowers/skills/executing-plans` (MIT, Copyright 2025 Jesse Vincent).

# Executing Plans

## When to fire

You have a written implementation plan to execute in a separate session with review checkpoints. Prefer [SUBAGENT_DRIVEN](SUBAGENT_DRIVEN.md) when subagents are available.

## Required upfront

[GIT_WORKTREES](GIT_WORKTREES.md) — set up isolated workspace before starting. Never start implementation on `main` / `master` without explicit user consent.

## Procedure

### Step 1 — Read and review

- Read the plan in full.
- Review critically. Raise concerns BEFORE starting.
- Only after concerns are addressed: create tasks via `TaskCreate` from the plan tasks. Proceed.

### Step 2 — Per task

- Mark task `in_progress`.
- Follow steps exactly. The plan has bite-sized steps; no improvisation.
- Run the verifications named in the task (see [VERIFICATION](VERIFICATION.md)).
- Mark `completed`.

### Step 2.5 — Batch close gate

After every ~3 tasks, check window utilization. If utilization > 65% AND the next batch is independent of the just-finished work, suggest `/compact` (harness primitive) with explicit preservation hints — the active plan, last task SHA, and tests-passing state. Do **not** `/compact` mid-batch (you lose the verification state). The gate is documented at [SKILL.md § Context Hygiene](../SKILL.md#context-hygiene); skip when utilization is below the threshold or batches are coupled.

### Step 3 — Finish

After all tasks: invoke [FINISHING_BRANCH](FINISHING_BRANCH.md). Required.

## Stop rules

Stop immediately on:

- Blockers (missing dependency, unclear instruction).
- Repeated verification failures (3+ on the same step → architectural question, not retry).
- Critical plan gaps.

Ask for clarification rather than guessing. If the partner updates the plan or the approach needs rethinking, return to Step 1.

## Constraints

- Never skip verifications.
- Reference any skills the plan names (e.g. "use [TDD](TDD.md)").
- Never start on `main` / `master` without explicit user consent.

## Red flags

| Rationalization | Counter |
| :--- | :--- |
| "I can guess what they meant" | Stop. Ask. |
| "Skip verification, last task was identical" | Each task verified. No batching. |
| "Three failures, one more try" | Stop. Architectural question. |
| "Just commit on main this once" | Never without explicit user consent. |

## Killer quotes

> "Don't force through blockers — stop and ask."

> "Stop when blocked, don't guess."

> "Never start implementation on main/master branch without explicit user consent."
