> Reference companion for the [ci-cd-generator](../SKILL.md) skill.

# Rust Pipeline Template

Generated when Phase 0 detects a `Cargo.toml`. Defaults assume a stable toolchain pinned via `rust-toolchain.toml` (preferred) or via the workflow.

## Tooling matrix

| Concern | Tool | Action |
| --- | --- | --- |
| Toolchain | `actions-rust-lang/setup-rust-toolchain@v1` | reads `rust-toolchain.toml` |
| Cache | `Swatinem/rust-cache@v2` | indexes by `Cargo.lock`, target dir, registry, git db |
| Format | `cargo fmt --check` | exits 1 if files would be reformatted |
| Lint | `cargo clippy --all-targets --all-features -- -D warnings` | warnings = errors |
| Build | `cargo check --all-targets --workspace` | type-check before tests |
| Test | `cargo nextest run --all-features` | parallel test runner; faster + better output |
| Coverage | `cargo llvm-cov` | LLVM source-based coverage; `--fail-under-lines 60` |
| Loom (concurrency) | `loom` cfg | optional job for state-machine tests |
| Audit (CVE) | `cargo audit` | `RustSec/audit-check@v1` |
| Deny (license + bans) | `cargo deny` | `EmbarkStudios/cargo-deny-action@v2` |
| Cross-compile | `cross` | optional release matrix |

## Toolchain pinning

Prefer a `rust-toolchain.toml` at the repo root over hardcoding the version in the workflow:

```toml
# rust-toolchain.toml
[toolchain]
channel = "1.82"
components = ["rustfmt", "clippy", "llvm-tools-preview"]
```

When this file exists, `actions-rust-lang/setup-rust-toolchain@v1` reads it and the workflow does not need a `toolchain:` input. The generator emits a comment in the YAML pointing at this convention if the file is missing.

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
  CARGO_TERM_COLOR: always
  RUSTFLAGS: "-D warnings"
  COVERAGE_MIN: "60"

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
      - uses: actions-rust-lang/setup-rust-toolchain@v1
        with:
          components: rustfmt, clippy
      - uses: Swatinem/rust-cache@v2
      - name: cargo fmt
        run: cargo fmt --all -- --check
      - name: cargo clippy
        run: cargo clippy --all-targets --all-features -- -D warnings

  test:
    needs: meta
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions-rust-lang/setup-rust-toolchain@v1
      - uses: Swatinem/rust-cache@v2
      - name: install nextest
        uses: taiki-e/install-action@nextest
      - name: cargo check
        run: cargo check --all-targets --all-features --workspace
      - name: nextest
        run: cargo nextest run --all-features --workspace
      - name: doc tests
        run: cargo test --doc --all-features --workspace

  coverage:
    needs: meta
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions-rust-lang/setup-rust-toolchain@v1
        with:
          components: llvm-tools-preview
      - uses: Swatinem/rust-cache@v2
      - name: install cargo-llvm-cov
        uses: taiki-e/install-action@cargo-llvm-cov
      - name: coverage gate
        run: |
          cargo llvm-cov --workspace --lcov --output-path lcov.info \
            --fail-under-lines "$COVERAGE_MIN"
      - uses: actions/upload-artifact@v4
        with:
          name: lcov-${{ github.sha }}
          path: lcov.info

  loom:
    needs: meta
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions-rust-lang/setup-rust-toolchain@v1
      - uses: Swatinem/rust-cache@v2
      - name: detect loom tests
        id: detect
        run: |
          if compgen -G "tests/loom_*" > /dev/null || [ -d tests/loom ]; then
            echo "exists=true" >> "$GITHUB_OUTPUT"
          else
            echo "exists=false" >> "$GITHUB_OUTPUT"
          fi
      - name: loom
        if: steps.detect.outputs.exists == 'true'
        env:
          RUSTFLAGS: "--cfg loom -D warnings"
          LOOM_MAX_PREEMPTIONS: "3"
        run: cargo test --release --test loom_*

  security:
    needs: meta
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: rustsec/audit-check@v2
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
      - uses: EmbarkStudios/cargo-deny-action@v2
        with:
          command: check bans licenses sources advisories

  build:
    needs: [lint, test, coverage, security]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions-rust-lang/setup-rust-toolchain@v1
      - uses: Swatinem/rust-cache@v2
      - name: release build
        run: cargo build --release --all-features --workspace
```

Required secrets: none for the canonical workflow.

## Property-Based Testing

Two distinct concerns in Rust:

1. **Pure-state PBT**: `proptest` for value-driven exploration. Lives inside the standard `test` job — no separate workflow needed.
2. **Concurrent / interleaving PBT**: `loom` explores all possible thread schedulings for code paths annotated with `cfg(loom)`. Slow; ships in the `loom` job above and only runs when `tests/loom/` exists.

Loom example:

```rust
// tests/loom_atomic.rs
#![cfg(loom)]
use loom::sync::atomic::{AtomicUsize, Ordering};
use loom::thread;

#[test]
fn no_lost_updates() {
    loom::model(|| {
        let counter = std::sync::Arc::new(AtomicUsize::new(0));
        let h: Vec<_> = (0..2).map(|_| {
            let c = counter.clone();
            thread::spawn(move || c.fetch_add(1, Ordering::SeqCst))
        }).collect();
        for t in h { t.join().unwrap(); }
        assert_eq!(counter.load(Ordering::SeqCst), 2);
    });
}
```

## N+1 detection template

For projects using `sqlx`, install a query counter via the connection's `log_settings` and assert in tests:

```rust
// tests/integration.rs
use sqlx::Executor;

#[sqlx::test]
async fn get_users_query_budget(pool: sqlx::PgPool) -> sqlx::Result<()> {
    let counter = std::sync::Arc::new(std::sync::atomic::AtomicUsize::new(0));
    let _guard = install_query_counter(&pool, counter.clone());

    let users = api::list_users(&pool).await?;
    assert!(!users.is_empty());

    let n = counter.load(std::sync::atomic::Ordering::SeqCst);
    assert!(n <= 3, "N+1 suspected: {n} queries (max 3)");
    Ok(())
}
```

`install_query_counter` is a project-side helper that taps into `tracing` events from sqlx; it is not part of the workflow.

## Memory leak / undefined behaviour

`miri` runs the test suite under an interpreter that catches undefined behaviour, including some leak classes. It is **slow** (often 10× normal tests) and runs only on a nightly toolchain.

Optional job (gated behind a label or schedule):

```yaml
miri:
  if: contains(github.event.pull_request.labels.*.name, 'run-miri') || github.event_name == 'schedule'
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - uses: actions-rust-lang/setup-rust-toolchain@v1
      with:
        toolchain: nightly
        components: miri, rust-src
    - uses: Swatinem/rust-cache@v2
    - run: cargo miri test --workspace
```

## Cross-compile + release

When the user opts in to a release workflow, the generator emits `release.yml` using `goreleaser`-style matrix via `cross`:

```yaml
# .github/workflows/release.yml
name: release
on:
  push:
    tags: ['v*']

permissions:
  contents: write

jobs:
  build:
    strategy:
      matrix:
        target:
          - x86_64-unknown-linux-gnu
          - aarch64-unknown-linux-gnu
          - x86_64-apple-darwin
          - aarch64-apple-darwin
        include:
          - target: x86_64-unknown-linux-gnu
            os: ubuntu-latest
          - target: aarch64-unknown-linux-gnu
            os: ubuntu-latest
            cross: true
          - target: x86_64-apple-darwin
            os: macos-15-intel
          - target: aarch64-apple-darwin
            os: macos-15
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - uses: actions-rust-lang/setup-rust-toolchain@v1
        with:
          target: ${{ matrix.target }}
      - uses: Swatinem/rust-cache@v2
      - if: matrix.cross
        run: cargo install cross
      - name: build
        run: |
          if [ "${{ matrix.cross }}" = "true" ]; then
            cross build --release --target ${{ matrix.target }}
          else
            cargo build --release --target ${{ matrix.target }}
          fi
      - uses: actions/upload-artifact@v4
        with:
          name: ${{ matrix.target }}
          path: target/${{ matrix.target }}/release/<binary-name>
```

The generator does not know the binary name — emit a `<binary-name>` placeholder and surface the substitution requirement in the report.

## Caveats

- `Swatinem/rust-cache@v2` is mandatory for any non-trivial workspace; cold builds without it can take 10–20 minutes.
- `cargo nextest` is faster and produces cleaner output than `cargo test`, but workspace test discovery differs slightly. Sanity-check with `cargo test` once before relying on nextest exclusively.
- `cargo audit` and `cargo deny` overlap (both check advisories); the canonical workflow keeps both because `cargo deny` adds license + sources + bans checks not in `cargo audit`.
- `loom` test runtime grows exponentially with thread count. Keep `loom` tests to 2–3 threads and use `LOOM_MAX_PREEMPTIONS=3` to bound the search.
- CodeQL does **not** support Rust as of this writing; the security job in [SECURITY_GATES.md](SECURITY_GATES.md) falls back to Semgrep for SAST coverage.
