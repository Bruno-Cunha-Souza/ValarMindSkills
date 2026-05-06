# Code Debugger — Rust Reference

> Reference companion for the [code-debugger](../SKILL.md) skill. Rust-specific debugging techniques, command snippets, and bug-class playbooks. Pairs with [code-review/references/RUST.md](../../code-review/references/RUST.md) (static smell catalogue).

## Tools

| Tool | Purpose | Install / Use |
| --- | --- | --- |
| `gdb` / `lldb` | Native step-debugger | system package |
| `rust-gdb` / `rust-lldb` | Rust-aware wrappers | bundled with `rustup` |
| `RUST_BACKTRACE=1` / `=full` | Backtrace on panic | env var |
| `cargo expand` | Expand macros for inspection | `cargo install cargo-expand` |
| `cargo asm` | Generated assembly per fn | `cargo install cargo-asm` |
| `tokio-console` | Live async runtime introspection | `cargo install tokio-console` |
| `miri` | Detect UB under MIR interpreter | `rustup +nightly component add miri` |
| `loom` | Permutation testing for concurrent code | crate `loom` |
| `cargo flamegraph` | CPU flame graph | `cargo install flamegraph` |
| `dhat-rs` | Heap profiling | crate `dhat` |
| `tracing` + `tracing-subscriber` | Structured logging | crates |

## Quick reproducer commands

```bash
# Backtrace on panic
RUST_BACKTRACE=1 cargo test -- --nocapture
RUST_BACKTRACE=full cargo test -- --nocapture

# Run a single test
cargo test --test <file> -- --exact <name> --nocapture

# Run many times (flake hunt)
cargo test --test <file> -- --exact <name> --test-threads=1
cargo nextest run --test <file> --partition count:200/1   # cargo-nextest

# Show release-vs-debug
cargo test --release        # bug only in release? optimisation issue
cargo test                  # bug only in debug? overflow check / debug_assert

# Sanitisers (nightly)
RUSTFLAGS="-Z sanitizer=thread"  cargo +nightly test --target=x86_64-unknown-linux-gnu
RUSTFLAGS="-Z sanitizer=address" cargo +nightly test --target=x86_64-unknown-linux-gnu

# Macro expansion
cargo expand --bin <bin>     # or: cargo expand <module>

# Async introspection
RUSTFLAGS="--cfg tokio_unstable" cargo build
TOKIO_CONSOLE_BIND=127.0.0.1:6669 ./target/debug/<bin>
tokio-console

# UB detection (slow but precise)
cargo +nightly miri test
```

## Bug-class playbooks

### Panic — explicit `panic!` / `unwrap` / `expect`

Backtrace pattern (with `RUST_BACKTRACE=1`):

```text
thread 'tokio-runtime-worker' panicked at 'called `Option::unwrap()` on a `None` value', src/handlers/order.rs:42:18
note: run with `RUST_BACKTRACE=1` environment variable to display a backtrace
```

Procedure:

1. Open `src/handlers/order.rs` at line 42. Read the `unwrap` site.
2. Determine why the `Option` was `None` (or `Result` was `Err`).
3. Replace with `?` propagation, an explicit `match`, or `ok_or(...)?` if the situation is recoverable.
4. If the panic is genuinely unreachable, leave a comment explaining why and consider `unreachable_unchecked!` only with a `// SAFETY:` comment.

### Panic — index / slice bounds

Pattern: `'index out of bounds: the len is N but the index is M'`.

Procedure:

1. Identify the indexed access. Replace with `.get(i)` returning `Option<&T>` and handle `None`.
2. Common roots: off-by-one; assumption about input length not validated.

### Borrow checker error

If the failure is at compile time (most borrow checker errors are), it is not in the scope of this skill — it is a build error. The skill addresses **runtime** borrow-related bugs:

- **Use after move** in `unsafe`. Almost always means a `*mut`/`*const` aliasing rule was violated.
- **Iterator invalidation** via `unsafe`. Same.
- **Re-entrant lock** with a `RefCell` or `parking_lot::Mutex` recursive lock disabled.

### Race detected (`-Z sanitizer=thread`)

Pattern: ThreadSanitizer prints the racing accesses and the involved threads.

Procedure:

1. Both stacks point to a shared cell. Identify it.
2. Verify the synchronisation primitive (`Mutex`, `RwLock`, atomic).
3. Common roots: shared `Cell<T>` / `RefCell<T>` across threads (impossible to compile in safe Rust — must be `unsafe`); incorrect `Ordering` on atomics; data hidden behind raw pointer aliasing.

### Deadlock — `std::sync::Mutex` across `.await`

Pattern: program hangs; `tokio-console` shows a task in `blocked` state on a mutex.

Procedure:

1. Identify the `lock()` call held across an `.await`. The `MutexGuard` is `Send` for `std::sync::Mutex`, but holding it across `.await` blocks the runtime worker.
2. Replace with `tokio::sync::Mutex` (whose guard yields properly).
3. Or restructure: drop the guard before the await.

### Async task leak / never-finishing future

Procedure:

1. `tokio-console` lists tasks; sort by age. Long-lived tasks expecting a wake that never comes.
2. Common roots: `tokio::spawn` with a future that awaits a channel nobody sends to; `select!` without `else` arm and all branches pending; a `JoinHandle` is dropped, detaching the task.

### Memory leak

Procedure:

1. `dhat::profiler` wraps the binary; produces a heap snapshot.
2. `dhat-viewer` shows allocation sites and live blocks.
3. Common roots: cycle of `Rc`/`Arc` (Rust does not collect cycles automatically — use `Weak`); unbounded queue / channel; long-lived `HashMap` without eviction.

### Slow test / slow service

Procedure:

1. `cargo flamegraph -p <pkg> -- <args>` produces an SVG.
2. Read leaves of the flame; widest = hottest.
3. Common roots: allocation in tight loops (`String::from`, `.to_vec()`), `clone()` per iteration, `Box::new` boxing, repeated regex compilation, panicking parse path on the hot path.

### Flaky test

Procedure:

1. `cargo nextest run --test <file> --partition count:200/1` — measure flake rate.
2. Check for:
   - `tokio::test` with shared state (e.g. global static `Mutex`).
   - `std::time::Instant` used as a key in a map (`Eq` is on duration, sometimes equal).
   - Order-dependent tests sharing a temp dir / DB.
3. `RUST_TEST_THREADS=1 cargo test` to surface order issues.

### UB suspected

Procedure:

1. Run `cargo +nightly miri test` on the affected test. Slow but exact.
2. ThreadSanitizer (`-Z sanitizer=thread`) for races; AddressSanitizer for memory issues.
3. Audit every `unsafe` block reachable from the failing path. Check `// SAFETY:` rationale matches reality.

### Wrong build mode

Pattern: bug appears in release but not debug, or vice versa.

Procedure:

1. **Bug in release only**: likely an optimisation surfacing UB (aliasing, uninit). Re-test with sanitisers.
2. **Bug in debug only**: likely an overflow check (`debug_assert!`, `i32` overflow panic). Use `wrapping_add` / `checked_add` if intended; else fix the overflow.
3. Confirm with `cargo build --release` and reproduce.

## gdb/lldb quick recipe

```bash
# Build with debug info (default in dev profile)
cargo build

# Attach
rust-lldb ./target/debug/<bin>           # macOS
rust-gdb  ./target/debug/<bin>           # Linux

# Inside lldb:
(lldb) breakpoint set --file order.rs --line 42
(lldb) run
(lldb) frame variable
(lldb) thread backtrace
(lldb) thread list

# For tests
rust-lldb $(cargo test --no-run --message-format=json | jq -r '.executable | select(.)' | head -1) -- --exact <test_name>
```

## tokio-console quick recipe

```bash
# Add to Cargo.toml dev-deps:
[dependencies]
console-subscriber = "0.4"

# In main:
console_subscriber::init();

# Build with the unstable cfg:
RUSTFLAGS="--cfg tokio_unstable" cargo run

# In another terminal:
tokio-console
# 't' tasks, 'r' resources; sort by 'p' polls, 'b' busy
```

## Common false leads

- **Compiler errors** from the borrow checker are not in scope — they are build errors. Fix them and continue.
- **`clippy` warnings** are leads, not causes. Useful as priors during Phase 2 hypothesis generation; do not treat as proof.
- **`unwrap` panics** point to a precondition mismatch, not always to the function that contains the `unwrap`. Read the call chain.
- **Async stacks** are notoriously short. Use `tracing::instrument` to thread a span and reconstruct the logical path.

## Hand-off triggers

- Refactor-class root cause → `@clean-code` with [RUST reference](../../clean-code/references/RUST.md).
- API security findings touched during the debug → `@code-security-review`.
- The fix touches `unsafe` → recommend `@code-review` and `cargo geiger` audit.
