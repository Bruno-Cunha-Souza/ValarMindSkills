# Example — Go API project

End-to-end walkthrough of `@ci-cd-generator` on a Go REST API using Gin, Postgres, and Docker. The user invokes the skill on a fresh repository.

## Input

User prompt:

> /valarmindskills:ci-cd-generator
>
> set up CI for this Go service — security level standard, opt in to load testing

Repository state:

```text
.
├── Dockerfile
├── README.md
├── cmd/api/main.go
├── go.mod
├── go.sum
├── internal/
│   ├── handlers/
│   ├── middleware/
│   └── store/
└── tests/integration/
```

## Phase 0 — Detection

The skill detects:

| Field | Value |
| --- | --- |
| `language` | `go` |
| `go-toolchain` | from `go.mod` → `1.23` |
| `runtime` | linux/amd64 |
| `dockerfile` | present (`./Dockerfile`) |
| `release` | no `.goreleaser.yml` — release workflow not seeded |

## Phase 1 — Preferences

Resolved from defaults + user overrides:

| Input | Value | Source |
| --- | --- | --- |
| Coverage threshold | 60 (warn 80) | default |
| Security level | `standard` | user-specified |
| Container scan | enabled | inferred from `Dockerfile` |
| SBOM | disabled | `standard` does not include |
| Dependabot | enabled | default |
| Load tests | enabled | user-specified |
| Heuristics opted out | none | default |

## Phase 2 — Heuristics applied

| # | Heuristic | Action |
| --- | --- | --- |
| 1 | Coverage gate | `COVERAGE_MIN=60`, `COVERAGE_TARGET=80` |
| 2 | N+1 detection | Integration tests already exist; assertion template documented in report |
| 3 | Race PBT | `go test -race` always on; dedicated `race-pbt` job with `continue-on-error` until project has `//go:build pbt` tests |
| 4 | Memory leak | `goleak.VerifyTestMain` snippet recommended in report |
| 5 | Load testing | Separate `nightly-load.yml` emitted |

## Phase 3 — Security gates wired

| Gate | Status |
| --- | --- |
| CodeQL (Go) | added |
| `govulncheck` | added |
| `osv-scanner` | added |
| `gitleaks` | added |
| `trivy-fs` + `trivy-image` | added (Dockerfile present) |
| SBOM | skipped (`standard`) |

## Phase 4 — Files emitted

### `.github/workflows/ci.yml`

```yaml
# ci-cd-generator v1
# trigger graph: push(main) | pull_request(main)
# security level: standard
# heuristics: coverage(60/80) n1 race leak load
# required secrets: GITLEAKS_LICENSE (only on org repos)

name: ci

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

permissions:
  contents: read

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

env:
  COVERAGE_MIN: "60"
  COVERAGE_TARGET: "80"

jobs:
  meta:
    name: actionlint
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: rhysd/actionlint@v1

  lint:
    needs: meta
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with: { go-version-file: go.mod, cache: true }
      - name: gofmt
        run: |
          out=$(gofmt -l .)
          if [ -n "$out" ]; then echo "::error::unformatted files:%0A$out"; exit 1; fi
      - run: go vet ./...
      - uses: golangci/golangci-lint-action@v6
        with: { version: v1.61 }

  test:
    needs: meta
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16
        env:
          POSTGRES_PASSWORD: ci
        ports: ['5432:5432']
        options: >-
          --health-cmd pg_isready --health-interval 5s --health-timeout 3s --health-retries 5
    env:
      DATABASE_URL: postgres://postgres:ci@localhost:5432/postgres?sslmode=disable
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with: { go-version-file: go.mod, cache: true }
      - name: tidy check
        run: |
          go mod tidy
          git diff --exit-code go.mod go.sum
      - name: test (race + cover)
        run: go test -race -cover -covermode=atomic -coverprofile=coverage.out -timeout=5m ./...
      - name: coverage gate
        run: |
          pct=$(go tool cover -func=coverage.out | awk '/^total:/ {gsub("%",""); print $3}')
          echo "coverage=$pct%"
          awk -v p="$pct" -v min="$COVERAGE_MIN" -v tgt="$COVERAGE_TARGET" 'BEGIN{
            if (p+0 < min+0) { print "::error::coverage "p"% < min "min"%"; exit 1 }
            if (p+0 < tgt+0) { print "::warning::coverage "p"% < target "tgt"%" }
          }'
      - uses: actions/upload-artifact@v4
        with:
          name: coverage-${{ github.sha }}
          path: coverage.out

  race-pbt:
    needs: meta
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with: { go-version-file: go.mod, cache: true }
      - name: property-based concurrent tests
        run: go test -tags=pbt -timeout=10m ./...
        continue-on-error: true   # remove once PBT tests exist

  security:
    needs: meta
    runs-on: ubuntu-latest
    permissions:
      contents: read
      security-events: write
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with: { go-version-file: go.mod, cache: true }
      - name: govulncheck
        run: |
          go install golang.org/x/vuln/cmd/govulncheck@latest
          govulncheck ./...
      - run: go mod verify
      - uses: google/osv-scanner-action@v1.9
        with: { scan-args: --lockfile=go.sum }

  codeql:
    needs: meta
    runs-on: ubuntu-latest
    permissions:
      contents: read
      security-events: write
    steps:
      - uses: actions/checkout@v4
      - uses: github/codeql-action/init@v3
        with: { languages: go, queries: security-and-quality }
      - uses: github/codeql-action/autobuild@v3
      - uses: github/codeql-action/analyze@v3

  secrets-scan:
    needs: meta
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - uses: gitleaks/gitleaks-action@v2
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

  trivy:
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

  build:
    needs: [lint, test, security, codeql, secrets-scan, trivy]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with: { go-version-file: go.mod, cache: true }
      - run: go build -trimpath -ldflags='-s -w' ./cmd/api
      - uses: docker/setup-buildx-action@v3
      - name: docker build (no push)
        run: docker build -t local/api:${{ github.sha }} .
```

### `.github/workflows/nightly-load.yml`

```yaml
# ci-cd-generator v1
# load testing — opt-in (off by default)
# required secrets: STAGING_URL, STAGING_TOKEN

name: nightly-load
on:
  schedule:
    - cron: "0 4 * * *"
  workflow_dispatch:

permissions:
  contents: read

jobs:
  k6:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: grafana/setup-k6-action@v1
      - name: smoke (1 VU, 30s)
        run: k6 run --vus 1 --duration 30s tests/load/smoke.js
        env:
          K6_BASE_URL: ${{ secrets.STAGING_URL }}
          K6_TOKEN: ${{ secrets.STAGING_TOKEN }}
      - name: ramp (50 VUs, 5min)
        run: k6 run --vus 50 --duration 5m tests/load/ramp.js
        env:
          K6_BASE_URL: ${{ secrets.STAGING_URL }}
          K6_TOKEN: ${{ secrets.STAGING_TOKEN }}
```

### `.github/dependabot.yml`

```yaml
version: 2
updates:
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule: { interval: "weekly" }
    groups:
      gh-actions:
        patterns: ["*"]

  - package-ecosystem: "gomod"
    directory: "/"
    schedule: { interval: "weekly" }
    open-pull-requests-limit: 10
```

## Phase 5 — Validation

```bash
$ actionlint .github/workflows/*.yml
$ yamllint -d relaxed .github/workflows/*.yml
$ grep -hoE '\$\{\{ secrets\.[A-Z_]+ \}\}' .github/workflows/*.yml | sort -u
${{ secrets.GITHUB_TOKEN }}
${{ secrets.K6_BASE_URL }}
${{ secrets.K6_TOKEN }}
${{ secrets.STAGING_TOKEN }}
${{ secrets.STAGING_URL }}
```

`actionlint` reports nothing → green. `yamllint` clean.

## Phase 6 — Report

```text
ci-cd-generator: generated
  language:      go
  runtime/pm:    go 1.23 + actions/setup-go@v5
  security:      standard
  workflows:     .github/workflows/ci.yml, .github/workflows/nightly-load.yml, .github/dependabot.yml
  jobs:          meta, lint, test, race-pbt, security, codeql, secrets-scan, trivy, build
  required-secrets:
    - STAGING_URL       (nightly-load only — staging endpoint)
    - STAGING_TOKEN     (nightly-load only — auth header)
    - GITLEAKS_LICENSE  (only required on org-owned repos)

Suggested branch protection (run after committing):
  gh api -X PUT repos/<owner>/<repo>/branches/main/protection \
    -F required_status_checks.strict=true \
    -F 'required_status_checks.contexts[]=lint' \
    -F 'required_status_checks.contexts[]=test' \
    -F 'required_status_checks.contexts[]=security' \
    -F 'required_status_checks.contexts[]=codeql' \
    -F 'required_status_checks.contexts[]=secrets-scan' \
    -F 'required_status_checks.contexts[]=trivy' \
    -F 'required_status_checks.contexts[]=build' \
    -F enforce_admins=true \
    -F required_pull_request_reviews.required_approving_review_count=1

Follow-up:
  - Add `goleak.VerifyTestMain(m)` to a `TestMain` in each package under `internal/`.
  - Author at least one `//go:build pbt` test under `internal/store/` so the `race-pbt` job stops being a no-op.
  - Configure `STAGING_URL` and `STAGING_TOKEN` in repo settings before the next 04:00 UTC nightly run.
  - Run `/valarmindskills:github-commit` to commit the new files.
```

## What the user does next

```bash
git checkout -b ci-bootstrap
git add .github/
# Review the diff one more time
gh repo set-default
gh secret set STAGING_URL --body "https://staging.example.com"
gh secret set STAGING_TOKEN --body "$(op read op://staging/api/token)"
# Commit
/valarmindskills:github-commit
git push origin ci-bootstrap
gh pr create --fill
```
