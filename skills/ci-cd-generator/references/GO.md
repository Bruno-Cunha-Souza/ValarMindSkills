> Reference companion for the [ci-cd-generator](../SKILL.md) skill.

# Go Pipeline Template

Generated when Phase 0 detects a `go.mod`. Defaults assume Go 1.22+ with toolchain pinning via `go-version-file: go.mod`.

## Tooling matrix

| Concern | Tool | Action |
| --- | --- | --- |
| Toolchain | `actions/setup-go@v5` | `go-version-file: go.mod`, `cache: true` |
| Format | `gofmt`, `goimports` | `gofmt -l . | tee /dev/stderr | wc -l` exits 0 |
| Vet | `go vet` | `go vet ./...` |
| Lint (deep) | `golangci-lint` | `golangci-lint run --timeout=5m` |
| Static analysis | `staticcheck` | `staticcheck ./...` |
| Test + coverage | `go test` | `go test -race -cover -covermode=atomic -coverprofile=coverage.out ./...` |
| Race detector | `-race` flag | always on |
| Goroutine leak | `uber-go/goleak` | dedicated `TestMain` |
| Vulnerability scan | `govulncheck` | `govulncheck ./...` |
| OSV cross-check | `osv-scanner` | `osv-scanner --lockfile=go.sum` |
| Module integrity | `go mod verify` | exits non-zero on tamper |
| Build | `go build` | `go build -trimpath -ldflags='-s -w' ./...` |
| Release | `goreleaser` | optional; gated on tag |

## Default `go-version` strategy

- Prefer `go-version-file: go.mod` over hardcoded versions — the module's `go` directive is the source of truth
- Add a matrix for libraries that need to support multiple toolchains: `go: ['1.22', '1.23', 'stable']`
- For application repositories, single version is sufficient

## Cache strategy

`actions/setup-go@v5` enables module + build cache when `cache: true`. No additional `actions/cache` step is needed for typical projects. Workspaces with multiple `go.sum` files require explicit `cache-dependency-path:`.

## Canonical workflow

```yaml
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
        with:
          go-version-file: go.mod
          cache: true
      - name: gofmt
        run: |
          out=$(gofmt -l .)
          if [ -n "$out" ]; then echo "::error::unformatted files:%0A$out"; exit 1; fi
      - name: go vet
        run: go vet ./...
      - name: staticcheck
        run: |
          go install honnef.co/go/tools/cmd/staticcheck@latest
          staticcheck ./...
      - name: golangci-lint
        uses: golangci/golangci-lint-action@v6
        with:
          version: v1.61

  test:
    needs: meta
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with:
          go-version-file: go.mod
          cache: true
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
        with:
          go-version-file: go.mod
          cache: true
      - name: property-based concurrent tests
        run: go test -tags=pbt -timeout=10m ./...
        continue-on-error: true   # remove once PBT tests exist

  security:
    needs: meta
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with:
          go-version-file: go.mod
          cache: true
      - name: govulncheck
        run: |
          go install golang.org/x/vuln/cmd/govulncheck@latest
          govulncheck ./...
      - name: go mod verify
        run: go mod verify
      - name: osv-scanner
        uses: google/osv-scanner-action@v1.9
        with:
          scan-args: --lockfile=go.sum

  build:
    needs: [lint, test, security]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with:
          go-version-file: go.mod
          cache: true
      - name: build
        run: go build -trimpath -ldflags='-s -w' ./...
```

Required secrets: none for the canonical workflow.

## Goroutine leak detection

`uber-go/goleak` plugs into `TestMain` and runs after each package's tests:

```go
// internal/pkgname/main_test.go
package pkgname

import (
    "testing"
    "go.uber.org/goleak"
)

func TestMain(m *testing.M) {
    goleak.VerifyTestMain(m)
}
```

No extra workflow step is needed — `go test ./...` runs `TestMain` automatically.

## N+1 detection template

Use a per-test query counter installed via the `gorm.io/gorm` `Logger` interface (or equivalent for `pgx`, `sqlx`, `database/sql`):

```go
// test_helpers.go
type queryCounter struct{ n int64 }

func (c *queryCounter) Add()        { atomic.AddInt64(&c.n, 1) }
func (c *queryCounter) Count() int  { return int(atomic.LoadInt64(&c.n)) }

func installQueryCounter(db *gorm.DB) *queryCounter {
    c := &queryCounter{}
    db.Callback().Query().Before("gorm:query").Register("count", func(_ *gorm.DB) { c.Add() })
    return c
}
```

Then inside the integration test, assert `counter.Count() <= 3` (or whatever bound the endpoint warrants). The pipeline picks up the assertion automatically — no separate job required.

## Release workflow (optional)

When the user opts in or `.goreleaser.yml` exists:

```yaml
# .github/workflows/release.yml
name: release
on:
  push:
    tags: ['v*']

permissions:
  contents: write
  packages: write

jobs:
  goreleaser:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - uses: actions/setup-go@v5
        with:
          go-version-file: go.mod
          cache: true
      - uses: goreleaser/goreleaser-action@v6
        with:
          args: release --clean
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

A minimal `.goreleaser.yml` (single binary, multi-OS, checksums + SBOM) is documented in the goreleaser docs; the generator does not invent one.

## Caveats

- `golangci-lint` may take 1–3 minutes on cold cache. Pin a `version:` to avoid surprises when upstream defaults change.
- `staticcheck` and `golangci-lint` overlap; the canonical workflow keeps both because each catches issues the other misses (`staticcheck` is faster and tighter; `golangci-lint` aggregates many linters).
- Avoid `go test -count=1 ./...` in normal CI — it disables the test cache and slows reruns. Use it only when reproducibility matters (race-PBT job above does).
- For monorepos, scope the `go test` invocations to changed modules using `dorny/paths-filter` or replace `./...` with explicit module paths.
- `goreleaser` requires a clean working tree; the workflow's `actions/checkout@v4` provides that, but local generation must not leave uncommitted files.
