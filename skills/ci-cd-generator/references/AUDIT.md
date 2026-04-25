> Reference companion for the [ci-cd-generator](../SKILL.md) skill.

# Audit Mode

The skill's secondary operating mode: instead of generating a new pipeline, **audit an existing `.github/workflows/`** against the same heuristics and security gates the generator emits.

Audit mode is read-only by default. It produces a findings report with severity-ranked issues, fix proposals, and a "what would the generator do differently" diff suggestion. It never edits the workflow without explicit user approval.

## When to run an audit

- The repository already has workflows authored before this skill existed
- A workflow merged with rubber-stamp review and the user wants a second pass
- A security incident exposed a CI weakness (compromised secret, malicious action) and the user wants the full surface checked
- Migrating from another CI platform — audit the imported GitHub Actions equivalents
- Pre-release gate: confirm a project's workflows match the security level the team thinks they are running at

## Inputs

| Input | Required | Default | How obtained |
| --- | --- | --- | --- |
| Workflow paths | No | `.github/workflows/*.yml` | `find .github/workflows -type f \( -name '*.yml' -o -name '*.yaml' \)` |
| Expected security level | No | Inferred (lowest gate present); user override allowed | Phase 1 |
| Expected language | No | Inferred from repo (`go.mod` / `Cargo.toml` / `package.json`) | Phase 0 of generator |
| Apply fixes | No | `false` (report-only) | User opt-in per finding |

If the repo has zero workflows, abort with a one-line notice and offer to switch to **generation** mode.

## Procedure

### Phase A0 — Inventory

```bash
find .github/workflows -type f \( -name '*.yml' -o -name '*.yaml' \) | sort
yq eval-all '. | "{{filename}}: " + (.name // "<unnamed>") + " | jobs=" + (.jobs | keys | length | tostring)' .github/workflows/*.y*ml
```

Output: list of workflow files, declared `name:`, job count. Persist the list as `$WORKFLOWS`.

If `actionlint` is installed, run it before any other check. A YAML that does not parse cannot be meaningfully audited:

```bash
actionlint .github/workflows/*.y*ml || echo "::error::actionlint failed — audit cannot proceed reliably"
```

### Phase A1 — Heuristic compliance

The five default heuristics from [USER_HEURISTICS.md](USER_HEURISTICS.md). For each, check whether the workflow implements it.

| # | Heuristic | Detection (grep / yq) | If missing |
| --- | --- | --- | --- |
| 1 | **Coverage gate** | `rg -n 'COVERAGE_MIN\|coverage.*fail\|--fail-under\|coverageThreshold' .github/workflows/` | **Medium** finding; suggest adding env-var gate |
| 2 | **N+1 detection** (test-side) | `rg -n 'queryCount\|captureQueries\|N\+1\|max.*queries' .github/workflows/` | **Low** finding; the gate is in test code, not workflow — surface as info |
| 3 | **Race detector** (Go) / `loom` (Rust) / async PBT (TS) | `rg -n -e '-race\b' -e 'loom\b' -e 'fast-check\|test:pbt' .github/workflows/` | **Medium** finding for Go (`-race` is cheap); **Info** for Rust/TS (PBT is opt-in) |
| 4 | **Memory leak detection** | `rg -n -e 'detectOpenHandles\|detectLeaks' -e 'goleak' -e 'miri' .github/workflows/` | **Medium** for TS without flags; **Info** for Go/Rust (project-side) |
| 5 | **Load testing** | `rg -nl 'k6\|artillery' .github/workflows/` | **Info** only — load testing is opt-in |

Record per-heuristic verdict: `present` / `missing` / `partial` (e.g., `-race` set but no coverage gate).

### Phase A2 — Security gate compliance

Walk the matrix from [SECURITY_GATES.md](SECURITY_GATES.md). The audit infers the **target** security level from what is present, then reports what the next level up would add.

```bash
# Detect each gate by signature
rg -nl 'github/codeql-action\|returntocorp/semgrep'      .github/workflows/   # SAST
rg -nl 'govulncheck\|cargo-audit\|cargo-deny\|pnpm audit\|bun pm audit\|npm audit\|osv-scanner' .github/workflows/   # SCA
rg -nl 'gitleaks-action'                                  .github/workflows/   # secret scan
rg -nl 'aquasecurity/trivy-action\|trivy '                .github/workflows/   # container
rg -nl 'anchore/sbom-action\|cyclonedx'                   .github/workflows/   # SBOM
rg -nl 'cosign\|slsa-framework'                           .github/workflows/   # provenance
test -f .github/dependabot.yml && echo "dependabot: present"
```

Inferred level rule:

- All five (SAST + SCA + secret + container + SBOM) → `strict`
- SAST + SCA + secret (container/SBOM optional) → `standard`
- None → `minimal`

If the user declared a target level different from the inferred one, **every missing gate from the target tier is a finding**:

| Missing gate at target level | Severity |
| --- | --- |
| SAST in `standard`/`strict` | High |
| SCA in `standard`/`strict` | High |
| Secret scan in `standard`/`strict` | Medium |
| Container scan in `strict` (Dockerfile present) | Medium |
| SBOM in `strict` | Medium |
| Dependabot config | Low |

### Phase A3 — Anti-pattern sweep

For each pattern below, the audit greps the workflows and the security finding is non-negotiable.

```bash
# 1. write-all permissions at workflow level
rg -nE 'permissions:\s*write-all' .github/workflows/

# 2. pull_request_target with PR-head checkout (RCE vector)
for f in .github/workflows/*.y*ml; do
  yq eval 'select(.on.pull_request_target != null)' "$f" | grep -qE 'ref:\s*\$\{\{\s*github\.event\.pull_request\.head' && echo "$f: pull_request_target + PR-head checkout"
done

# 3. Secrets passed at workflow-level env
yq eval '.env | keys[]' .github/workflows/*.y*ml 2>/dev/null | grep -i 'token\|secret\|key\|password'

# 4. Third-party actions without version pin
rg -hE 'uses: ' .github/workflows/*.y*ml \
  | grep -v 'actions/' \
  | grep -vE '@v[0-9]|@[a-f0-9]{40}|@[a-f0-9]{7,}' \
  | sort -u

# 5. continue-on-error or if: always() on security/test jobs
rg -nB2 'continue-on-error:\s*true\|if:\s*always\(\)' .github/workflows/

# 6. Inline `bash <(curl ...)` before any verification
rg -n 'bash\s*<\(curl\|sh\s*-c.*curl' .github/workflows/

# 7. Self-hosted runners without explicit allowlist label
yq eval '.jobs.[].runs-on' .github/workflows/*.y*ml | grep -i self-hosted
```

| Anti-pattern | Severity baseline |
| --- | --- |
| `permissions: write-all` workflow-level | **Critical** |
| `pull_request_target` + PR-head checkout | **Critical** |
| Secrets in workflow-level `env:` | **High** |
| Action `@<branch>` or no pin | **High** in `strict`, **Medium** otherwise |
| `continue-on-error: true` on security gate | **High** |
| `bash <(curl ...)` before allowlist | **High** |
| Self-hosted runner without label scoping | **Medium** |
| Hardcoded UTC timezones in cron without `workflow_dispatch` fallback | **Low** |

Anti-patterns are **never downgraded** by the audit — they are the floor. The user can dispute via override but the report records the dispute alongside the finding.

### Phase A4 — Action freshness

Stale actions are not by themselves vulnerable, but they are a maintenance signal.

```bash
# Extract every uses: occurrence with version
rg -hoE 'uses: [^ ]+@[^ ]+' .github/workflows/*.y*ml | sort -u
```

For each non-`actions/*` action, compare the pinned version against the latest published. The audit **does not call the network**; it surfaces the list and tells the user to run `gh release list -R <owner>/<repo>` per action. A version more than 2 majors behind is a **Low** finding.

### Phase A5 — Caching and concurrency hygiene

Cheap wins to flag as **Low** (not blockers but cost the user CI minutes):

```bash
# Cancel-in-progress on PR runs
yq eval '.concurrency // "missing"' .github/workflows/*.y*ml

# Cache configured for the language
rg -n 'cache: true\|Swatinem/rust-cache\|setup-node@v.*cache:\|setup-go@v.*cache:' .github/workflows/

# Job parallelism — fan-in via needs:
yq eval '.jobs | to_entries | .[] | "\(.key): needs=\(.value.needs // "none")"' .github/workflows/*.y*ml
```

| Hygiene issue | Severity |
| --- | --- |
| No `concurrency:` with `cancel-in-progress: true` | Low |
| No language cache configured | Low |
| Single sequential chain (no fan-out) | Low |
| Test job depends on lint job (should be parallel) | Low |

## Severity reference

| Severity | CVSS-like range | Example |
| --- | --- | --- |
| **Critical** | 9.0–10.0 | `pull_request_target` + PR-head checkout, `permissions: write-all` workflow-level, hardcoded `secrets.GITHUB_TOKEN` written to a public artifact |
| **High** | 7.0–8.9 | Secrets at workflow `env:`, action `@<branch>` pin, `continue-on-error` on security gate, missing SAST in declared `standard` level |
| **Medium** | 4.0–6.9 | Missing coverage gate, missing race detector, action with major-tag pin in declared `strict`, no Dockerfile container scan with Dockerfile present |
| **Low** | 1.0–3.9 | No `concurrency:` cancel-in-progress, no cache, action 2+ majors behind, no Dependabot config |
| **Info** | N/A | Heuristics that are project-side rather than workflow-side (N+1 assertion, leak detection in Go/Rust), opt-in heuristics absent (load testing) |

## Output format

Audit report (printed verbatim after Phase A5):

```text
ci-cd-generator: audit
  workflows:        N files at .github/workflows/
  inferred-lang:    <go | rust | typescript | polyglot | unknown>
  inferred-level:   <minimal | standard | strict>
  declared-level:   <user-stated; if absent, equals inferred>
  total-findings:   Critical X · High Y · Medium Z · Low W · Info V

## Findings

| ID | Severity | File:Line | Category | Title | Fix |
|----|----------|-----------|----------|-------|-----|
| CICD-001 | Critical | ci.yml:18 | anti-pattern | permissions: write-all at workflow level | Replace with `permissions: contents: read` and elevate per-job |
| CICD-002 | High     | ci.yml:42 | gate-missing | No SAST job — declared standard level requires it | Add CodeQL job (Go/JS-TS) or Semgrep (Rust); see references/SECURITY_GATES.md |
| CICD-003 | Medium   | ci.yml:60 | heuristic-missing | go test invocation lacks -race | Append `-race` to the test command; see references/USER_HEURISTICS.md#3-race-condition--property-based-testing-pbt |
| CICD-004 | Low      | ci.yml:5  | hygiene | No concurrency.cancel-in-progress | Add concurrency: { group: ci-${{ github.ref }}, cancel-in-progress: true } |

## Heuristic compliance

| # | Heuristic | Status |
|---|-----------|--------|
| 1 | Coverage gate           | missing |
| 2 | N+1 assertion (project) | n/a (project-side) |
| 3 | Race detector / PBT     | partial — -race missing |
| 4 | Memory leak detection   | missing |
| 5 | Load testing            | not enabled (info only) |

## Security gate compliance vs declared "standard"

| Gate | Required | Present | Verdict |
|------|----------|---------|---------|
| SAST            | yes | no  | finding CICD-002 |
| SCA             | yes | yes | ok |
| Secret scan     | yes | no  | finding |
| Container scan  | conditional (Dockerfile present) | no | finding |
| SBOM            | no  | no  | ok at this level |

## Suggested next steps
1. Apply Critical (CICD-001) immediately — it can leak credentials.
2. Triage High findings; CICD-002 unlocks declared "standard" compliance.
3. Run `/valarmindskills:ci-cd-generator --regenerate` if you want the skill to emit a fresh baseline alongside this audit for diffing.
```

## Apply mode (opt-in)

After the report, the user can request fixes per finding ID. Each fix is a unified diff that the audit emits to stdout — the user reviews and approves before any write. Default policy is identical to the generator's: never `git commit` automatically.

```bash
# user reply
"apply CICD-001 and CICD-004"
```

The audit then:

1. Generates the diff per finding.
2. Tags each diff with **SAFE** / **REVIEW** / **BREAKING** (same taxonomy as `@golang-api-security` Phase 6).
3. Applies via `Edit` tool, one file at a time.
4. Re-runs `actionlint` against the modified file. If it fails, `git restore` and surface the diff for manual handling.
5. Reports applied vs deferred.

Anti-pattern fixes (Critical / High) are **always SAFE** because the patterns themselves are unambiguous bugs. Heuristic fixes (Medium) are typically **REVIEW** because they may interact with project-side test changes the user has not made yet.

## Constraints

- **Never** edit a workflow without explicit user approval per finding ID
- **Never** apply fixes when `actionlint` fails on the source file — fix the syntax first, then re-audit
- **Never** treat absence of a heuristic in a project that has explicitly opted out via header comment as a finding
- **Never** trigger network calls (action freshness check is local — surface the list, do not fetch)
- **Must** run `actionlint` before Phase A1 if available; abort if it fails
- **Must** distinguish workflow-side vs project-side heuristics (N+1, leak detection in Go/Rust) — surface project-side ones as Info, not as Medium
- **Must** record the user's declared security level (or "inferred from presence") in the report so reruns can compare against the same baseline

## Caveats

- `yq` syntax shown is the Go `yq` (mikefarah/yq), not the Python `yq`. Substitute commands accordingly.
- The audit is **per-repo**, not per-organization. To audit at org level, run it in a loop over `gh repo list` and aggregate the reports.
- Pre-existing `.gitleaksignore` / `.audit-ignore` / `.trivyignore` files are respected — they are not findings, they are documented suppressions. Surface them in the report as "user-suppressed" annotations.
- Workflows under `.github/workflows/composite/` and reusable workflows (`workflow_call`) follow the same rules but the audit reports them under a separate "reusable" section because they are not entry points.
- Forked repos with workflows disabled in repo settings are out of scope — Actions never runs them. The audit notes the disabled state and stops.
