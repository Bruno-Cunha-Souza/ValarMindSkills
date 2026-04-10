# Rust — Clean Code Reference

> Language-specific companion for the [clean-code](../SKILL.md) skill. Covers Rust idioms, tooling, smells, and refactoring patterns.

## Tools

| Tool | Purpose | Install / Run |
|------|---------|---------------|
| `clippy` | Idiomatic Rust linter (500+ lints) | `rustup component add clippy` → `cargo clippy` |
| `rustfmt` | Canonical formatter | `rustup component add rustfmt` → `cargo fmt` |
| `cargo-audit` | Known vulnerability scanner | `cargo install cargo-audit` |
| `cargo-deny` | License + advisory + ban checks | `cargo install cargo-deny` |
| `cargo-udeps` | Find unused dependencies | `cargo install cargo-udeps` (nightly) |
| `cargo-machete` | Fast unused dependency detection | `cargo install cargo-machete` |
| `cargo-bloat` | Find what takes space in binary | `cargo install cargo-bloat` |

### Quick Audit

```bash
# Full clippy sweep (pedantic catches more smells)
cargo clippy -- -W clippy::pedantic -W clippy::nursery

# Format check (CI-friendly)
cargo fmt -- --check

# Find unused dependencies
cargo machete

# Check for known vulnerabilities
cargo audit

# Test with all features
cargo test --all-features

# Check test coverage (requires cargo-tarpaulin)
cargo tarpaulin --out Html
```

## Rust-Specific Smells

### 1. Unwrap Abuse

`unwrap()` and `expect()` in non-test code — panics in production.

```diff
# Bad — panics on None
- let user = db.find_user(id).unwrap();
- let config = std::fs::read_to_string("config.toml").unwrap();

# Good — propagate errors
+ let user = db.find_user(id)?;
+ let config = std::fs::read_to_string("config.toml")
+     .context("reading config.toml")?;
```

**Detect:** `rg '\.unwrap\(\)' --type rust | grep -v '_test\.rs' | grep -v '#\[test\]' | grep -v '#\[cfg(test)\]'`

### 2. Unnecessary Clone

Cloning to satisfy the borrow checker instead of restructuring ownership.

```diff
# Bad — cloning to avoid borrow issues
- let name = user.name.clone();
- process(&name);
- println!("{}", user.name);

# Good — borrow directly
+ process(&user.name);
+ println!("{}", user.name);

# Good — if you need ownership, take it
+ let name = user.name;  // move, don't clone
+ process(&name);
```

**Detect:** `rg '\.clone\(\)' --type rust --count-matches | sort -t: -k2 -rn | head -20`

### 3. Stringly Typed APIs

Using `String` where an enum or newtype would enforce correctness.

```diff
# Bad — any string accepted
- fn set_status(status: &str) {
-     match status {
-         "active" | "inactive" | "pending" => { /* ... */ }
-         _ => panic!("invalid status"),
-     }
- }

# Good — enum enforces valid states
+ #[derive(Debug, Clone, Copy)]
+ enum Status { Active, Inactive, Pending }
+
+ fn set_status(status: Status) {
+     match status {
+         Status::Active => { /* ... */ }
+         Status::Inactive => { /* ... */ }
+         Status::Pending => { /* ... */ }
+     }
+ }
```

**Detect:** `rg 'fn \w+\(.*: &?str\)' --type rust` then review if the string has a finite set of valid values.

### 4. Overuse of Arc<Mutex<T>>

Shared mutable state wrapped in `Arc<Mutex<>>` everywhere — sign of fighting the borrow checker instead of designing with ownership.

```diff
# Bad — shared mutable state scattered
- struct App {
-     users: Arc<Mutex<HashMap<String, User>>>,
-     config: Arc<Mutex<Config>>,
-     cache: Arc<Mutex<LruCache<String, Data>>>,
- }

# Good — message passing or actor model
+ enum Command {
+     GetUser(String, oneshot::Sender<Option<User>>),
+     UpdateConfig(Config),
+     Invalidate(String),
+ }
+ // Single owner processes commands sequentially
+ async fn run(mut rx: mpsc::Receiver<Command>, state: &mut AppState) {
+     while let Some(cmd) = rx.recv().await {
+         match cmd { /* ... */ }
+     }
+ }
```

**Detect:** `rg 'Arc<Mutex' --type rust --count-matches | sort -t: -k2 -rn | head -10`

### 5. Monolithic Error Enum

One giant error type for the entire crate — every function returns it.

```diff
# Bad — one error type for everything
- #[derive(thiserror::Error, Debug)]
- enum AppError {
-     #[error("db: {0}")] Db(#[from] sqlx::Error),
-     #[error("io: {0}")] Io(#[from] std::io::Error),
-     #[error("parse: {0}")] Parse(#[from] serde_json::Error),
-     #[error("auth: {0}")] Auth(String),
-     #[error("validation: {0}")] Validation(String),
-     // ... 20 more variants
- }

# Good — scoped errors per module
+ // db/error.rs
+ #[derive(thiserror::Error, Debug)]
+ enum DbError {
+     #[error("query failed: {0}")] Query(#[from] sqlx::Error),
+     #[error("not found: {entity} {id}")] NotFound { entity: &'static str, id: String },
+ }
+
+ // auth/error.rs
+ #[derive(thiserror::Error, Debug)]
+ enum AuthError {
+     #[error("invalid token")] InvalidToken,
+     #[error("expired")] Expired,
+ }
```

**Detect:** Count variants: `rg -U '#\[derive.*Error.*\][\s\S]*?enum \w+ \{' --type rust --multiline -A 50 | grep -c '#\[error'`

### 6. God Impl Block

A single `impl` block with dozens of methods — equivalent to a god class.

```diff
# Bad — 30 methods on one struct
- impl Server {
-     fn handle_login(&self) { /* ... */ }
-     fn handle_logout(&self) { /* ... */ }
-     fn send_email(&self) { /* ... */ }
-     fn generate_report(&self) { /* ... */ }
-     fn backup_database(&self) { /* ... */ }
-     // ... 25 more
- }

# Good — split by trait/responsibility
+ trait AuthHandler {
+     fn handle_login(&self);
+     fn handle_logout(&self);
+ }
+ trait Notifier {
+     fn send_email(&self, to: &str, body: &str);
+ }
+ impl AuthHandler for Server { /* ... */ }
+ impl Notifier for Server { /* ... */ }
```

**Detect:** `rg -U 'impl \w+[^{]*\{' --type rust --multiline -A 100 | awk '/^impl /{name=$2; count=0} /fn /{count++} /^\}/{if(count>10) print name": "count" methods"}'`

### 7. Boolean Parameter

Functions with `bool` arguments that change behavior — unclear at call site.

```diff
# Bad — what does `true` mean?
- fn send_notification(user: &User, urgent: bool, retry: bool) {

# Good — enum makes intent clear
+ enum Priority { Normal, Urgent }
+ enum RetryPolicy { None, WithRetry(u32) }
+ fn send_notification(user: &User, priority: Priority, retry: RetryPolicy) {
```

**Detect:** `rg 'fn \w+\(.*bool.*bool' --type rust`

## Rust Refactoring Patterns

### Newtype Pattern

Prevents mixing up primitive types that represent different things.

```diff
# Before: easy to swap user_id and order_id
- fn assign_order(user_id: String, order_id: String) -> Result<()> {
-     // oops: assign_order(order_id, user_id) compiles fine
- }

# After: compiler catches mistakes
+ struct UserId(String);
+ struct OrderId(String);
+
+ fn assign_order(user_id: UserId, order_id: OrderId) -> Result<()> {
+     // assign_order(order_id, user_id) → compile error
+ }
```

### Builder Pattern

Replaces constructors with many optional fields.

```diff
# Before: many optional parameters
- fn new(name: &str, email: &str, age: Option<u32>,
-     role: Option<Role>, team: Option<String>) -> User {

# After: builder
+ struct UserBuilder {
+     name: String,
+     email: String,
+     age: Option<u32>,
+     role: Option<Role>,
+     team: Option<String>,
+ }
+
+ impl UserBuilder {
+     fn new(name: impl Into<String>, email: impl Into<String>) -> Self {
+         Self { name: name.into(), email: email.into(),
+                age: None, role: None, team: None }
+     }
+     fn age(mut self, age: u32) -> Self { self.age = Some(age); self }
+     fn role(mut self, role: Role) -> Self { self.role = Some(role); self }
+     fn build(self) -> User { /* ... */ }
+ }
+
+ // Usage
+ let user = UserBuilder::new("Alice", "alice@example.com")
+     .age(30)
+     .role(Role::Admin)
+     .build();
```

### From/Into Conversions

Replaces manual conversion functions scattered across the codebase.

```diff
# Before: manual conversion in every call site
- fn create_response(user: &User) -> ApiResponse {
-     ApiResponse {
-         id: user.id.to_string(),
-         name: user.name.clone(),
-         email: user.email.clone(),
-     }
- }
- let resp = create_response(&user);

# After: From trait — idiomatic, composable
+ impl From<&User> for ApiResponse {
+     fn from(user: &User) -> Self {
+         Self {
+             id: user.id.to_string(),
+             name: user.name.clone(),
+             email: user.email.clone(),
+         }
+     }
+ }
+ let resp = ApiResponse::from(&user);
+ // or with Into:
+ let resp: ApiResponse = (&user).into();
```

### Error Context with anyhow/thiserror

Replaces repetitive `map_err` chains.

```diff
# Before: manual error mapping everywhere
- let file = std::fs::read_to_string(&path)
-     .map_err(|e| AppError::Io(format!("reading {}: {}", path, e)))?;
- let config: Config = toml::from_str(&file)
-     .map_err(|e| AppError::Parse(format!("parsing {}: {}", path, e)))?;

# After: anyhow context
+ use anyhow::Context;
+ let file = std::fs::read_to_string(&path)
+     .with_context(|| format!("reading {path}"))?;
+ let config: Config = toml::from_str(&file)
+     .with_context(|| format!("parsing {path}"))?;
```

## Rust Verification Commands

```bash
# Run tests
cargo test

# Run tests with output for debugging
cargo test -- --nocapture

# Full clippy audit
cargo clippy -- -W clippy::pedantic

# Check formatting
cargo fmt -- --check

# Check for unused dependencies
cargo machete

# Run with address sanitizer (nightly)
RUSTFLAGS="-Z sanitizer=address" cargo +nightly test

# Verify no unsafe code (if policy requires it)
rg 'unsafe' --type rust | grep -v '_test\.rs'
```
