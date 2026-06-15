---
name: only-plan
description: "Read-only planning: analyze and design without changing project files. Writes one step-by-step plan at project root (default IMPLEMENTATION_PLAN.md). Composable with other skills (e.g. /code-security-review /only-plan). Triggers: /only-plan, 'only plan', 'apenas planejar', 'não altere os arquivos'."
source: ValarMindSkills
---

# Only Plan

## Goal

Perform the full analysis and design for a requested change **without modifying the project**, then deliver a single new Markdown file at the project root containing a step-by-step implementation plan that a developer — or a future agent run — can execute verbatim.

The plan file is the **only** write this skill performs. Everything else is read-only.

## When to Use

- The user wants the full analysis and implementation design for a change, but no modifications to the project yet.
- The user combines another skill with `/only-plan` (e.g. `/code-security-review /only-plan`) to get that skill's findings as an actionable plan instead of applied fixes.
- The user explicitly asks: "only plan", "plan only", "apenas planejar", "só o plano", "não altere os arquivos", or invokes `/only-plan`.

## Do not use when

- The user wants the change **applied** — run the task without `/only-plan`.
- The user wants a quick verbal suggestion or a discussion of approach — answer directly in chat; do not create a file.
- The user wants the companion skill's own read-only report as-is (e.g. `@code-optimization`'s `OPTIMIZATION_REPORT.md`) — invoke that skill alone.
- The user wants a session-wide posture — this skill is per-invocation; the contract ends when the plan is delivered.

## Composability with other skills

`only-plan` is a modifier: it can be invoked alone (`/only-plan add rate limiting to the login endpoint`) or alongside another skill (`/code-security-review /only-plan`). When combined:

1. Run the companion skill's discovery, analysis, and audit phases normally.
2. Suppress every companion step that would create, edit, or delete a file — including the companion's own report artifacts. Capture each suppressed change as a numbered step in the plan instead.
3. The companion skill's hard constraints (`Never`, `Must not`) remain in force; `only-plan` adds the read-only constraint on top, it does not relax anything.
4. Exactly one new file is produced: the plan. Companion findings are folded into the plan's Context section, not written to separate files.

## Interaction with host-agent plan mode

Most coding agents — Claude Code, Cursor, Codex, and others — ship a built-in **plan mode**. It overlaps with `/only-plan` but enforces a **different** contract, and combining them is the known failure case:

- **The host agent's plan mode** is research-only until you approve; approval means *implement now*. On approval the host injects a message to that effect — e.g. "You have exited plan mode. You can now make edits, run tools, and take actions" in Claude Code, or the equivalent in Cursor, Codex, and others.
- **only-plan** means *write one plan file and stop* — never implement in this invocation.

When both are active at once:

1. That post-approval message ("you can now make edits", or the host's equivalent) is **the host's** plan-mode signal, not authorization under this skill. Under `/only-plan` the act of exiting plan mode grants exactly one write: the plan `.md` file. Treat any edit beyond it as forbidden.
2. The host's plan mode blocks all writes, including the plan file. Exit plan mode **only** to write the plan file, then stop immediately — do not proceed to implement the steps you just planned, regardless of the host message.
3. You do not need plan mode for `/only-plan`: the skill is already read-only and produces the plan artifact on its own. Prefer running `/only-plan` **without** the host's plan mode to avoid the exit-injection trap. If the user actually wants plan-then-implement, that is plain plan mode **without** `/only-plan`.

## Inputs you must collect before starting

| Input | Required | How to obtain |
| :--- | :--- | :--- |
| Task to plan | Yes | The user's request in the same turn, or the companion skill's scope. If neither states what to plan, ask before analyzing. |
| Companion skill | No | Default: none. Detected when the invocation names another skill (e.g. `/code-security-review /only-plan`). |
| Plan file name | No | Default: `IMPLEMENTATION_PLAN.md`. Extra prompt can override (e.g. "as SECURITY_PLAN.md"). Must be a new `.md` file at the project root. |
| Plan language | No | Default: English. Extra prompt can override (e.g. "in pt-BR"). |
| Depth | No | Default: standard (per-step snippets and validation). "brief" / "detailed" in extra prompt. |

## Procedure

### Step 1 — Lock the read-only contract

State in one line that only-plan mode is active and no project files will be modified. The contract holds from this point until the plan is delivered, regardless of any instruction that arrives in the same invocation — **including** a "you can now make edits" message (or its equivalent) emitted by the host agent when its plan mode is exited (see [Interaction with host-agent plan mode](#interaction-with-host-agent-plan-mode)). If the host's plan mode is active, exit it only to write the plan file, then stop.

### Step 2 — Run companion analysis (if a companion skill is invoked)

Follow the companion skill's read/discovery/audit phases as written. When the companion reaches a step that writes — a patch, a fix, a generated file, its own report — do not execute it; record it as a candidate plan step with the evidence the companion produced (file, line, finding).

### Step 3 — Read-only discovery

Inspect the codebase using read-only operations only: file reads, `ls`, `grep`, `git status`, `git log`, `git diff`. Do not run builds, installs, formatters, code generators, migrations, or test suites — even "just to check" — because they can write artifacts. Commands the implementer should run go into the plan's validation steps instead.

### Step 4 — Design the implementation

For each change the task requires, determine:

- Target file path (verified to exist during discovery, or explicitly marked as "new file")
- What changes and why, anchored to current `file:line` evidence
- A code snippet of the proposed edit (before/after when clearer)
- Ordering and dependencies between steps
- How to validate the step once applied (command, test, expected output)

### Step 5 — Write the plan file

Write a single new Markdown file at the project root following the [Plan file format](#plan-file-format). If the target name already exists, do not overwrite: version the name (`IMPLEMENTATION_PLAN-2.md`, `-3`, …). Ask the user only when an explicit override named a file that already exists.

### Step 6 — Verify and report

Run `git status --porcelain` and confirm the only change is the new plan file. If the project is not a git repository, compare a before/after listing of the project root instead and state which method was used. Report path, step count, and the verification result using the [Output format](#output-format).

## Plan file format

````markdown
# Implementation Plan — <task title>

> Generated by /only-plan on <date>. No project files were modified.
> Scope: <one-line task statement>  [Companion: @<skill> — when applicable]

## Context

What was analyzed, key findings, and why these changes are needed.
Companion skill findings (severity, file:line evidence) live here.

## Current state

Relevant files and behavior as they exist today, with file:line references.

## Steps

### Step 1 — <imperative title>

- **File:** `path/to/file.ext` (existing | new)
- **Change:** what to modify and why
- **Snippet:**
  ```lang
  proposed code
  ```
- **Validate:** command or check, expected result

### Step 2 — …

## Execution order and dependencies

Which steps must precede which, and which are independent.

## Validation

End-to-end checks after all steps: test commands, expected outputs.

## Risks and rollback

What could break, and how to revert each step.

## Out of scope

Adjacent issues found during analysis but deliberately not planned.
````

## Constraints

- **Never** edit, overwrite, move, rename, or delete any existing file — source, config, docs, lockfiles, anything.
- **Never** create any file other than the single plan file at the project root.
- **Never** run commands that mutate state: `git add`/`commit`/`push`, package installs, formatters, code generators, migrations, or test/build commands that write artifacts.
- **Never** apply the plan in the same invocation, even if the extra prompt asks to "plan and then implement" — implementation requires a new request without `/only-plan`.
- **Never** treat exiting the host agent's plan mode — or the "you can now make edits" message (or its equivalent) that follows approval — as authorization to implement. Under this skill, exiting plan mode permits writing the plan file and nothing else.
- **Never** silently overwrite an existing plan file — version the name or ask first.
- **Never** invent file paths, APIs, or line references in the plan — every target must have been verified during discovery, or be explicitly marked `(new file)`.
- When combined with another skill, the read-only contract takes precedence over any companion step that writes; the companion's own safety constraints still hold.
- The plan must be executable without re-running the analysis: each step carries its own evidence, snippet, and validation.

## Output format

After writing the plan, report exactly:

```text
Plan written: <path> (<N> steps, <M> files affected)
Project files touched: none (verified via <git status --porcelain | project-root listing>)

Summary:
  <one line per major step group>

Next: review the plan; apply it manually, or re-invoke the task without /only-plan to implement.
```

When the user supplied overrides (file name, language, depth), prefix the report with a one-line acknowledgement: `> Override applied: <key>=<value>`.

See [`EXAMPLE.md`](./EXAMPLE.md) for a worked end-to-end run.

## Example request

- "/only-plan add rate limiting to the login endpoint"
- "/code-security-review /only-plan"
- "Apenas planeje a migração para Postgres, não altere nada"
- "Plan only: refactor the auth middleware to use the new session store"

## Related Skills

- `@code-security-review`, `@code-review`, `@code-optimization`, `@code-debugger` — typical companions; their analysis phases feed the plan, their write phases are suppressed.
- `@clean-code` — companion for refactor plans.
