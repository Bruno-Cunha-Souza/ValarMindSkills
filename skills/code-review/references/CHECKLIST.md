# Code Review — Checklist

> Reference companion for the [code-review](../SKILL.md) skill. Copy-paste cheat sheet ordered by review phase. Use it as a working scratchpad while reading a diff.

## Phase 0 — Setup

- [ ] Diff is fetched locally (`gh pr checkout <#>` or `git fetch origin <branch>`)
- [ ] `$BASE_REF`, `$BASE_SHA`, and `$DIFF_RANGE` are captured from PR metadata or local merge-base
- [ ] Diff size ≤ 50 files / 1500 lines (otherwise ask to split)
- [ ] Language detected (`$LANG`); per-language reference loaded
- [ ] Monorepo/workspace roots mapped for every changed file
- [ ] PR description matches the diff (no scope creep)
- [ ] CI is green or the failures are understood (do not review on top of unknown CI failures)

## Phase 1 — Static Analysis

- [ ] `semgrep --config=auto` ran on the diff scope, output captured
- [ ] Language linter ran (`golangci-lint` / `cargo clippy` / `tsc + eslint|biome`)
- [ ] Vulnerability scanner ran (`govulncheck` / `cargo audit` / `npm audit`)
- [ ] Duplication scan (`jscpd`) ran if diff > 200 lines
- [ ] Each automated finding is captured with tool + version
- [ ] Each automated finding starts at **Medium** severity (calibration)
- [ ] Tests/runtime verification skipped unless requested or needed to confirm a finding

## Phase 2 — Manual Read-Through

For each new or changed function:

- [ ] Name is intention-revealing
- [ ] Function does one thing
- [ ] Inputs validated (nil/empty/negative/huge/concurrent)
- [ ] Invariants explicit, not assumed
- [ ] Resource lifecycle clear (acquire ↔ release, including failure paths)
- [ ] Errors propagated with context, not swallowed
- [ ] No untrusted input crosses a trust boundary unchecked
- [ ] Public symbols have a use site OR a doc comment
- [ ] No `TODO`/`FIXME`/`XXX` left untracked

## Phase 3 — Security

- [ ] Input validation at every external entry point (HTTP, queue, file, env)
- [ ] Output encoding correct for the sink (HTML, SQL, shell, log)
- [ ] AuthN check before any handler that needs it
- [ ] AuthZ (BOLA) check on every resource lookup by ID
- [ ] Mass assignment guarded (allow-list of writable fields)
- [ ] Rate limit, body size, pagination caps in place for new endpoints
- [ ] Outbound HTTP / DNS / file calls cannot be steered by user input (SSRF)
- [ ] Secrets are not in source, logs, errors, or test fixtures
- [ ] No new use of weak crypto (`md5`, `sha1`, `des`, `math/rand`, `InsecureSkipVerify`)
- [ ] No new wide-open CORS / missing security headers
- [ ] Deserialization of untrusted JSON has a schema or struct boundary
- [ ] No `eval` / dynamic `require` / shell expansion of user data

## Phase 4 — Performance & Scalability

- [ ] No DB call inside a loop (N+1) — use `IN`/`JOIN`/batch
- [ ] New WHERE/JOIN columns have a migration that adds an index
- [ ] No blocking I/O on a request handler hot path
- [ ] Buffers and collections are bounded (size cap, TTL)
- [ ] New goroutines / tasks / Promises receive `context` / `AbortSignal` / cancellation
- [ ] Locks not held across I/O calls
- [ ] Hot loops do not allocate per iteration
- [ ] Cache has TTL and size cap; invalidation path documented
- [ ] Pagination / streaming used for any unbounded collection in a response

## Phase 5 — Tests & Maintainability

- [ ] New code path has a test
- [ ] Existing tests were searched before filing a missing-test finding
- [ ] Tests assert behavior, not implementation
- [ ] Negative paths covered (errors, edge inputs, timeouts)
- [ ] Concurrent code has race / loom / property test
- [ ] Function size ≤ 30 lines; > 60 is a finding
- [ ] Cyclomatic complexity ≤ 10; > 20 is a finding
- [ ] Duplication caught only on the third occurrence (Rule of Three)
- [ ] No name needs a comment to explain itself
- [ ] No "what" comments — only "why"

## Phase 6 — Output Hygiene

- [ ] Every finding cites `path:line`
- [ ] Every finding quotes the exact source
- [ ] Every finding states impact, suggested fix, risk tag, confidence
- [ ] Severity follows the rubric (no inflation)
- [ ] CVE references map back to scanner output of this run
- [ ] Cross-links to dedicated skills present where applicable
- [ ] Tool versions captured in the report header
- [ ] Optional verification commands reported separately from static tools
- [ ] Summary lists blocking-merge findings explicitly

## Quick blocking-merge gate

A PR should not merge while any of the following is true:

- Any **Critical** finding
- More than one **High** finding without justification
- New code path with no test in the diff
- New endpoint with no AuthN/AuthZ check
- New SQL with no parameter binding
- New outbound HTTP with user-supplied URL and no allow-list
- New crypto without a documented algorithm choice
- CI failing on a check the team treats as required
