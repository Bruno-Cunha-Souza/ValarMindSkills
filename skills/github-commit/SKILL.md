---
name: github-commit
description: Use this skill when I ask to commit, create a commit, write a commit message, or save my changes with a conventional commit.
source: ValarMind Skills
---

# Conventional Commit

## Goal

Analyze staged changes in the git repository and generate a commit message following the [Conventional Commits](https://www.conventionalcommits.org/) specification, adapted to the project's conventions when they exist.

## Inputs you must collect before starting

| Input | Required | How to obtain |
|-------|----------|---------------|
| Staged changes | Yes | `git diff --staged` |
| Project conventions | No | Check commitlint config, CLAUDE.md, CONTRIBUTING.md |
| Type, scope, or intent | No | Ask the user if not clear from the diff |

## Procedure

### Step 1 — Check staged changes

Run `git diff --staged`. If the result is empty, inform the user that there are no staged changes and offer help to stage files (`git add`).

### Step 2 — Summary of changed files

Run `git diff --staged --stat` to get a summary of modified, added, or removed files.

### Step 3 — Check project conventions

Look for project-specific commit configurations:

- `.commitlintrc`, `.commitlintrc.json`, `.commitlintrc.yml`, `commitlint.config.js`, `commitlint.config.ts`
- `commitlint` section in `package.json`
- `CONTRIBUTING.md`, `CLAUDE.md`
- Recent commit history: `git log --oneline -10`

If specific conventions are found, they take precedence over the default rules.

### Step 4 — Analyze the diff

Read the full diff and identify:

- What was added, removed, or modified
- The intent behind the changes (new feature, bug fix, refactor, etc.)
- Which areas of the codebase were affected

### Step 5 — Determine the commit type

Choose the most appropriate type:

| Type | When to use |
|------|-------------|
| `feat` | New feature for the user |
| `fix` | Bug fix |
| `refactor` | Code restructuring without changing behavior |
| `perf` | Performance improvement |
| `style` | Formatting, whitespace, semicolons (no logic change) |
| `test` | Adding or fixing tests |
| `docs` | Documentation only |
| `build` | Build system, external dependencies |
| `ci` | CI/CD configuration |
| `chore` | Maintenance tasks that don't fit other types |

### Step 6 — Determine the scope (optional)

Identify the scope from the area of the codebase affected. Examples: `auth`, `api`, `ui`, `db`, `config`. Only use the scope if it adds clarity.

### Step 7 — Compose the message

Build the message following this format:

```
<type>(<scope>): <description>

<optional body>

<optional footer>
```

**Description** (subject line) rules:
- Maximum 72 characters
- Imperative mood ("add", not "added" or "adds")
- Lowercase first letter
- No period at the end

**Body** rules (when needed):
- Separated from the description by a blank line
- Wrap at 72 characters
- Explain the "why" of the change, not the "what"
- Use when the description alone is not sufficient

**Footer** rules (when applicable):
- `BREAKING CHANGE: <description>` for backward-incompatible changes
- `Refs: #<number>` to reference issues or PRs
- `Co-authored-by: Name <email>` for co-authorship

### Step 8 — Present and confirm

1. Present the complete message in a code block
2. Wait for the user's approval
3. After approval, execute `git commit` with the message

## Constraints

- Follow the Conventional Commits spec strictly
- Never invent changes — only describe what the diff shows
- Subject line must be at most 72 characters, imperative mood, lowercase, no period
- Body must wrap at 72 characters, separated by a blank line
- If the project has its own conventions, they take precedence
- Include `BREAKING CHANGE:` in the footer when the change breaks backward compatibility
- Reference issues/PRs in the footer when mentioned by the user
- Never commit without explicit user approval
- Never include the AI agent: Claude, Codex, etc. in the commit message

## Output format

Present the complete commit message in a code block, followed by a confirmation prompt. See examples in [`EXAMPLE.md`](./EXAMPLE.md).

## Example request

- "Commit my changes"
- "Create a commit for the login fix"
- "Commit these changes as a feat"
- "Commit with scope api"
