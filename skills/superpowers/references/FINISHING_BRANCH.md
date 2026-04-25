> Reference companion for the [superpowers](../SKILL.md) skill. Ported from `obra/superpowers/skills/finishing-a-development-branch` (MIT, Copyright 2025 Jesse Vincent).

# Finishing a Development Branch

## When to fire

Implementation is complete, all tests pass, and the work needs to be integrated. Stage 7 of the seven-stage workflow.

## Procedure

### Step 1 — Verify tests (gate)

- Run the full test suite (see [VERIFICATION](VERIFICATION.md)).
- If any test fails: **stop**. Refuse to proceed to options. Fix the failure first.

### Step 2 — Determine base branch

```bash
BASE=$(git merge-base --fork-point origin/main HEAD)   # or main / master
```

If unsure, ask the user.

### Step 3 — Present exactly four options

No extra explanation. No editorializing.

```
1. Merge locally
2. Push and create PR
3. Keep as-is
4. Discard
```

Wait for the user to pick.

### Step 4 — Execute the choice

| Option | Steps |
| :--- | :--- |
| **1. Merge locally** | `git checkout <base>` → `git pull` → `git merge <feature>` → **re-run tests on merged result** → `git branch -d <feature>` |
| **2. Push and create PR** | `git push -u origin <feature>` → `gh pr create` with summary + test plan body |
| **3. Keep as-is** | Preserve worktree. Do not clean up. |
| **4. Discard** | Require user to type `discard` exactly. Only then `git branch -D <feature>`. |

### Step 5 — Cleanup

| Option | Worktree | Branch |
| :--- | :--- | :--- |
| 1 (merged) | Remove | Deleted (step 4) |
| 2 (PR) | **Keep** — user may amend after review | Kept |
| 3 (keep) | **Keep** | Kept |
| 4 (discard) | Remove | Deleted (step 4) |

```bash
git worktree remove ".worktrees/<branch>"
```

## Constraints

- Never proceed with failing tests.
- Never merge without re-verifying tests on the merged result.
- Never delete work without typed `discard` confirmation.
- Never force-push without explicit user request.
- Never offer open-ended "what next?" — exactly the four options.

## Red flags

| Rationalization | Counter |
| :--- | :--- |
| "Merge first, fix the failing test in main" | Stop. Fix on the feature branch. Then merge. |
| "Auto-clean the worktree after PR push" | Keep. User may amend. |
| "Discard — they said yes already" | Type `discard` exactly. |

## Killer quotes

> "Verify tests → Present options → Execute choice → Clean up."

> "Cannot proceed with merge/PR until tests pass."

> "Type 'discard' to confirm."
