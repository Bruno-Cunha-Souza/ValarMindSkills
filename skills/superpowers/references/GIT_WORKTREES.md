> Reference companion for the [superpowers](../SKILL.md) skill. Ported from `obra/superpowers/skills/using-git-worktrees` (MIT, Copyright 2025 Jesse Vincent).

# Using Git Worktrees

## When to fire

Starting feature work that needs isolation from the current workspace, or before executing implementation plans. Required upfront for [SUBAGENT_DRIVEN](SUBAGENT_DRIVEN.md) and [EXECUTING_PLANS](EXECUTING_PLANS.md).

## Why

Prevents accidentally committing worktree contents to the repository. Allows multiple plans to execute in parallel without stepping on each other.

## Procedure

1. **Announce.** "Setting up an isolated worktree for this work."

2. **Pick a directory.** Priority order:
   - Existing `.worktrees/` (preferred).
   - Existing `worktrees/`.
   - `CLAUDE.md` preference, if set.
   - Ask the user. Offer `.worktrees/` (project-local) or `~/.config/superpowers/worktrees/<project-name>/` (global).

3. **For project-local directories, MUST verify the directory is gitignored.**
   ```bash
   git check-ignore -q .worktrees && echo IGNORED || echo NOT_IGNORED
   ```
   - If `NOT_IGNORED`: add to `.gitignore`, commit, then create the worktree. Fix broken things immediately.
   - No `.gitignore` check needed for the global directory.

4. **Detect project name.**
   ```bash
   PROJECT=$(basename "$(git rev-parse --show-toplevel)")
   ```

5. **Create worktree + branch.**
   ```bash
   git worktree add ".worktrees/$BRANCH_NAME" -b "$BRANCH_NAME"
   cd ".worktrees/$BRANCH_NAME"
   ```

6. **Auto-detect project setup and run.**
   - `package.json` → `npm install` (or `pnpm install` / `bun install` if lockfile present).
   - `Cargo.toml` → `cargo build`.
   - `pyproject.toml` → `poetry install` (or `pip install -r requirements.txt` if no poetry).
   - `go.mod` → `go mod download`.

7. **Run baseline tests.**
   - If they fail, **report and ask**, do not silently proceed.

8. **Report final state.**
   - Worktree location (full path).
   - Test count (passing/total).
   - Ready state.

## Constraints

- Never skip the ignore check for project-local directories.
- Never assume a directory location.
- Never proceed past failing baseline tests without asking.
- Never hardcode setup commands — detect from the repo.

## Red flags

| Rationalization | Counter |
| :--- | :--- |
| "Skip the ignore check, my last project had it set up" | Each project verified. |
| "Baseline tests fail but they're flaky" | Report and ask. Do not silently proceed. |
| "Just use the main checkout, faster" | Worktree exists for isolation. Do not skip. |

## Killer quotes

> "Systematic directory selection + safety verification = reliable isolation."

> "Why critical: prevents accidentally committing worktree contents to repository."

## Example

```
$ git check-ignore -q .worktrees && echo IGNORED || echo NOT_IGNORED
IGNORED
$ git worktree add .worktrees/auth -b feature/auth
$ cd .worktrees/auth
$ npm install
$ npm test
47 passed, 0 failed
$ echo "Worktree ready at $(pwd) — 47/0 baseline. Ready to implement auth feature."
```
