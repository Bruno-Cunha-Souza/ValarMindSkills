---
name: github-pr-review
description: Use this skill when I ask to review a pull request, analyze a PR, check PR code quality, or give feedback on a GitHub PR.
source: ValarMind Skills
---

# Pull Request Code Review

## Goal

Perform a structured, comprehensive code review of a GitHub Pull Request, analyzing correctness, security, performance, and maintainability. Present findings clearly, prioritized by severity.

## Inputs you must collect before starting

| Input | Required | How to obtain |
|-------|----------|---------------|
| PR identifier | Yes | Number, URL, or branch name — ask the user |
| Repository | Yes | Infer from current directory or ask the user |
| Review depth | No | `quick` (high-level) or `deep` (line-by-line) — default: `deep` |

## Procedure

### Step 1 — Fetch PR metadata

Run:

```bash
gh pr view <number> --json title,body,author,baseRefName,headRefName,files,additions,deletions,commits,labels
```

Record: title, author, base/head branch, number of files, lines added/removed, number of commits.

### Step 2 — Get the full diff

Run:

```bash
gh pr diff <number>
```

If the PR has more than 1000 changed lines, inform the user and suggest focusing on the most critical files. Ask whether to continue with the full review or prioritize.

### Step 3 — Read description and linked issues

- Read the PR description to understand the context and intent of the changes
- If there are linked issues (e.g., "Closes #123"), look them up with `gh issue view <number>`
- Identify acceptance criteria, if any

### Step 4 — Analyze the changes

Analyze the diff across 4 dimensions:

#### Logic & Correctness
- Are business requirements met?
- Are edge cases handled (null, empty, boundaries, concurrency)?
- Are error flows correct?
- Do loop and recursion conditions have guaranteed termination?
- Are data types consistent?

#### Security
- Are inputs validated and sanitized?
- Is there injection risk (SQL, XSS, command)?
- Are authentication and authorization checks in place?
- Is sensitive data exposed (logs, API responses, environment variables)?
- Alignment with OWASP Top 10?

#### Performance
- Are there N+1 queries or inefficient database access?
- Are unbounded collections being iterated?
- Are there unnecessary allocations in loops?
- Is algorithmic complexity appropriate for the expected volume?
- Are there blocking calls where async would be more appropriate?

#### Maintainability
- Are variable, function, and class names clear?
- Do functions have a single responsibility and reasonable size?
- Is coupling between modules low?
- Is there adequate test coverage for the changes?
- Is the style consistent with the rest of the codebase?

### Step 5 — Categorize findings by severity

| Severity | Criteria |
|----------|----------|
| **Critical** | Bug that causes crashes, data loss, exploitable security vulnerability, or breaks existing functionality |
| **Major** | Bug in a likely scenario, significant performance issue, violation of important project standards |
| **Minor** | Recommended code improvement, style inconsistency impacting readability, incomplete error handling |
| **Nitpick** | Stylistic suggestion, alternative naming, comment for clarity — does not block approval |

### Step 6 — Write the executive summary

Write a 2-4 sentence summary containing:

- What the PR does (in your own words, based on the diff analysis)
- Overall quality assessment
- Key concerns (if any)
- Verdict: **Approve**, **Request Changes**, or **Comment**

### Step 7 — Present the review

Present the complete review following the format in [`EXAMPLE.md`](./EXAMPLE.md).

If the user requests it, publish the review on GitHub via:

```bash
gh pr review <number> --approve --body "message"
gh pr review <number> --request-changes --body "message"
gh pr review <number> --comment --body "message"
```

## Constraints

- Only review code that was changed in the PR — do not review surrounding unchanged code
- Do not assume context not visible in the diff; read referenced files if needed to understand the change
- Be constructive — suggest solutions, not just problems
- Prioritize by severity; do not bury critical issues under nitpicks
- Reference specific files and line numbers from the diff
- Never fabricate issues or invent code that is not in the diff
- If the PR is too large (>1000 lines), suggest splitting and focus on the most critical files
- Never publish the review on GitHub without explicit user approval

## Output format

Structured review following the template in [`EXAMPLE.md`](./EXAMPLE.md), with an executive summary, findings categorized by severity, and a final verdict.

## Example request

- "Review PR #42"
- "Analyze this pull request: https://github.com/org/repo/pull/123"
- "Do a quick review of the payment feature PR"
- "Review the latest PR on this repo"
