---
name: caveman-review
description: "Terse PR review — finding = 'path:line — problem. fix.' by severity, 2-sentence summary + verdict. Full-detail: @github-pr-review. Triggers: 'caveman review', 'terse review', 'revisar PR caveman', '/caveman-review'."
source: https://github.com/JuliusBrussee/caveman/tree/main
---

# Caveman Review

## Goal

Review a GitHub Pull Request and produce the shortest review that still lets the PR author act on every finding. Each comment is a single line: file, line number, the problem, and the fix. No preamble, no restatement of the diff, no nitpicks without an actionable fix.

## Inputs you must collect before starting

| Input | Required | Default | How to obtain |
| :--- | :--- | :--- | :--- |
| PR identifier | Yes | — | Number, URL, or branch — ask the user if absent |
| Repository | Yes | Current directory | Infer from `gh repo view` or ask |
| Review depth | No | `deep` | `quick` for high-level only, `deep` for line-by-line |
| Include nitpicks | No | `false` | Ask if the user wants nitpicks; default is to drop them |

## Procedure

### Step 1 — Fetch PR metadata

```bash
gh pr view <number> --json title,body,author,baseRefName,headRefName,files,additions,deletions,commits,labels
```

Record: title, author, base/head branch, file count, +/- lines, commit count.

### Step 2 — Get the diff

```bash
gh pr diff <number>
```

If the diff is over 1000 changed lines, tell the user and ask whether to focus on the most critical files before continuing.

### Step 3 — Read the description and linked issues

- Read the PR body for intent and acceptance criteria.
- For each `Closes #<n>` or `Refs #<n>`, run `gh issue view <n>` to pick up the acceptance criteria.

### Step 4 — Analyze across four dimensions

For every changed hunk, ask:

- **Correctness.** Business logic, edge cases (null, empty, boundaries, concurrency), error paths, termination guarantees.
- **Security.** Input validation, injection (SQL, XSS, command), authN/authZ checks, sensitive data in logs or responses, OWASP Top 10 alignment.
- **Performance.** N+1 queries, unbounded iteration, unnecessary allocations, blocking calls where async fits, algorithmic complexity.
- **Maintainability.** Naming, single responsibility, coupling, test coverage, style consistency with the surrounding code.

### Step 5 — Severity table

| Severity | Criteria |
| :--- | :--- |
| **Critical** | Crashes, data loss, exploitable vulnerability, breaks existing functionality |
| **Major** | Likely bug, notable perf issue, violates an important project standard |
| **Minor** | Recommended improvement, partial error handling, readability impact |
| **Nitpick** | Stylistic, naming alternative — drop by default, include only if the user asked |

### Step 6 — Compose the comments

Each finding is **one line**, in this exact shape:

```text
<path>:<line> — <problem>. <fix>.
```

Rules:

- Path and line are from the PR diff, not from local HEAD.
- Problem in 3–8 words. Fix in 3–8 words.
- No "consider…", no "maybe…", no "it might be better if…". Use imperative verbs: `use`, `rename`, `extract`, `guard`, `sanitize`, `await`, `batch`.
- If the fix requires a code example (one or two lines), append a fenced block on the next lines. Keep the code block intact — caveman posture never rewrites code snippets.
- If you cannot state the problem *and* the fix in a single line, promote the finding to a section with a minimal fenced example. Do not omit the fix.

Group comments under severity headings in this order: Critical → Major → Minor → Nitpick (skip Nitpick unless the user asked).

### Step 7 — Executive summary and verdict

Write **one to two sentences** stating what the PR does (based on the diff, not the description) and the highest-severity blocker, if any. End with a verdict on its own line:

> **Verdict:** Approve | Request Changes | Comment

### Step 8 — Present and optionally publish

Present the review in the format shown in [`EXAMPLE.md`](./EXAMPLE.md). If the user approves, publish with:

```bash
gh pr review <number> --approve          --body "<message>"
gh pr review <number> --request-changes  --body "<message>"
gh pr review <number> --comment          --body "<message>"
```

## Constraints

- **One line per finding.** If the finding needs more than one line of prose, split the problem into two findings or attach a fenced code block — do not expand into paragraphs.
- **Always pair a problem with a fix.** A comment that says what is wrong without saying what to do is noise.
- **Never fabricate issues.** Only raise findings grounded in the diff.
- **Never review unchanged code** surrounding the diff unless the PR description explicitly asks for a broader review.
- **Never publish on GitHub without explicit user approval.**
- **Code blocks stay intact.** No reformatting, no reflow, no renaming identifiers in example snippets.
- **Drop nitpicks by default.** Include only when the user asks. A nitpick without an invited audience is a cost, not a gift.
- **If the PR is over 1000 changed lines**, offer to scope down before reviewing.

## Output format

Follow [`EXAMPLE.md`](./EXAMPLE.md). The review consists of:

1. A two-line header with PR number, title, author, and branch arrow.
2. A 1–2 sentence executive summary.
3. A single-line verdict.
4. Findings grouped by severity, each as one line in the `path:line — problem. fix.` shape, with fenced code blocks attached only when a one-liner is insufficient.
5. A severity count table at the bottom.

## Example request

- "caveman review PR #42"
- "/caveman-review 187"
- "terse review this PR"
- "revisar PR caveman"
- "quick caveman review of the payment PR"
