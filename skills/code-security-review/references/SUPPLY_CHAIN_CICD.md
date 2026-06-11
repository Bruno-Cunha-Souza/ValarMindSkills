> Reference companion for the [code-security-review](../SKILL.md) skill.

# Software Supply Chain & CI/CD Security

Deep-dive companion for **OWASP Web Top 10 2025 A03 — Software Supply Chain Failures**, the category that broadened the old "Vulnerable & Outdated Components" to cover the whole path from a dependency declaration to a deployed artifact: third-party packages, the build pipeline, CI workflows, registries, and the credentials that tie them together. Pairs with `scripts/07-supply-chain.sh` (dependency + lockfile audit), `scripts/09-cicd-workflows.sh` (GitHub Actions audit), and `scripts/10-secrets-scan.sh` (secrets).

## When to load

Load this reference when Phase 0 detects any of:

- Dependency manifests / lockfiles: `package.json`, `requirements.txt`, `pyproject.toml`, `go.mod`, `Cargo.toml`, `*.lock`.
- A CI surface: `.github/workflows/*.yml`, `.gitlab-ci.yml`, `Jenkinsfile`, `*.tekton.yaml`.
- Container build inputs: `Dockerfile`, `docker-compose.yml`, Helm charts.

## A03:2025 scope

A03 spans four blast radii. Each maps to distinct controls and to a distinct CWE family:

| Surface | What goes wrong | CWE |
| --- | --- | --- |
| Dependencies | Vulnerable, yanked, typosquatted, or backdoored package pulled into the build | CWE-1395, CWE-1104 |
| Build / CI | Pipeline executes attacker-controlled code or leaks credentials | CWE-284, CWE-532 |
| Artifacts / integrity | Unsigned or tampered build output ships to production | CWE-494, CWE-345 |
| Provenance | No way to verify what source produced a given artifact | CWE-829 |

A03 overlaps **A08:2025 Software or Data Integrity Failures** (integrity of the artifact) and **A02:2025 Security Misconfiguration** (over-permissive pipeline defaults). When a finding touches both, tag the dominant one and cross-reference.

## Dependency controls

### Pin and lock per ecosystem

Unpinned versions resolve to "whatever is current at install time" — the exact window every recent registry attack exploited. Pin exact versions **and** lock the full transitive graph with hashes:

| Ecosystem | Pin + lock | CI enforcement |
| --- | --- | --- |
| Python (pip) | `pkg==1.2.3`, `--require-hashes`, `pip-compile` | `pip install --require-hashes -r requirements.txt` |
| Node (npm) | `package-lock.json` committed | `npm ci --ignore-scripts` |
| Bun | `bun.lock` committed | `bun install --frozen-lockfile` |
| Go | `go.mod` + `go.sum` | `go mod verify`, `GOFLAGS=-mod=readonly` |
| Rust | `Cargo.lock` (binaries) | `cargo build --locked`, `cargo-deny` |

`--ignore-scripts` matters: most npm-ecosystem compromises execute their payload from a package **install hook**, before any of your code runs. Disable lifecycle scripts by default and allowlist the few packages that genuinely need them (`trustedDependencies` in Bun, `--foreground-scripts` review in npm).

### Typosquatting and slopsquatting

Two classes of name-confusion attack:

- **Typosquatting** — a malicious package named one keystroke off a popular one (`reqeusts`, `loadsh`).
- **Slopsquatting** — an attacker registers a package name that LLMs *hallucinate*. AI coding assistants invent plausible-but-nonexistent package names with measurable frequency; attackers pre-register the common hallucinations and wait for an `npm install`.

Control: before adding any dependency — especially one suggested by an AI tool — verify it exists on the official registry, check its age and download count, and confirm the publisher. Treat a brand-new, low-download package with the name you "expected to exist" as suspicious until proven otherwise. See `../AI_SECURITY.md` for the AI-generated-code review checklist.

### SBOM

Generate a Software Bill of Materials (CycloneDX or SPDX) as a build artifact so you can answer "are we affected by CVE-X?" in minutes, not days. `osv-scanner` and `trivy` both consume and produce SBOMs; `syft` generates them from source or images.

## GitHub Actions hardening

CI workflows are code with credentials. The dominant 2025 attack pattern shifted from breaching production to hijacking the pipeline that deploys to it.

- **Pin actions by full 40-hex commit SHA, never by tag.** Tags are mutable; an attacker who rewrites `v1` to point at a malicious commit compromises every workflow that trusts the tag. `uses: actions/checkout@<40-hex-sha>  # v4.2.2`.
- **`pull_request_target` + checkout of the PR head = "pwn request".** That trigger runs with repository write permissions and secrets, and checking out untrusted PR code under it hands those to an attacker. Use `pull_request` for untrusted contributions; reserve `pull_request_target` for code that never executes the PR's contents.
- **Least-privilege `permissions`.** Set a top-level `permissions: contents: read` and escalate per-job only where needed. A workflow with no `permissions:` block inherits broad defaults.
- **Never interpolate `${{ secrets.* }}` (or `${{ github.event.* }}`) directly into a `run:` shell string.** Expression interpolation is textual substitution → shell injection. Pass secrets through `env:` and reference them as shell variables (`$MY_SECRET`).
- **`persist-credentials: false`** on checkout unless a later step needs the token.
- **Prefer OIDC over long-lived cloud keys.** Federated short-lived tokens remove the standing credential an attacker would exfiltrate.
- **Audit with `zizmor`** (Trail of Bits) — purpose-built static analyzer for these exact misconfigurations. `scripts/09-cicd-workflows.sh` runs it when present and falls back to grep heuristics otherwise.

## Secrets hygiene

- **`gitleaks`** — fast pattern scan over the working tree and history; good pre-commit hook.
- **`trufflehog`** — scans and then *verifies* whether a detected credential is still live, sharply cutting false positives. Use it for triage of real exposure.
- Scan **history**, not just HEAD — a secret committed and "removed" is still in the pack.
- On a confirmed leak: rotate first, then purge history. Rotation is the control; history rewriting is cleanup.
- Keep secrets out of the repo entirely: `.env` in `.gitignore`, secrets in the CI secret store or a vault, never in committed config.

## Tooling matrix

| Job | Tool | Canonical command |
| --- | --- | --- |
| Cross-stack vuln scan | `osv-scanner` (Google/OSV) | `osv-scanner --recursive .` |
| Python deps | `pip-audit` (PyPA) | `pip-audit --require-hashes` |
| Go stdlib + deps | `govulncheck` | `govulncheck ./...` |
| Rust deps | `cargo-audit` / `cargo-deny` | `cargo audit` · `cargo deny check` |
| Node deps | `npm audit` / `bun audit` | `npm audit --audit-level=high` |
| Containers | `trivy` | `trivy image <ref>` · `trivy fs .` |
| GitHub Actions | `zizmor` | `zizmor .github/workflows` |
| Secrets | `gitleaks` / `trufflehog` | `gitleaks detect` · `trufflehog filesystem .` |
| SAST | `semgrep` / `opengrep` | `semgrep --config auto` |

Note on SAST: Semgrep changed its licensing and registry terms; **opengrep** is the LGPL community fork (created January 2025) and is rules-compatible — existing Semgrep configs run unchanged. Pick either; both consume the same ruleset format.

## Incident case studies (lesson → control)

Each of these is well-attested. The point is not the headline but the control it validates:

| Incident | Mechanism | Control it proves |
| --- | --- | --- |
| **xz-utils backdoor** (2024) | Long-game social engineering of a maintainer; backdoor in release tarballs but not git | Build from verifiable source; reproducible builds; scrutinize maintainer-trust changes |
| **tj-actions/changed-files** (Mar 2025) | Mutable tags rewritten to a malicious commit; dumped CI runner secrets to logs (~23k repos) | Pin actions by 40-hex SHA, not tag |
| **chalk / debug npm compromise** (Sep 2025) | Maintainer phished; malicious versions of packages with ~2.6B weekly downloads | Disable install scripts; version cooldown before adopting fresh releases; lockfile + hashes |
| **Shai-Hulud worm** (Sep + Nov 2025) | Self-replicating malware spreading via stolen npm tokens, auto-republishing | Scoped/short-lived tokens; provenance (npm attestations); MFA on publish |
| **Slopsquatting** | Attackers pre-register package names that LLMs hallucinate | Verify package existence/age/publisher before adding AI-suggested deps |

## Control → script map

| Control | Script | Finding IDs |
| --- | --- | --- |
| Vulnerable dependencies | `07-supply-chain.sh` | `SUPPLY-{PY,GO,BUN,NPM,RS,OSV}-001` |
| Lockfile pinning | `07-supply-chain.sh` | `SUPPLY-LOCK-001/002/003` |
| Unpinned action tags | `09-cicd-workflows.sh` | `CICD-001` |
| Pwn-request trigger | `09-cicd-workflows.sh` | `CICD-002` |
| Secrets in `run:` | `09-cicd-workflows.sh` | `CICD-003` |
| Missing `permissions:` | `09-cicd-workflows.sh` | `CICD-004` |
| Self-hosted runner | `09-cicd-workflows.sh` | `CICD-005` |
| Committed secrets | `10-secrets-scan.sh` | `SECRETS-{GL,TH,RX}-001` |

## Sibling references

- [`DESIGN_CONTROLS.md`](DESIGN_CONTROLS.md) — language-agnostic design controls (the supply-chain quick commands live there)
- [`AI_SECURITY.md`](AI_SECURITY.md) — LLM / agentic / MCP coverage and AI-generated-code review
- [`TESTING_PHASES.md`](TESTING_PHASES.md) — active testing flow + static phases 8–10
- [`REPORT_TEMPLATE.md`](REPORT_TEMPLATE.md) — finding documentation template
