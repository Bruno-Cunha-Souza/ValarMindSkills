> Reference companion for the [superpowers](../SKILL.md) skill. Ported from `obra/superpowers/skills/writing-plans` (MIT, Copyright 2025 Jesse Vincent).

# Writing Plans

## When to fire

After [BRAINSTORMING](BRAINSTORMING.md) produced an approved spec. Before touching code. Run inside a dedicated worktree (see [GIT_WORKTREES](GIT_WORKTREES.md)).

## Output

Plan file at `docs/superpowers/plans/YYYY-MM-DD-<feature-name>.md` (user prefs override).

## Iron rule

**Assume the engineer has zero codebase context and questionable taste.**

Every step copy-pasteable. Every code block real. Repeat code in tasks even when similar — the engineer may read tasks out of order.

## Procedure

1. **Scope check.** If the spec covers multiple independent subsystems, recommend splitting into separate plans before continuing.
2. **Map file structure.** Which files Create / Modify (with line ranges) / Test. Each file's single responsibility. Files that change together live together. Split by responsibility, not technical layer.
3. **Header.** Goal in one sentence. Architecture in 2-3 sentences. Tech stack list. Pointer: "Execute with [SUBAGENT_DRIVEN](SUBAGENT_DRIVEN.md) (recommended) or [EXECUTING_PLANS](EXECUTING_PLANS.md)."
4. **Bite-sized tasks.** Each task = one 2-5 minute action. Steps use checkboxes (`- [ ]`).
5. **Per task, list:** Files block (Create / Modify / Test), Step 1 failing test (with code), Step 2 run command + expected FAIL, Step 3 minimal impl (with code), Step 4 run + expected PASS, Step 5 invoke `@github-commit` (skill stages the diff, generates Conventional Commit, waits for user approval — fallback to raw `git add`/`git commit -m` only if the skill is unavailable).
6. **Self-review.** Coverage of every spec requirement. Placeholder scan. Type/method/property name consistency across tasks. Fix inline.
7. **Execution handoff.** Ask the user to choose [SUBAGENT_DRIVEN](SUBAGENT_DRIVEN.md) (recommended) or [EXECUTING_PLANS](EXECUTING_PLANS.md). Then invoke that skill.

## No placeholders, ever

Forbidden phrases:

- `TBD`, `TODO`, `implement later`, `add appropriate error handling`, `similar to Task N`, `write tests for the above` without code
- References to undefined types/functions
- "Implement appropriate validation" (no code)

All are plan failures.

## Disciplines

DRY. YAGNI. TDD. Frequent commits.

## Standard task template

```markdown
## Task N — Add `parseDuration` helper

### Files

- Create: `src/utils/time.ts`
- Test:   `src/utils/__tests__/time.test.ts`

### Steps

- [ ] **Step 1** — Write failing test.

```ts
// src/utils/__tests__/time.test.ts
import { parseDuration } from "../time";

describe("parseDuration", () => {
  it("parses 1h30m", () => {
    expect(parseDuration("1h30m")).toBe(5_400_000);
  });
});
```

- [ ] **Step 2** — Run. Expect FAIL: `Cannot find module '../time'`.

```bash
npm test -- time.test.ts
```

- [ ] **Step 3** — Implement minimum.

```ts
// src/utils/time.ts
export function parseDuration(input: string): number {
  const match = input.match(/^(\d+)h(\d+)m$/);
  if (!match) throw new Error("invalid duration");
  return (Number(match[1]) * 60 + Number(match[2])) * 60_000;
}
```

- [ ] **Step 4** — Run. Expect PASS: `1 passed`.

- [ ] **Step 5** — Commit via `@github-commit`.

```bash
git add src/utils/time.ts src/utils/__tests__/time.test.ts
# then invoke `@github-commit`: it reads the staged diff, drafts a Conventional
# Commit message, and waits for explicit approval before running `git commit`.
# Fallback if the skill is unavailable:
# git commit -m "feat(utils): add parseDuration for h/m strings"
```
```

## Red flags

| Rationalization | Counter |
| :--- | :--- |
| "Step is clear from context" | Engineer may read out of order. Show the code. |
| "Similar to Task 3" | Repeat the code. Out-of-order safe. |
| "Add appropriate validation" | Show what "appropriate" means in code. |
| Cross-task name drift (`clearLayers()` vs `clearFullLayers()`) | Self-review must catch. Pick one, sweep. |

## Killer quotes

> "Write comprehensive implementation plans assuming the engineer has zero context for our codebase and questionable taste."

> "Repeat the code — the engineer may be reading tasks out of order."

> "DRY. YAGNI. TDD. Frequent commits."
