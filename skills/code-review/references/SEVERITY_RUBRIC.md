# Code Review — Severity Rubric

> Reference companion for the [code-review](../SKILL.md) skill. Use this rubric to calibrate severity. Findings inherit severity from the worst row that applies.

## Severity definitions

| Severity | Meaning | Merge gate |
| --- | --- | --- |
| **Critical** | Direct exploit, data loss, service outage if merged as-is | Blocks merge |
| **High** | Likely exploit, partial outage, silent data corruption | Blocks merge |
| **Medium** | Latent bug, fragile code, notable maintainability hit | Blocks merge if no justification |
| **Low** | Style, naming, minor smell | Does not block merge |
| **Info** | Observation; not a defect | Never blocks |

## Impact × Likelihood matrix

Pick severity by intersecting Impact (Y) and Likelihood (X). Then adjust by Confidence (next section).

| Impact \ Likelihood | Almost certain | Probable | Possible | Unlikely |
| --- | --- | --- | --- | --- |
| **Catastrophic** (RCE, full data dump) | Critical | Critical | High | High |
| **Severe** (PII leak, AuthZ bypass) | Critical | High | High | Medium |
| **Moderate** (DoS, partial outage) | High | High | Medium | Medium |
| **Minor** (degraded UX, recoverable error) | Medium | Medium | Low | Low |
| **Cosmetic** (style, name, comment) | Low | Low | Low | Info |

### Likelihood definitions

- **Almost certain** — exploitable with public knowledge and no preconditions.
- **Probable** — exploitable with one realistic precondition (authenticated user, common config).
- **Possible** — exploitable under specific conditions an attacker can engineer.
- **Unlikely** — exploitable only with privileged position or rare configuration.

## Confidence

Each finding declares a confidence:

- **High** — evidence is exhaustive, reasoning is mechanical, the linter agrees.
- **Medium** — pattern matches but author intent could justify it; needs a reply.
- **Low** — partial evidence; reviewer would benefit from a second opinion.

**Escalation rule:** if `Confidence=Low` and `Severity ≥ High`, mark the finding `needs-human-review` in the report and do not present it as a blocking-merge finding without a human confirming it.

## Risk tag (for suggested fixes)

The risk tag describes the **fix**, not the finding.

| Tag | Meaning | Examples |
| --- | --- | --- |
| **SAFE** | Local change, no behavior change observable to callers | rename a private symbol, add a missing nil check, switch `md5` to `sha256` for a non-stored hash |
| **REVIEW** | Touches middleware, auth, shared utils, or a module boundary | add an authz middleware, change a logger format, rewrite an error wrapper |
| **BREAKING** | Changes a signature, response shape, schema, or observable behavior | add a required field, change an HTTP status code, remove a CLI flag |

## OWASP & CWE map

| Category | OWASP | Common CWE | Default severity floor |
| --- | --- | --- | --- |
| Broken Object Level Authorization | API1:2023 | CWE-639 | High |
| Broken Authentication | API2:2023 | CWE-287, CWE-307 | High |
| Broken Object Property Level Authz | API3:2023 | CWE-915 | High |
| Unrestricted Resource Consumption | API4:2023 | CWE-770 | Medium |
| Broken Function Level Authorization | API5:2023 | CWE-285 | High |
| Server-Side Request Forgery | API7:2023 | CWE-918 | High |
| Security Misconfiguration | API8:2023 | CWE-16 | Medium |
| Unsafe Consumption of APIs | API10:2023 | CWE-20 | Medium |
| SQL Injection | Web03:2021 | CWE-89 | Critical |
| Cross-Site Scripting | Web03:2021 | CWE-79 | High |
| Insecure Deserialization | Web08:2021 | CWE-502 | Critical |
| Path Traversal | — | CWE-22 | High |
| Command Injection | — | CWE-78 | Critical |
| Hardcoded Credentials | — | CWE-798 | Critical |
| Insecure Crypto | Web02:2021 | CWE-327 | High |
| Race Condition | — | CWE-362 | Medium |
| Open Redirect | — | CWE-601 | Medium |

The "default severity floor" is the **lowest** severity a confirmed finding in this category may receive. A Critical-floor finding never demotes to Medium even if the LLM thinks the impact is small.

## Per-tool false-positive calibration

Each automated tool has known FP-prone rules. Start at **Medium** and only promote with manual confirmation.

### Go

| Tool | Rule | Calibration |
| --- | --- | --- |
| `gosec` | G104 (unhandled error) | High FP rate; many ignored errors are intentional. Confirm each. |
| `gosec` | G115 (integer overflow conversion) | Often safe inside guarded paths; verify. |
| `gosec` | G404 (`math/rand` use) | Critical only if used for tokens/secrets; non-security uses are fine. |
| `staticcheck` | SA1019 (deprecated API) | Often Low; only High when the deprecation has a security driver. |
| `golangci-lint` | `dupl` | Frequently flags structurally similar but semantically different code. |

### Rust

| Tool | Rule | Calibration |
| --- | --- | --- |
| `cargo clippy` | `clippy::unwrap_used` | High in production code, Low in tests/examples. |
| `cargo clippy` | `clippy::missing_errors_doc` | Info-level for internal crates. |
| `cargo audit` | RUSTSEC advisory `informational` | Often Info; confirm the advisory is not a CVE before promoting. |
| `cargo deny` | `unmaintained` warning | Medium; verify there is no actual vulnerability before raising. |

### TypeScript / Node / Bun

| Tool | Rule | Calibration |
| --- | --- | --- |
| `eslint` | `@typescript-eslint/no-explicit-any` | Medium; many codebases tolerate `any` in narrow boundaries. |
| `tsc` | strictness errors | If the codebase is not strict-mode, treat as Info on existing files, Medium on diff. |
| `npm audit` | severity reported by registry | Cross-check against the actual import path; transitive dev-only deps are often Low. |
| `biome` | `noExplicitAny`, `noNonNullAssertion` | Same calibration as eslint equivalents. |
| `semgrep` | `audit` ruleset | Default Medium; promote only with manual confirmation. |

## Anti-patterns the LLM reviewer must refuse

The following habits inflate severity or invent findings. Refuse them at the report stage.

- **"This could be slow"** without a citation, a specific input size, and a known anti-pattern from Phase 4.
- **"This might leak memory"** without a code path showing the unreleased reference.
- **"This is vulnerable to X"** without an OWASP/CWE link **and** a `file:line` showing the pattern.
- **"Tests should be added"** as a finding when tests already exist for the path — verify by reading the test file before flagging.
- **"This violates SOLID"** without naming which letter and which pattern would actually fix it.
- **"This won't scale"** without naming the bound that breaks (rows, requests/sec, memory).
- **Citations to a CVE not present** in this run's `govulncheck` / `cargo audit` / `npm audit` / `semgrep` output.
- **Severity inflation** to Critical/High when the matrix above lands on Medium/Low.
