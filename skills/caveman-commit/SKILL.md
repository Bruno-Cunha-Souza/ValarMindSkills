---
name: caveman-commit
description: "Terse Conventional Commit: subject ≤50 chars imperative, body only when 'why' non-obvious, standard trailer. For full-detail use @github-commit. Triggers: 'caveman commit', 'terse commit', 'commit curto', '/caveman-commit'."
source: https://github.com/JuliusBrussee/caveman/tree/main
---

# Caveman Commit

## Goal

Produce a Conventional Commit message with the minimum prose needed to describe the change: a short imperative subject and, only when necessary, a short body that captures a non-obvious reason. Preserve all Conventional Commits semantics (type, optional scope, breaking-change marker) so tooling downstream still works.

## Inputs you must collect before starting

| Input | Required | Default | How to obtain |
| :--- | :--- | :--- | :--- |
| Staged changes | Yes | — | `git diff --staged` |
| Project conventions | No | Conventional Commits | `.commitlintrc*`, `commitlint` in `package.json`, `CONTRIBUTING.md`, `CLAUDE.md` |
| Type, scope, or intent | No | Inferred from diff | Ask the user only if the diff is ambiguous |
| Body | No | Omit | Include only when the *why* is non-obvious from the diff |

## Procedure

### Step 1 — Check staged changes

Run `git diff --staged`. If empty, tell the user there are no staged changes and offer to stage files with `git add`. Do not proceed.

### Step 2 — Scan the diff and project conventions

Run, in parallel:

```bash
git diff --staged --stat
git log --oneline -10
```

Check for `.commitlintrc*`, `commitlint.config.{js,ts}`, the `commitlint` key in `package.json`, `CONTRIBUTING.md`, and `CLAUDE.md`. Project conventions win over defaults.

### Step 3 — Pick the type

| Type | When to use |
| :--- | :--- |
| `feat` | New user-facing behavior |
| `fix` | Bug fix |
| `refactor` | Same behavior, restructured code |
| `perf` | Performance-only change |
| `test` | Tests added or fixed |
| `docs` | Docs only |
| `build` | Build system, deps |
| `ci` | CI/CD config |
| `chore` | Maintenance that fits nowhere else |
| `style` | Whitespace, formatting, no logic change |

Add `!` after the type (or scope) when the change is breaking: `feat(api)!: …`.

### Step 4 — Compose the subject

Rules:

- **≤ 50 characters** total (caveman-commit is stricter than the 72 of `@github-commit`).
- Imperative mood: `add`, `fix`, `drop`, not `added` / `fixes` / `dropping`.
- Lowercase first letter after the colon.
- No period at the end.
- No emoji.
- Scope is optional. Include only when it disambiguates (e.g., `fix(auth):` when the diff also touches unrelated files).
- No decorative prefixes, no issue numbers in the subject.

### Step 5 — Decide about the body

**Default: no body.** Write a body only if at least one of the following is true:

- The change encodes a non-obvious trade-off (a workaround, a constraint, a perf tweak, an external incident).
- The change is breaking and `BREAKING CHANGE:` details are mandated.
- An issue or ticket reference is required by the project.

When present, body rules:

- Separated from the subject by a blank line.
- Wrap at 72 characters.
- **At most 3 short bullets** (`- …`) or 3 short lines. No paragraphs.
- State the *why*, never restate the *what*.

### Step 6 — Footer (only when applicable)

- `BREAKING CHANGE: <one-line description>` for breaking changes.
- `Refs: #<n>` or `Closes: #<n>` when the user mentions issues or tickets.
- The repository's standard trailer if `CLAUDE.md` or local convention requires one.

### Step 7 — Present and confirm

1. Show the full message in a fenced code block, ready to paste.
2. Wait for the user's approval.
3. On approval, run `git commit` using a heredoc:

```bash
git commit -m "$(cat <<'EOF'
<type>(<scope>): <subject>

<optional body>

<optional footer>
EOF
)"
```

4. Run `git status` after the commit to confirm it landed.

## Constraints

- **Subject ≤ 50 chars, imperative, lowercase, no period, no emoji.** This is the skill's hard rule; do not soften it.
- **No body by default.** If you added a body, be able to name the non-obvious reason that earned it.
- **Never invent changes.** Describe only what the staged diff shows.
- **Never commit without explicit user approval.**
- **Never skip or alter the project's mandatory trailer** (e.g., a required `Co-Authored-By` or DCO `Signed-off-by`).
- **Never include AI-agent names** (Claude, Codex, Copilot, etc.) in the subject or body.
- Commit text is an artifact, not a conversation — caveman posture applies to the composition style, not to the commit message format itself. The format stays Conventional Commits.

## Output format

A single fenced code block containing the full commit message, then a one-line confirmation prompt. See [`EXAMPLE.md`](./EXAMPLE.md).

## Example request

- "caveman commit"
- "/caveman-commit"
- "terse commit for these changes"
- "commit curto para esse diff"
- "commit caveman, subject só"
