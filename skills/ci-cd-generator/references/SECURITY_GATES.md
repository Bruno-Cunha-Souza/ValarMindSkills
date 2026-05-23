> Reference companion for the [ci-cd-generator](../SKILL.md) skill.

# Security Gates

The security jobs the generator wires into the pipeline based on the chosen security level (`minimal` / `standard` / `strict`). Each gate is a separate job so failures isolate cleanly.

## Cross-language tool matrix

| Concern | Go | Rust | TypeScript | Python | Action / command |
| --- | --- | --- | --- | --- | --- |
| **SAST** | CodeQL (`go`) | Semgrep (CodeQL has no Rust) | CodeQL (`javascript-typescript`) | CodeQL (`python`) + bandit | `github/codeql-action/init` + `analyze` or `returntocorp/semgrep@v1`; bandit via `pip install bandit` |
| **SCA (advisories)** | govulncheck + osv-scanner | cargo-audit + cargo-deny | pnpm/npm audit + osv-scanner | pip-audit + safety + osv-scanner | tool-specific |
| **Dependency PR bot** | dependabot (gomod) | dependabot (cargo) | dependabot (npm) or renovate | dependabot (pip) | `.github/dependabot.yml` |
| **Secret scan** | gitleaks | gitleaks | gitleaks | gitleaks | `gitleaks/gitleaks-action@v2` |
| **Container scan** | trivy fs + image | trivy fs + image | trivy fs + image | trivy fs + image | `aquasecurity/trivy-action@0.20.0` |
| **SBOM** | syft (`anchore/sbom-action`) | syft | syft | syft | `anchore/sbom-action@v0` |
| **License check** | `golang-jwt/license-detector` (rare) | cargo-deny licenses | license-checker (npm) | pip-licenses | per-language |
| **Provenance / signing** | cosign + SLSA | cosign + SLSA | cosign + SLSA | cosign + SLSA + sigstore (PEP 740 attestations) | `slsa-framework/slsa-github-generator` |

## Security level expansion

| Gate | `minimal` | `standard` | `strict` |
| --- | :---: | :---: | :---: |
| SAST | — | ✓ | ✓ |
| SCA | — | ✓ | ✓ |
| Dependabot config | ✓ | ✓ | ✓ |
| Secret scan | — | ✓ | ✓ |
| Container scan (if Dockerfile) | — | ✓ | ✓ |
| SBOM | — | — | ✓ |
| License check | — | — | ✓ |
| Cosign signing | — | — | optional |
| SLSA provenance | — | — | optional |
| Pin actions by SHA | — | major-version `@vN` | full `@<sha>` |

## SAST — CodeQL

For Go and TypeScript, CodeQL is the default. The job is added by the generator only when `security level = standard | strict`.

```yaml
codeql:
  needs: meta
  runs-on: ubuntu-latest
  permissions:
    actions: read
    contents: read
    security-events: write   # required to upload SARIF
  strategy:
    fail-fast: false
    matrix:
      language: ['go']        # or ['javascript-typescript']; multiple entries for monorepos
  steps:
    - uses: actions/checkout@v4
    - uses: github/codeql-action/init@v3
      with:
        languages: ${{ matrix.language }}
        queries: security-and-quality
    - uses: github/codeql-action/autobuild@v3
    - uses: github/codeql-action/analyze@v3
      with:
        category: '/language:${{ matrix.language }}'
```

CodeQL does not support Rust (as of 2026-04). For Rust projects, the generator substitutes Semgrep:

```yaml
semgrep:
  needs: meta
  runs-on: ubuntu-latest
  permissions:
    contents: read
    security-events: write
  steps:
    - uses: actions/checkout@v4
    - uses: returntocorp/semgrep-action@v1
      with:
        config: p/rust p/security-audit p/secrets
    - uses: github/codeql-action/upload-sarif@v3
      with:
        sarif_file: semgrep.sarif
```

## SCA — language-specific

The SCA job runs alongside the unit-test job; failures block merge.

| Language | Command | Failure threshold |
| --- | --- | --- |
| Go | `govulncheck ./...` + `osv-scanner --lockfile=go.sum` | any High/Critical |
| Rust | `cargo audit` + `cargo deny check advisories` | any High/Critical |
| TypeScript (pnpm) | `pnpm audit --prod --audit-level=high` | High+ in production deps |
| TypeScript (bun) | `bun pm audit` | non-zero exit |
| TypeScript (npm) | `npm audit --omit=dev --audit-level=high` | High+ in production deps |
| TypeScript (yarn) | `yarn npm audit --severity high` (Berry) or `yarn audit --level high` (classic) | High+ |
| Python (uv) | `uv pip compile --universal pyproject.toml -o /tmp/req.txt && pip-audit -r /tmp/req.txt --strict` + `osv-scanner --lockfile=uv.lock` | any High/Critical |
| Python (poetry) | `pip-audit --strict` + `osv-scanner --lockfile=poetry.lock` | any High/Critical |
| Python (pip) | `pip-audit --strict --disable-pip` + `safety check --full-report` | any High/Critical (pip-audit); safety informational |

Generator does **not** silence audit failures with `|| true`. If a known false-positive must be ignored, the user adds it to a `.audit-ignore` config — the workflow does not invent suppressions.

## Dependency PR bot — Dependabot

The generator emits `.github/dependabot.yml` covering every detected package ecosystem and `github-actions` itself.

```yaml
# .github/dependabot.yml
version: 2
updates:
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
    groups:
      gh-actions:
        patterns: ["*"]

  # one block per detected language
  - package-ecosystem: "gomod"            # only when language=go
    directory: "/"
    schedule: { interval: "weekly" }
    open-pull-requests-limit: 10

  - package-ecosystem: "cargo"            # only when language=rust
    directory: "/"
    schedule: { interval: "weekly" }

  - package-ecosystem: "npm"              # only when language=typescript
    directory: "/"
    schedule: { interval: "weekly" }
    versioning-strategy: increase-if-necessary
    groups:
      typescript-tooling:
        patterns: ["typescript", "@types/*", "tsx", "tsup"]
      test-runners:
        patterns: ["vitest", "jest", "@vitest/*", "@jest/*"]

  - package-ecosystem: "pip"              # only when language=python
    directory: "/"
    schedule: { interval: "weekly" }
    groups:
      python-tooling:
        patterns: ["ruff", "mypy", "pyright", "bandit", "pip-audit"]
      test-runners:
        patterns: ["pytest", "pytest-*", "hypothesis", "coverage"]
      framework:
        patterns: ["fastapi", "django*", "flask*", "starlette", "pydantic*", "sqlalchemy*"]
```

Dependabot supports `pip` for `requirements*.txt`, `pyproject.toml` (PEP 621), and `pipenv` files. For `uv.lock` and `poetry.lock` updates, Dependabot reads the `pyproject.toml` and bumps the spec; the lockfile is refreshed by `uv lock` / `poetry lock` on next install.

Renovate is offered as an alternative when the user has used it before; the generator does not force a choice.

## Secret scan — gitleaks

```yaml
secrets:
  needs: meta
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
      with:
        fetch-depth: 0   # required so gitleaks scans full history
    - uses: gitleaks/gitleaks-action@v2
      env:
        GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        GITLEAKS_LICENSE: ${{ secrets.GITLEAKS_LICENSE }}   # required only for orgs
```

The license var is only required for **organizations** (gitleaks-action policy). Personal repos do not need it. The generator surfaces this in the report.

## Container scan — trivy

Triggered when `Dockerfile` exists.

```yaml
trivy-fs:
  needs: meta
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - uses: aquasecurity/trivy-action@0.24.0
      with:
        scan-type: fs
        scan-ref: .
        severity: CRITICAL,HIGH
        exit-code: '1'
        ignore-unfixed: true
        format: sarif
        output: trivy-fs.sarif
    - if: always()
      uses: github/codeql-action/upload-sarif@v3
      with:
        sarif_file: trivy-fs.sarif

trivy-image:
  needs: build
  runs-on: ubuntu-latest
  if: success() && hashFiles('Dockerfile') != ''
  steps:
    - uses: actions/checkout@v4
    - uses: docker/setup-buildx-action@v3
    - name: build image (no push)
      run: docker build -t local/scan:${{ github.sha }} .
    - uses: aquasecurity/trivy-action@0.24.0
      with:
        image-ref: local/scan:${{ github.sha }}
        severity: CRITICAL,HIGH
        exit-code: '1'
        ignore-unfixed: true
```

## SBOM — syft (strict only)

```yaml
sbom:
  needs: build
  runs-on: ubuntu-latest
  permissions:
    contents: write   # only required when uploading the SBOM as a release asset
  steps:
    - uses: actions/checkout@v4
    - uses: anchore/sbom-action@v0
      with:
        format: cyclonedx-json
        output-file: sbom.cdx.json
        upload-artifact: true
        upload-artifact-retention: 90
```

For releases, the generator wires `anchore/sbom-action` into the release workflow as well, attaching the SBOM as a release asset.

## License check (strict only)

| Language | Tool |
| --- | --- |
| Go | `pmezard/licenses` (CLI) — manual review preferred |
| Rust | `cargo deny check licenses` (already in security job) |
| TypeScript | `license-checker --production --onlyAllow 'MIT;Apache-2.0;BSD-2-Clause;BSD-3-Clause;ISC'` |
| Python | `pip-licenses --format=csv --fail-on='GPL;AGPL;LGPL'` (or whichever set is disallowed) |

The strict pipeline fails if a non-allowlisted license appears in production dependencies.

## Cosign signing + SLSA (strict, optional)

For projects that publish artifacts (binaries, container images), the generator can wire `slsa-framework/slsa-github-generator` and `sigstore/cosign-installer` into the release workflow. This is **off by default** because:

- It requires `id-token: write` permission, which has supply-chain implications
- It adds verification steps consumers must understand
- Most projects do not need attestations until they reach a maturity threshold

When the user opts in, the generator adds:

```yaml
permissions:
  id-token: write
  contents: read

steps:
  - uses: sigstore/cosign-installer@v3
  - name: sign image (keyless via OIDC)
    run: cosign sign --yes ghcr.io/${{ github.repository }}:${{ github.sha }}
```

## Anti-patterns the generator refuses

| Pattern | Why it is refused |
| --- | --- |
| `pull_request_target` + `actions/checkout@v4` with `ref: refs/pull/*/merge` | Allows untrusted code to read repo secrets |
| `permissions: write-all` at workflow level | Broad credentials; minimum is `contents: read` |
| `env:` with secrets at workflow level | Leaks to all jobs; must be per-job or per-step |
| Untrusted action without version pin | Supply-chain risk; minimum `@vN`, strict mandates `@<sha>` |
| `actions/checkout@v4` + `bash <(curl …)` before allowlist check | Arbitrary remote execution before validation |
| `if: always()` swallowing security job failures | Defeats the gate |
| `continue-on-error: true` on a security gate | Same; only acceptable on opt-in heuristic jobs |

If the user explicitly asks for one of these (e.g., `pull_request_target` for fork PRs), the generator emits the workflow with a prominent header comment explaining the risk and the mitigations applied.

## Required secrets summary

The generation report lists every secret referenced by the emitted workflows. Common ones:

| Secret | When required |
| --- | --- |
| `GITHUB_TOKEN` | always — automatically provided by GitHub Actions |
| `GITLEAKS_LICENSE` | gitleaks-action on organization repos |
| `STAGING_URL`, `STAGING_TOKEN` | nightly load testing |
| `NPM_TOKEN`, `CARGO_REGISTRY_TOKEN` | publishing in release workflows |
| `CODECOV_TOKEN` | only if user opted in to codecov upload |

The generator never emits a workflow that references a secret it has not listed in the report.
