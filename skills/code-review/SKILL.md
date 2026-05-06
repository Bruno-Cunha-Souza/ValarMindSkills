---
name: code-review
description: "Lifecycle code review for Go, Rust, TypeScript. Auto-detects toolchain, runs static analysis, emits severity-ranked findings with file:line evidence, suggested diffs, risk tags (SAFE/REVIEW/BREAKING). Covers OWASP Top 10, perf anti-patterns, test quality. Read-only — every finding cites real file:line. Triggers: 'review code', 'revisar código', 'auditar código', '/code-review'."
source: ValarMindSkills
---

# Code Review Lifecycle

> "Code is read far more often than it is written. A review is the first reading after the first write." — adapted from the Go proverbs.

This skill conducts a structured, evidence-first review of a code change set. It is **read-only by default** — it never edits code, it produces a report. It is **language-aware** for Go, Rust, and TypeScript (Node and Bun); other languages are best-effort using the generic principles. It is **lifecycle-driven**: detect → sweep → read → assess → report → cross-link.

The skill exists because LLM reviewers tend to hallucinate findings: invented function names, wrong file paths, fabricated CVEs, and severity inflation. Every guardrail in the Constraints section is there to push back on those failure modes.

## When to Use

- A pull request is open and the user wants a thorough review before approving or merging.
- A specific commit, branch, or directory needs an audit (security, performance, maintainability, or all three).
- Legacy code is about to be refactored and the user wants a baseline assessment.
- A pre-release gate confirms the diff matches the quality level the team thinks they are running at.
- An incident post-mortem revealed a class of bug and the user wants the surrounding code swept for it.
- The user explicitly asks: `'review code'`, `'code review'`, `'revisar código'`, `'PR review'`, `'auditar código'`, or invokes `/valarmindskills:code-review`.

## Do not use when

- The user wants to **fix** code — this skill never edits. Hand off to the user or to `@code-debugger` for runtime issues.
- The user wants a **commit message** or **release notes** — use `@github-commit` or `@github-release-note`.
- The change is a single typo, comment edit, or trivial rename — review overhead exceeds the value; tell the user and stop.
- The change is in a language the skill cannot detect (not Go, Rust, TypeScript, or covered by an explicit `@<lang>` skill). Surface the gap and ask whether the user wants a generic pass.
- The user wants to **run tests** or **execute** the code — this skill is static; it reads, it does not run. Use `@code-debugger` for runtime triage.
- The diff is on infrastructure (Terraform, Kubernetes manifests) — use `@nextjs-security-pro`, `@golang-api-security`, or `@ci-cd-generator` for those domains.

## Prerequisites

Install before starting a review. Each tool's absence is logged and the related Phase is degraded but never silently skipped.

| Tool | Purpose | Install |
| --- | --- | --- |
| `git` | Diff and blame inspection | system package |
| `gh` (GitHub CLI) | Pull request metadata, review comments | `brew install gh` then `gh auth login` |
| `rg` (ripgrep) | Pattern sweep across the diff | `brew install ripgrep` / `apt install ripgrep` |
| `fd` | Fast file finder | `brew install fd` / `apt install fd-find` |
| `jscpd` | Multi-language clone detection | `npm install -g jscpd` |
| `semgrep` | Polyglot SAST with rules per language | `brew install semgrep` / `pip install semgrep` |
| `golangci-lint` | Go meta-linter (50+ linters) | `go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest` |
| `staticcheck` | Go advanced static analysis | `go install honnef.co/go/tools/cmd/staticcheck@latest` |
| `govulncheck` | Go CVE scan | `go install golang.org/x/vuln/cmd/govulncheck@latest` |
| `cargo clippy` | Rust idiomatic linter | `rustup component add clippy` |
| `cargo audit` | Rust CVE scan | `cargo install cargo-audit` |
| `cargo deny` | Rust dependency policy | `cargo install cargo-deny` |
| `tsc` | TypeScript compiler (`--noEmit`) | per-project |
| `eslint` / `biome` | TypeScript linter | per-project |
| `knip` | Find unused TS exports/files/deps | `bunx knip` / `npx knip` |
| `npm audit` / `bun audit` | Node/Bun CVE scan | bundled with package manager |

Required access:

- [ ] Read access to the repository and the diff (locally or via `gh pr diff`)
- [ ] Permission to invoke linters and `--noEmit` compilations on the host (no execution beyond static analysis)
- [ ] If the review targets a private dependency: read access to that module

The skill does **not** require write access. It never commits, never pushes, never edits source files.

## Phase 0 — Project & Scope Detection

Detect language, package manager, and review scope before sweeping anything. Run the steps in order; stop at the first conclusive match per axis.

```bash
# Step 1 — language at the repo root
test -f go.mod        && echo "language: go"
test -f Cargo.toml    && echo "language: rust"
test -f package.json  && echo "language: typescript"
test -f tsconfig.json && echo "  ts-config: present"

# Step 2 — TypeScript runtime (only if language=typescript)
test -f bun.lockb         && echo "runtime: bun, pm: bun"
test -f pnpm-lock.yaml    && echo "runtime: node, pm: pnpm"
test -f yarn.lock         && echo "runtime: node, pm: yarn"
test -f package-lock.json && echo "runtime: node, pm: npm"

# Step 3 — review scope
git rev-parse --abbrev-ref HEAD                         # current branch
git diff --name-only origin/main...HEAD | wc -l         # files changed
git diff --shortstat origin/main...HEAD                 # additions/deletions
gh pr view --json number,title,baseRefName 2>/dev/null  # PR context if any

# Step 4 — polyglot or monorepo
fd -t f -d 3 '(go.mod|Cargo.toml|package.json)$' .      # multiple roots → monorepo
```

Persist as `$LANG ∈ {go, rust, typescript, polyglot, other}`, plus the diff range `$BASE..$HEAD`.

| `$LANG` | Reference to load | Primary linter |
| --- | --- | --- |
| `go` | [references/GOLANG.md](references/GOLANG.md) | `golangci-lint` |
| `rust` | [references/RUST.md](references/RUST.md) | `cargo clippy` |
| `typescript` | [references/TYPESCRIPT.md](references/TYPESCRIPT.md) | `tsc --noEmit` + `eslint`/`biome` |
| `polyglot` | Run Phase 1–5 per language detected | per-language |
| `other` | Skip Phase 1.2 sweeps; run Phase 2 + generic Phase 3–5 | semgrep generic ruleset |

If the diff exceeds **50 files** or **1500 lines**, ask the user to split the review or to scope it to a subset before proceeding. Large reviews dilute attention and amplify hallucination risk.

## Phase 1 — Static Analysis Sweep

Run the toolchain first; treat results as **leads**, never as conclusions. Calibration: every linter has known false-positive classes — start each automated finding at **Medium** severity and only promote to **High** with manual confirmation in Phase 2.

### 1.1 Automated Toolchain

```bash
# Polyglot SAST (always run if available)
semgrep --config=auto --error --severity=ERROR --severity=WARNING

# Go
golangci-lint run ./...
staticcheck ./...
go vet -all ./...
govulncheck ./...

# Rust
cargo clippy --all-targets --all-features -- -D warnings
cargo audit
cargo deny check

# TypeScript / Node / Bun
bunx tsc --noEmit              # or: npx tsc --noEmit
bunx biome check .             # or: bunx eslint .
bunx knip
bun audit                      # or: npm audit --omit=dev

# Duplication (any language)
npx jscpd --min-lines 5 --min-tokens 50 ./
```

For each tool, capture the raw output and keep the version (`<tool> --version`) in the findings report. A finding without a tool version is not reproducible.

### 1.2 Pattern Sweep — language-agnostic

For each category below, run the grep across the diff only (`git diff --name-only origin/main...HEAD | xargs rg ...`) and read the matching files for context.

| # | Category | Detection |
| --- | --- | --- |
| 1 | **Hardcoded secrets** | `rg -i '(password\|secret\|api[_-]?key\|token\|bearer)\s*[:=]\s*["\x27][A-Za-z0-9/+=_-]{8,}["\x27]'` |
| 2 | **TODO/FIXME/XXX** | `rg -n '\b(TODO\|FIXME\|XXX\|HACK)\b'` (each is a finding when shipping to main) |
| 3 | **Stack trace exposure** | `rg -n '(stack\|stacktrace\|traceback\|panic)' --type-add 'web:*.{go,ts,tsx,rs}' --type web` |
| 4 | **Unbounded loops / collections** | `rg -n 'for\s*\(\s*;;\s*\)\|while\s*\(true\)\|loop\s*\{' ` |
| 5 | **Disabled error handling** | `rg -n '_ =\|catch\s*\(\s*_\s*\)\|\.unwrap\(\)\|\.expect\(\|\.ok\(\)\.unwrap\('` |
| 6 | **Insecure crypto** | `rg -n '(md5\|sha1\|des\|InsecureSkipVerify\|crypto/rand vs math/rand)'` |
| 7 | **Logging of sensitive data** | `rg -n 'log\.(Info\|Debug\|Print).*\b(password\|token\|secret\|cookie\|authorization)\b'` |
| 8 | **Wide-open CORS** | `rg -n 'Access-Control-Allow-Origin.*\*\|AllowAllOrigins\|origin: ["\x27]\*'` |
| 9 | **Disabled lints / suppressions** | `rg -n '(// nolint\|//nolint\|#\[allow\(\|@ts-ignore\|@ts-nocheck\|eslint-disable)'` |
| 10 | **Test code in production paths** | `rg -n '(println\!\|console\.log\|fmt\.Println)' --glob '!**/*test*'` |

Per-language sweeps live in [references/GOLANG.md](references/GOLANG.md), [references/RUST.md](references/RUST.md), and [references/TYPESCRIPT.md](references/TYPESCRIPT.md).

## Phase 2 — Manual Read-Through

Read the diff with the same posture a teammate would: from base branch to head, file by file, **top to bottom**. The automated tools cannot judge intent — this phase is where intent meets implementation.

### 2.1 Read order

1. **Tests first** if any new tests exist — they encode the author's intent.
2. **Public API surface** — exported functions, types, routes, schemas, CLI flags.
3. **Internal logic** — handlers, services, business rules.
4. **Plumbing** — DI wiring, config, build.
5. **Infrastructure** — Dockerfile, workflow, IaC (only if it touches the diff).

### 2.2 Read-through questions

For every changed function or block, answer in your head:

- Is the **name** intention-revealing? Could a reader infer purpose without reading the body?
- Does the function **do one thing**? If not, why is the merge OK?
- What happens with **nil / empty / negative / huge / concurrent** inputs?
- What **invariants** must hold before and after this code runs? Are they checked or assumed?
- Where does **untrusted input** enter? Where does it leave the boundary trusted?
- What **resource** is acquired? Where is it released? Under failure?
- What **time** does this code take in the worst case? Memory? Allocations?
- Could this **race** with another goroutine / task / Promise?
- Are **errors propagated with context** or swallowed?
- If this **panics / crashes / throws**, what is the blast radius?

A finding is born only when the answer is unsatisfactory **and** the evidence is in the diff. Hallucinations are findings born without one of those two preconditions.

### 2.3 Diff hygiene

| Smell | Detection | Action |
| --- | --- | --- |
| Unrelated changes mixed in | `git diff --name-only` against the PR description | Ask the author to split |
| Whitespace-only churn | `git diff --ignore-all-space` shows a smaller diff | Note as Low severity, not blocking |
| Large generated files committed | `*.lock`, `*.min.js`, `dist/` in the diff | Verify intentional; check `.gitignore` |
| Re-formatted file alongside a tiny logic change | Many lines changed, few semantic | Ask for a separate format-only commit |

## Phase 3 — Security Review

Run after Phase 2 because security findings depend on understanding intent. The OWASP API Top 10 (2023) and OWASP Web Top 10 (2021) are the reference frames.

### 3.1 Security categories (sweep + read)

| OWASP | Category | What to read |
| --- | --- | --- |
| API1 | Broken Object Level Authorization (BOLA / IDOR) | Every handler that takes an ID — does it check ownership? |
| API2 | Broken Authentication | Token issue/refresh/revoke paths; password handling |
| API3 | Broken Object Property Level Authorization | Mass assignment; allow-listed fields on update |
| API4 | Unrestricted Resource Consumption | Rate limits, body size limits, pagination caps |
| API5 | Broken Function Level Authorization | Admin / non-admin route separation, RBAC checks |
| API6 | Unrestricted Access to Sensitive Business Flows | Captcha / quotas on signup, order, transfer |
| API7 | Server-Side Request Forgery | Outbound HTTP calls with user-supplied URLs |
| API8 | Security Misconfiguration | Headers (CSP, HSTS), TLS, debug flags, default creds |
| API9 | Improper Inventory Management | Public endpoints not in OpenAPI / spec |
| API10 | Unsafe Consumption of APIs | Deserialization of upstream JSON without schema |
| Web1–10 | Web equivalents | XSS, SQLi, SSRF, etc. — see per-language reference |

For deeper Go-specific OWASP audits, hand off to `@golang-api-security`. For Next.js, hand off to `@nextjs-security-pro`. This skill stops at "this PR likely introduces a class-X issue at file.ext:LINE — recommend running the dedicated skill".

### 3.2 Cross-language security smells

Every language's reference file ([GOLANG](references/GOLANG.md), [RUST](references/RUST.md), [TYPESCRIPT](references/TYPESCRIPT.md)) lists detection commands and code examples for: SQL injection, XSS, SSRF, path traversal, command injection, insecure deserialization, hardcoded secrets, insecure crypto, log injection, open redirect, race conditions, resource exhaustion.

## Phase 4 — Performance & Scalability Review

Performance findings have the lowest hallucination tolerance — the LLM cannot benchmark. Constrain claims to **patterns known to scale poorly**, not to predicted latencies.

| # | Anti-pattern | Sweep |
| --- | --- | --- |
| 1 | **N+1 queries** | Loop body containing a DB call (`rg -n -B1 'for .*\{' --type go \| grep -A1 -E '(db\.\|tx\.\|repo\.)'`) |
| 2 | **Missing index hint** | New WHERE/JOIN on a column not in any migration in the diff |
| 3 | **Sync I/O on hot path** | Blocking call inside a request handler (e.g. `time.Sleep`, `fs.readFileSync`, `block_on`) |
| 4 | **Unbounded buffering** | `bufio.Scanner` without `Buffer()`; `Vec::new()` then unbounded `push`; `for await ... of stream` without limit |
| 5 | **Premature serialization** | Marshalling 10k-row collections into a single response |
| 6 | **Missing context / cancellation** | New goroutine / task without `context.Context` / `CancellationToken` / `AbortSignal` |
| 7 | **Lock granularity** | `Mutex` held across an I/O call; `Arc<Mutex<HashMap>>` where `DashMap`/`RwLock` would suffice |
| 8 | **Allocation in hot loop** | `string +` concatenation in a tight loop; `clone()` per iteration |
| 9 | **Memory leak via closure capture** | Long-lived closure capturing a request-scoped value |
| 10 | **Cache poisoning / unbounded cache** | New cache without TTL or size cap |

Every finding must cite a file:line and quote the exact code; "this might be slow" without code is not a finding.

## Phase 5 — Test, Maintainability & Style Review

### 5.1 Tests

- New code path → new test? If not, severity at least **Medium** unless covered by an existing test that the diff also exercises.
- Test asserts **behavior** (output, side effect) or **implementation** (mock call count)? Behavior tests are durable; implementation tests are smells unless justified.
- Negative paths covered: error propagation, edge inputs, timeouts, cancellation.
- Race detector / property-based tests for concurrent code (Go `-race`, Rust `loom`, TypeScript `fast-check`).
- Test names readable as sentences (`TestServer_RejectsUnauthenticatedRequest`).

### 5.2 Maintainability (overlap with `@clean-code`)

- Function size: > 30 lines is a smell. > 60 lines is a finding.
- Cyclomatic complexity: > 10 is a smell. > 20 is a finding.
- Duplication: same block in 2 places is a smell on the **third** occurrence; before that, leave it. Use the Rule of Three.
- Naming: if a name needs a comment to explain it, the name is wrong.
- Comments: each comment should explain **why**, not **what**. Drop "what" comments.
- Public surface: every new exported symbol must have a use site or a doc-comment. If neither, ask why it is exported.

For deep refactor recommendations, hand off to `@clean-code`.

### 5.3 Style

Rely on the project's auto-formatter (`gofmt`, `rustfmt`, `prettier`/`biome`). Style differences that the formatter would catch are not findings — they are bugs in the CI configuration.

## Phase 6 — Findings Synthesis & Output

Aggregate, deduplicate, and rank. Each finding is a row in the report; each row needs every column filled or it is dropped.

### 6.1 Severity rubric

| Severity | Definition | Examples |
| --- | --- | --- |
| **Critical** | Direct exploit, data loss, or full service outage if merged | RCE, plain-text creds, missing auth on admin route |
| **High** | Likely exploit, partial outage, or silent data corruption | BOLA in a list endpoint, panic in a handler, unbounded query |
| **Medium** | Latent bug, fragile code, or notable maintainability hit | Missing test, swallowed error, function > 60 lines |
| **Low** | Style, naming, comment hygiene, minor smells | Stuttering name, unnecessary `clone()`, magic number |
| **Info** | Observation, not a defect | "Consider extracting helper", "Worth a benchmark" |

Calibration aids — see [references/SEVERITY_RUBRIC.md](references/SEVERITY_RUBRIC.md) for the full Impact × Likelihood matrix and per-tool false-positive notes.

### 6.2 Risk tag

Tag every suggested change so the author can triage:

- `SAFE` — isolated, no behavior change, no public API impact.
- `REVIEW` — touches middleware, auth, shared utils, or a module boundary.
- `BREAKING` — changes a signature, response shape, schema, or observable behavior.

### 6.3 Confidence tag

- `High` — the evidence is exhaustive and the reasoning is mechanical.
- `Medium` — the pattern matches but intent could plausibly justify it.
- `Low` — the reviewer would benefit from a second opinion.

If `Confidence=Low` **and** `Severity ≥ High`, escalate explicitly: state "needs human review before action".

## Constraints

- **Never edit code.** This skill is a reviewer, not an editor. Suggestions are diffs in the report, never `Edit`/`Write` calls.
- **Never invent a file path, function name, or symbol.** Every reference must be copied from the diff or the repo. If you do not know, say "not in diff — please confirm".
- **Never claim a test passes / fails without showing the command and its output.** This skill does not run tests; if test results are needed, ask the user to run them and paste output.
- **Never invent a CVE.** Cite only CVEs that appear in `govulncheck`, `cargo audit`, `npm audit`, or `semgrep` output of this run.
- **Never quote a line you did not read.** Open the file at the cited line; the quote in the report must match byte-for-byte.
- **Never inflate severity to look thorough.** Inflated severity erodes trust. Use the rubric.
- **Never list a finding without a `file:line`, a code quote, an impact, a fix, and a risk tag.** Drop incomplete findings.
- **Always run language detection (Phase 0) before sweeping (Phase 1).** Skipping detection produces wrong-language patterns and false positives.
- **Always cap a single review at 50 files / 1500 lines.** If exceeded, ask to split before continuing.
- **Always emit the report verbatim in the Output format below** — even if there are zero findings.
- **Always cross-link to the dedicated skill** when the finding belongs to its domain (`@golang-api-security`, `@nextjs-security-pro`, `@clean-code`, `@code-debugger`).
- **Must include the tool versions used** in the report. A review without tool versions is not reproducible.

## Output format

Print verbatim after every successful run. The report is the deliverable.

```text
code-review: <branch / PR# / commit range>
  language(s):     <go | rust | typescript | polyglot>
  scope:           <files changed> files / <lines added>+ / <lines deleted>-
  tools:           semgrep <ver>, golangci-lint <ver>, ...
  duration:        Phase 0–6 walked

Findings (ranked by severity, then by file):

| ID  | Sev      | Conf   | Risk     | File:Line                | Title                              |
| --- | -------- | ------ | -------- | ------------------------ | ---------------------------------- |
| R001 | Critical | High   | REVIEW   | api/handlers/order.go:42 | BOLA — missing user_id check       |
| R002 | High     | Medium | SAFE     | api/store/db.go:118      | Unbounded SELECT without LIMIT     |
| R003 | Medium   | High   | SAFE     | api/util/log.go:7        | Logs Authorization header verbatim |
| R004 | Low      | High   | SAFE     | api/handlers/order.go:8  | Stuttering name OrderOrder         |

Detailed findings:

  R001 — BOLA — missing user_id check
    File:        api/handlers/order.go:42
    Code:
      | order, err := h.store.GetOrder(ctx, c.Param("id"))
      | if err != nil { ... }
      | c.JSON(200, order)
    Impact:      Any authenticated user can read any order by guessing IDs.
    Suggested fix (REVIEW):
      | order, err := h.store.GetOrder(ctx, c.Param("id"))
      | if err != nil { ... }
    + if order.UserID != claims.UserID { c.AbortWithStatus(403); return }
      | c.JSON(200, order)
    Verification: add an integration test that asserts a 403 when user A
                  requests user B's order id.
    Cross-link:  See @golang-api-security Phase 2 for full BOLA audit.

  R002 — Unbounded SELECT without LIMIT
    File:        api/store/db.go:118
    Code:
      | rows, err := db.QueryContext(ctx, "SELECT * FROM orders WHERE user_id=$1", uid)
    Impact:      Memory exhaustion when a user has many orders.
    Suggested fix (SAFE): add LIMIT/OFFSET pagination + max-page-size guard.
    Verification: load test with 10k-row user; verify p99 latency stays bounded.

  ... (one block per finding) ...

Summary:
  Critical: 1   High: 1   Medium: 1   Low: 1   Info: 0
  Blocking-merge findings: 2 (R001, R002)
  Suggested next step:
    1. Author addresses R001 and R002 before re-request.
    2. Run @golang-api-security Phase 2 to confirm no further BOLA cases.
    3. Re-review with `/valarmindskills:code-review` after fixes.

Skill version: code-review @ <git rev of SKILL.md>
```

When there are zero findings, print the same skeleton with `(no findings)` rows and a one-line summary `LGTM — no blocking issues found in scope.` followed by any Info-level observations.

## Related Skills

- `@code-debugger` — when a finding is a runtime failure rather than a code-review concern, hand off here.
- `@clean-code` — for refactor patterns and Rule-of-Three deduplication recommendations.
- `@golang-api-security` — deeper Go REST API security audit (Gin, Fiber).
- `@nextjs-security-pro` — Next.js App Router security audit.
- `@nextjs-optimization-pro` — Next.js performance and rendering review.
- `@api-security-best-practices` — multi-language secure API design patterns.
- `@api-security-testing` — active (runtime) API security testing.
- `@web-vulnerabilities` — vulnerability catalog for cross-linking findings.
- `@github-pr-review` — GitHub-flavored PR review (posts comments via `gh`).
- `@github-commit` — when the author wants help drafting the fix commit.
- `@superpowers` — engineering posture (TDD, evidence-first) for the author addressing findings.

## References

- [CHECKLIST](references/CHECKLIST.md) — copy-paste cheat sheet ordered by review phase
- [SEVERITY_RUBRIC](references/SEVERITY_RUBRIC.md) — Impact × Likelihood matrix, OWASP/CWE map, per-tool false-positive notes
- [GOLANG](references/GOLANG.md) — Go-specific patterns, sweeps, and example findings
- [RUST](references/RUST.md) — Rust-specific patterns, sweeps, and example findings
- [TYPESCRIPT](references/TYPESCRIPT.md) — TypeScript / Node / Bun patterns, sweeps, and example findings
- [EXAMPLE](EXAMPLE.md) — end-to-end worked review of a Go pull request
