# Code Review — Rust Reference

> Reference companion for the [code-review](../SKILL.md) skill. Rust-specific patterns, sweeps, and example findings. Pairs with [clean-code/references/RUST.md](../../clean-code/references/RUST.md) for refactor patterns.

## Tools

| Tool | Purpose | Install / Run |
| --- | --- | --- |
| `cargo clippy` | Idiomatic / correctness / pedantic linter (500+ lints) | `rustup component add clippy` |
| `cargo fmt --check` | Formatter compliance | `rustup component add rustfmt` |
| `cargo audit` | RUSTSEC vulnerability DB | `cargo install cargo-audit` |
| `cargo deny` | Dependency policy (advisories, bans, licences, sources) | `cargo install cargo-deny` |
| `cargo machete` | Detects unused dependencies | `cargo install cargo-machete` |
| `cargo nextest` | Faster, parallel test runner | `cargo install cargo-nextest` |
| `cargo expand` | Expand macros for inspection | `cargo install cargo-expand` |
| `cargo geiger` | Counts `unsafe` usage transitively | `cargo install cargo-geiger` |
| `miri` | UB detector under MIR interpreter | `rustup +nightly component add miri` |

## Quick sweep

```bash
# Static toolchain sweep from the touched crate/workspace root
cargo fmt --check
cargo clippy --all-targets --all-features -- -D warnings -W clippy::pedantic
cargo audit
cargo deny check
cargo machete
cargo geiger        # for crates that allow unsafe

# Optional verification only
cargo test --all-features
```

## Findings catalog — 25 patterns to scan

Run patterns against changed Rust files through the [Diff Scope Contract](../SKILL.md#01-diff-scope-contract), then open matching files before filing a finding.

### 1. `.unwrap()` / `.expect()` in non-test code

```bash
rg -n '\.unwrap\(\)|\.expect\(' --type rust --glob '!tests/**' --glob '!**/*test*'
```

Severity floor: **High** in production handlers, **Medium** elsewhere. CWE-754. Replace with `?` propagation, `Result` mapping, or an explicit invariant comment.

```diff
- let user = self.store.find(id).unwrap();
+ let user = self.store
+     .find(id)
+     .map_err(|e| AppError::Database(e))?
+     .ok_or(AppError::NotFound)?;
```

### 2. `panic!` / `unreachable!` / `todo!` in production

```bash
rg -n '\b(panic\!|unreachable\!|todo\!|unimplemented\!)\(' --type rust --glob '!tests/**'
```

Severity floor: **High**. Same blast radius as Go panics. `unreachable!` is acceptable when the type system actually proves unreachability — verify it does.

### 3. `unsafe` block without a `// SAFETY:` comment

```bash
rg -n -B 1 'unsafe\s*\{' --type rust    # manually verify a preceding `// SAFETY:` invariant
```

Severity floor: **Critical**. The Rust convention is mandatory. Without the comment, the invariants are unverifiable. CWE-119/120/125/787.

### 4. `Box::leak` / `Rc::leak` / mem::forget

```bash
rg -n '(Box::leak|Rc::leak|Arc::leak|mem::forget)' --type rust
```

Severity floor: **Medium**. Allowed for static lifetimes, but each occurrence needs justification.

### 5. `Mutex` poisoning ignored

```bash
rg -n '\.lock\(\)\.unwrap\(\)' --type rust
```

Severity floor: **Medium**. A panicking thread leaves the mutex poisoned; `unwrap()` propagates the panic. Use `.lock().unwrap_or_else(|e| e.into_inner())` or handle explicitly.

### 6. `Arc<Mutex<HashMap>>` where `DashMap` would suffice

```bash
rg -n 'Arc<Mutex<HashMap' --type rust
rg -n 'Arc<RwLock<HashMap' --type rust
```

Severity floor: **Low** (performance). Promote to **Medium** if the lock is on a hot path with measurable contention.

### 7. `clone()` in a hot loop

```bash
rg -n -C 3 'for .* in |\.clone\(\)' --type rust
```

Severity floor: **Low**. Promote to **Medium** if the type is large (`String`, `Vec`, `HashMap`).

### 8. `String` where `&str` would do (function param)

```bash
rg -n 'fn \w+\([^)]*: String\)' --type rust
```

Severity floor: **Low**. Forces callers to allocate.

### 9. `Vec<u8>` round-trip via `String`

```bash
rg -n 'String::from_utf8.*\.as_bytes\(\)' --type rust
```

Severity floor: **Low**. Wasted allocation.

### 10. Stringly-typed API

```bash
rg -n 'fn \w+\(.*: &str.*: &str' --type rust    # multiple &str params
```

Severity floor: **Medium** when the params are different domain concepts (`username`, `email`). Use newtypes.

### 11. `Box<dyn Error>` everywhere

```bash
rg -n 'Result<.*Box<dyn (std::)?error::Error' --type rust
```

Severity floor: **Low**. Promote to **Medium** in library crates — leaks an unbounded error type to callers. Use `thiserror` or a domain enum.

### 12. `tokio::spawn` without join handle

```bash
rg -n 'tokio::spawn\(' --type rust
```

Severity floor: **Medium** when the future has side effects (DB writes, log emission). Without a handle, errors are lost.

### 13. `.await` inside `Mutex` lock guard

```bash
rg -n '\.lock\(\)\..*\.await' --type rust
```

Severity floor: **High**. Holding `std::sync::Mutex` across `await` is UB-adjacent (deadlock). Use `tokio::sync::Mutex` if the lock must span an await.

### 14. `block_on` in async context

```bash
rg -n 'block_on\(' --type rust
```

Severity floor: **High**. Deadlocks the runtime if called from inside a task.

### 15. `unwrap_or_default` masking errors

```bash
rg -n '\.unwrap_or_default\(\)' --type rust
```

Severity floor: **Low**. Promote to **Medium** when the default value is a meaningful state (e.g., empty `Vec` for "no permissions" — defaults to permissive).

### 16. `as` casts that can truncate

```bash
rg -n '\bas\s+(u8|u16|u32|i8|i16|i32|usize|isize)\b' --type rust
```

Severity floor: **Medium**. CWE-681. Use `try_into()` and handle the error.

### 17. `mem::transmute`

```bash
rg -n 'transmute' --type rust
```

Severity floor: **Critical**. Almost always wrong. Each occurrence requires `// SAFETY:` and a justification.

### 18. `serde` skipping fields without `#[serde(default)]`

Severity floor: **Low**. Deserialization may fail on schema drift; use explicit `default` to document intent.

### 19. `reqwest::Client` constructed per request

```bash
rg -n 'reqwest::Client::new\(\)' --type rust
```

Severity floor: **Medium**. Defeats connection pooling. Inject a single client.

### 20. SQL string concatenation with `format!`

```bash
rg -n 'format\!\(.*"(SELECT|INSERT|UPDATE|DELETE)' --type rust
```

Severity floor: **Critical**. CWE-89.

### 21. `serde_json::Value` in a public API

Severity floor: **Low**. Promote to **Medium** for new endpoints — callers receive a schemaless blob.

### 22. `match` without `_` in non-exhaustive enum

Severity floor: **Low**. New enum variants will fail to compile (good), but if the upstream is `non_exhaustive` it forces a `_` arm. Decide intentionally.

### 23. `assert!` instead of returning `Err`

```bash
rg -n 'assert\!\(' --type rust --glob '!tests/**' --glob '!**/*test*'
```

Severity floor: **High** in handlers — same blast radius as `panic!`.

### 24. `RUST_LOG` / `tracing` logging of secrets

```bash
rg -n 'tracing::(info|debug|warn|error)\!\(.*\b(password|token|secret|cookie|authorization)\b' --type rust
```

Severity floor: **High**.

### 25. `Cargo.toml` git deps without `tag` / `rev`

```bash
rg -n 'git\s*=' --glob Cargo.toml    # manually verify tag/rev pinning
```

Severity floor: **Medium**. CWE-829. Floating git dependency.

## Test smell sweep

```bash
# Tests with `unwrap` everywhere — fine, but check for actual assertions
rg -n 'assert' --type rust --glob '**/*test*'

# `#[ignore]` without a reason
rg -n -B 1 '#\[ignore\]' --type rust

# Tests using `thread::spawn` without joining
rg -n 'thread::spawn' --type rust --glob '**/*test*'
```

## Performance sweep

```bash
# Boxed futures inside tight loops
rg -n 'Box::pin\(' --type rust

# Allocations in hot loops
rg -n -A 5 'for .* in ' --type rust
rg -n '(String::new|Vec::new|to_string|to_vec)' --type rust

# Unbounded `read_to_string`
rg -n 'read_to_string' --type rust
```

## Hand-off triggers

- API security findings → `@code-security-review` (FastAPI/Gin/Fiber/Elysia patterns; Rust analogues by inference).
- Refactor / smell density → `@clean-code` with [RUST reference](../../clean-code/references/RUST.md).
- Runtime panic, deadlock, leak → `@code-debugger`.
