> Reference companion for the [code-optimization](../SKILL.md) skill.

# Rust Performance Reference

Targets: stable Rust 1.83+, edition 2024 where applicable. Frameworks: Axum 0.7+, Actix-web 4.x, Rocket 0.5+. Runtime: tokio 1.40+ (multi-thread vs current-thread).

## 1. Tooling matrix

| Concern | Tool | Invocation |
| --- | --- | --- |
| Micro-benchmark | `criterion` | `cargo bench` (with `[[bench]]` setup), `criterion-report/index.html` |
| CPU flamegraph | `cargo-flamegraph` | `cargo flamegraph --bin <binary>` (needs perf on Linux; dtrace on macOS) |
| Allocation profile | `heaptrack` (Linux), `bytehound` | `heaptrack ./target/release/<binary>` |
| Compile-time + binary | `cargo build --timings`, `cargo bloat` | `cargo bloat --release --crates -n 30` |
| Unused deps | `cargo-machete`, `cargo-udeps` | `cargo machete` (no nightly), `cargo +nightly udeps` |
| Lints (perf-aware) | `clippy` | `cargo clippy -- -D warnings -W clippy::pedantic -W clippy::perf` |
| Async profile | `tokio-console` | add `console_subscriber::init();` + `RUSTFLAGS="--cfg tokio_unstable"` |
| Compile speed | `cargo +nightly rustc -- -Z self-profile` | analyze with `summarize` crate |

## 2. Hot-path antipatterns

### 2.1 Cloning and ownership

| Anti-pattern | Fix |
| --- | --- |
| `.clone()` in hot loop | Pass `&T` references; or `Cow<'a, str>` for "owned when modified" |
| `String::from(s)` + `String::clone()` for concatenation | `String::with_capacity(n)` + `push_str`; or `format!` only outside loops |
| `Vec<T>::clone()` for read-only iteration | Iterate by reference: `for x in &v` |
| `Arc::clone(&arc)` per call inside a tight loop | Hoist the clone outside, share by reference (`&Arc<T>`) where lifetime allows |
| `Box<dyn Trait>` boxing per call | Generic over `T: Trait` (static dispatch) when type is known at compile time |

### 2.2 Async runtime tuning

`tokio::main` defaults:

| Flavor | When |
| --- | --- |
| `#[tokio::main]` (multi-thread) | I/O-bound services with many cores; default for web servers |
| `#[tokio::main(flavor = "current_thread")]` | Single-threaded apps, CLI tools, embedded; lower per-task overhead |
| Explicit `Runtime::new()` with `worker_threads(n)` | When CPU work dominates — pin `n` to physical cores |

Anti-patterns:

- **Blocking call in async context** — `std::fs::read` inside `tokio` handler. Fix: `tokio::fs::read` or `tokio::task::spawn_blocking` for one-off CPU work. Detection: `tokio-console` shows the task held for long, blocking other tasks.
- **`tokio::spawn` without bound** — same as Go errgroup-without-semaphore. Use `tokio::sync::Semaphore` to cap concurrency.
- **`Mutex` held across `.await`** — deadlock + priority inversion. `tokio::sync::Mutex` is async-aware but still blocks the task; redesign to release before await when possible.

### 2.3 Allocator switching

Default `std::alloc::System` is mostly fine, but for heavy allocators consider:

| Crate | When |
| --- | --- |
| `jemallocator` / `tikv-jemallocator` | Workloads with many small allocations; better fragmentation profile |
| `mimalloc` | Often fastest in benchmarks; mature, ~6 MB binary overhead |
| `snmalloc` | Multi-thread heavy, modern (Microsoft research) |

```rust
// Cargo.toml
[dependencies]
mimalloc = { version = "0.1", default-features = false }

// main.rs
#[global_allocator]
static GLOBAL: mimalloc::MiMalloc = mimalloc::MiMalloc;
```

**Verify with a real benchmark** — allocator wins are workload-specific. Adding `mimalloc` blindly is not a Quick Win without a `criterion` delta.

### 2.4 Concurrent collections

| Anti-pattern | Fix |
| --- | --- |
| `Arc<Mutex<HashMap<K, V>>>` for a hot map | `dashmap::DashMap<K, V>` — sharded lock-free reads |
| `Arc<RwLock<Vec<T>>>` for append-only growing data | `crossbeam::queue::SegQueue<T>` or `arc-swap` for atomic swaps |
| `Mutex` for atomic counter | `std::sync::atomic::AtomicU64` |
| `tokio::sync::Mutex` for short critical sections | `parking_lot::Mutex` — sync, but no async-await fairness needed |

### 2.5 Serialization

| Library | When |
| --- | --- |
| `serde_json` | default; fine for most APIs |
| `simd-json` | SIMD-accelerated parsing; same API |
| `rmp-serde` (MessagePack) | Inter-service RPC where JSON parsing dominates |
| `bincode` 2.x | Rust↔Rust binary protocol; fastest in benchmarks |
| `prost` (protobuf) | Schema-defined inter-service contracts |

### 2.6 Iterators vs explicit loops

Rust's iterators are zero-cost — but only when LLVM can elide bounds checks and inlining sees through closures. Pitfalls:

- `.collect::<Vec<_>>()` allocates; use `.collect::<Vec<_>>().into_boxed_slice()` to drop excess capacity, or iterate without collecting.
- `.collect::<Vec<_>>()` then `.into_iter()` round-trip — fuse the chain.
- `for x in v.iter().map(...).filter(...)` — usually optimal; do not "unroll" manually.

## 3. Framework-specific notes

### 3.1 Axum

- Handlers are async fn returning `impl IntoResponse`. Slow handlers block the worker pool — offload CPU work to `spawn_blocking`.
- State is `Arc`-shared via `State<T>` extractor — cheap.
- `Json<T>` deserialization uses `serde_json`; swap to `axum-extra::JsonRejection` + `simd-json` for hot endpoints.
- Routing is `matchit` (radix tree); per-route overhead negligible.

### 3.2 Actix-web

- Workers are pinned to OS threads (one runtime per worker). Avoid sharing `Arc<Mutex>` across workers; use per-worker state or external store.
- `web::Json<T>` payload size default 32 KB — raise with `JsonConfig::limit(...)` only after audit.
- `actix-web` is per-worker zero-cost; don't reach for it just for benchmarks — pick by ecosystem fit.

### 3.3 Rocket 0.5

- Async by default since 0.5. Migrating from 0.4 sync code is a perf win.
- Fairings (middleware) run sequentially; expensive fairings dominate request latency.

## 4. Profiling recipes

```bash
# Criterion benchmark (set up in benches/<name>.rs)
cargo bench --bench my_bench
# Reports in target/criterion/<bench>/report/index.html

# Flamegraph from a release binary
cargo install flamegraph
cargo flamegraph --release --bin server -- --some-arg
# Opens flamegraph.svg in browser

# Allocation profile (Linux)
sudo apt install heaptrack
heaptrack ./target/release/server
heaptrack_gui heaptrack.server.<PID>.gz

# Tokio runtime profile
RUSTFLAGS="--cfg tokio_unstable" cargo run --release
# Wire console_subscriber::init() in main; connect via `tokio-console`
```

## 5. Verification

- **Criterion delta** — `criterion` saves baselines (`cargo bench -- --save-baseline old`); compare with `cargo bench -- --baseline old`. Report delta as Quick Win if `> 5%` significant.
- **`cargo bloat`** to verify binary-size regressions on dep additions.
- **`cargo build --timings`** to spot compile-time regressions from heavy generics.

## 6. Anti-patterns specific to Rust perf findings

- "Use `unsafe` for speed" — almost always wrong. The safe abstraction is usually equal speed once optimized. Demand a benchmark before recommending `unsafe`.
- "Switch to nightly for SIMD" — stable SIMD is mostly arrived (`std::simd` stabilization in progress); avoid nightly recommendations unless the project is already on nightly.
- "Pin to specific crate version for perf" — most perf regressions come from major version bumps; minor/patch are usually safe. Verify with `cargo update -p <crate> --precise <ver>` + criterion.
- "Add `inline(always)`" — LLVM inlines small fns. Use `#[inline]` (hint) sparingly; never `inline(always)` without a measured win.

## 7. References (external)

- The Rust Performance Book: https://nnethercote.github.io/perf-book/
- tokio docs (cite via context7 `mcp__context7__resolve-library-id` for "tokio").
- `criterion` user guide.
- `dashmap` README for the sharded-map trade-offs.
