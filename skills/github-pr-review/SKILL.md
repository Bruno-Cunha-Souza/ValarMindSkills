---
name: github-pr-review
description: "Structured GitHub PR review — correctness, security, performance, maintainability. Severity-ranked findings + verdict (Approve/Request Changes/Comment). Non-PR: @code-review. Triggers: 'review PR', 'revisar PR', 'analisar pull request', '/github-pr-review'."
source: ValarMindSkills
---

# Pull Request Code Review

> Structured GitHub PR review with severity-ranked, citation-bound findings and a clear verdict.

## Goal

Structured code review of a GitHub Pull Request — correctness, security, performance, maintainability. Findings ranked by severity, each tied to a verbatim diff citation, plus a verdict (Approve / Request Changes / Comment).

## When to Use

- The user names a PR by number, URL, or branch and asks for a review.
- The user asks for "feedback", "thoughts", or "concerns" on a pull request.
- The user explicitly invokes `/github-pr-review` or `/valarmindskills:github-pr-review`.

## Do not use when

- The user asks about code-review methodology, not a specific GitHub PR → use `@code-review`.
- The user wants to author a commit or PR description, not review one → use `@github-commit` or `@github-release-note`.
- The PR contains no code diff (docs only, lockfile bumps, config-only) and the user wants security/perf analysis — refuse with `out of scope: no code diff to analyze` and hand off.

## Inputs you must collect before starting

| Input | Required | How to obtain |
| :--- | :--- | :--- |
| PR identifier | Yes | Number, URL, or branch name; ask if missing |
| Repository | Yes | Infer from current directory; ask if ambiguous |
| Review depth | No | `quick` (high-level) or `deep` (line-by-line) — default: `deep` |

## Procedure

### Step 1 — Fetch PR metadata

```bash
gh pr view <number> --json title,body,author,baseRefName,headRefName,files,additions,deletions,commits,labels,state,isDraft
```

Record: title, author, base/head branch, files changed, lines added/removed, commits, state (open/closed/merged), draft flag.

If `state != "OPEN"` or `isDraft == true`, warn the user and ask whether to continue. Do not refuse — historical reviews are valid use cases.

### Step 2 — Get the full diff

```bash
gh pr diff <number>
```

If the PR has more than 1000 changed lines, inform the user and ask whether to (a) continue full review, (b) prioritize a file subset, or (c) abort. Do not silently truncate.

### Step 3 — Read description and linked issues

- Read the PR description for context and intent.
- Look up linked issues via `gh issue view <number>` for `Closes #N`, `Fixes #N`, `Refs #N`.
- Identify acceptance criteria, if any.

### Step 4 — Analyze the changes

Analyze the diff across four dimensions. Only review changed code — not surrounding unchanged code.

#### Logic & Correctness
- Business requirements met?
- Edge cases (null, empty, boundaries, concurrency)?
- Error flows correct?
- Loop / recursion termination?
- Type consistency?

#### Security
- Inputs validated and sanitized?
- Injection risk (SQL, XSS, command, SSRF, path traversal)?
- AuthN / AuthZ checks?
- Sensitive data exposure (logs, responses, env)?
- OWASP Top 10 alignment?

#### Performance
- N+1 queries or inefficient DB access?
- Unbounded iteration?
- Allocation in hot loops?
- Algorithmic complexity vs. expected volume?
- Blocking calls where async fits?

#### Maintainability
- Naming clarity (variables, functions, classes)?
- Single responsibility, function size?
- Module coupling?
- Test coverage for the changes?
- Style consistency with the rest of the codebase?

### Step 5 — Categorize each finding

Each finding must include `Severity`, `Confidence`, and a verbatim citation:

| Severity | Criteria |
| :--- | :--- |
| **Critical** | Crash, data loss, exploitable vulnerability, breaks existing functionality |
| **Major**    | Bug in a likely scenario, significant performance issue, important standard violation |
| **Minor**    | Recommended improvement, readability impact, incomplete error handling |
| **Nitpick**  | Stylistic or naming suggestion — does not block approval |

| Confidence | Meaning |
| :--- | :--- |
| **High**   | Mechanical evidence in the diff; reasoning is deterministic |
| **Medium** | Pattern matches but intent may justify it — flag for author |
| **Low**    | A second opinion would change the verdict — escalate or downgrade |

**Citation requirement.** Cite `path:line` AND quote the exact code (3–8 lines from the diff). A finding without both is rejected. Never paraphrase the code; never invent paths, line numbers, or function names.

### Step 6 — Write the executive summary

2–4 sentences with:
- What the PR does (paraphrased from the diff, not the description).
- Quality assessment.
- Key concerns, if any.
- Verdict: **Approve**, **Request Changes**, or **Comment**.

The verdict must match the highest finding severity:
- Any `Critical` or `Major` → `Request Changes`.
- Only `Minor` / `Nitpick` → `Comment` or `Approve` (author discretion).
- Zero findings after Step 8 verification → `Approve` with `LGTM`.

### Step 7 — Present the review

Follow the template in [`EXAMPLE.md`](./EXAMPLE.md). For zero-findings PRs, follow the LGTM template in the same file.

If the user explicitly approves, publish via:

```bash
gh pr review <number> --approve --body "<message>"
gh pr review <number> --request-changes --body "<message>"
gh pr review <number> --comment --body "<message>"
```

Never publish without explicit user approval — one approval is scoped to one publish action.

### Step 8 — Verify before presenting

Before returning the review, check:

1. Every cited `path:line` appears in the diff from Step 2.
2. Every code quote is verbatim from the diff (no paraphrase, no fabricated lines).
3. Every finding has a `Severity` and a `Confidence` field.
4. The verdict in the executive summary matches the highest finding severity per Step 6.
5. If zero findings, the output uses the `LGTM` template — not a synthesized Minor.
6. No finding was promoted from Minor to Major to fill the report.

If any check fails, repair before returning.

## Refusal hooks

- **Out of scope (non-code PR):** if the PR is docs-only, lockfile-only, or config-only and the user asked for security / performance analysis, respond `out of scope: no code diff to analyze — switching to <appropriate skill>` and hand off.
- **Ambiguous PR identifier:** if multiple PRs match (e.g., a branch name with multiple open PRs), ask exactly one clarifying question listing the candidates, then stop.
- **Base branch missing locally:** if `gh pr diff` fails because the base ref is not fetched, request `git fetch <remote> <base>` from the user and stop.
- **Publish without approval:** never call `gh pr review --approve|--request-changes|--comment` without an explicit, in-conversation approval scoped to that PR.

## Constraints

- Only review changed code — do not review surrounding unchanged code.
- Do not assume context not visible in the diff; read referenced files via `Read` to understand the change, but do not flag them.
- Be constructive — propose a fix alongside every finding.
- Prioritize by severity; do not bury Critical issues under Nitpicks.
- Cite `path:line` AND a verbatim 3–8 line code quote per finding. Never invent paths, line numbers, function names, CVE IDs, or RFC numbers.
- Never fabricate findings to fill the report. Zero findings is a valid outcome — emit the `LGTM` template and stop.
- Never promote a Minor to Major to look thorough. Severity is bound to impact × likelihood, not to report length.
- If the PR is > 1000 lines, ask before proceeding (Step 2).
- Never publish the review on GitHub without explicit, scoped user approval.

## Output format

Structured review following the template in [`EXAMPLE.md`](./EXAMPLE.md):

- Executive summary (2–4 sentences) ending with the verdict.
- Findings grouped by severity (Critical → Major → Minor → Nitpick), each with `Confidence`, `path:line`, code quote, suggested fix.
- Summary by severity table.
- Zero-findings path: `LGTM` template from `EXAMPLE.md`.

## Example request

- "Review PR #42"
- "Analyze this pull request: https://github.com/org/repo/pull/123"
- "Do a quick review of the payment feature PR"
- "Revisar PR #87 desse repo"
- "Feedback no PR mais recente"

## Related Skills

- `@code-review` — lifecycle code-review skill (multi-language Go/Rust/TS). Use when the user wants methodology-driven review not tied to a GitHub PR (audit, pre-merge gate, refactor review).
- `@code-debugger` — when a finding here uncovers a runtime bug that needs root-cause analysis.
- `@github-commit` — when the review concludes `Approve` and the user wants to author the merge commit.
- `@code-security-review` — hand off security findings into a stack-aware audit (Go branch — `references/golang/`; Next branch — `references/nextjs/`).

## References

| File | Purpose |
| :--- | :--- |
| [EXAMPLE.md](./EXAMPLE.md) | Worked review (Request Changes) + zero-findings (Approve / LGTM) template |
