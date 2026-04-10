---
name: clean-code
description: "Use when writing, reviewing, or refactoring code to ensure clean code principles — naming, functions, DRY, code smells, safe refactoring."
source: ValarMindSkills
---

# Clean Code Lifecycle

> "Code is clean if it can be read, and enhanced by a developer other than its original author." — Grady Booch

## When to Use

- **Writing new code**: To ensure high quality from the start.
- **Reviewing Pull Requests**: To provide constructive, principle-based feedback.
- **Refactoring legacy code**: To identify and remove code smells.
- **Improving team standards**: To align on industry-standard best practices.

## Prerequisites

| Tool | Purpose | Install |
|------|---------|---------|
| `jscpd` | Multi-language clone detection | `npm install -g jscpd` |
| `pmd` | Java/multi-language CPD | [pmd.github.io](https://pmd.github.io/) |
| `fd` | Fast file finder | `brew install fd` / `apt install fd-find` |
| `rg` | Fast content search | `brew install ripgrep` / `apt install ripgrep` |
| `golangci-lint` | Go meta-linter (50+ linters) | `go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest` |
| `clippy` | Rust idiomatic linter (500+ lints) | `rustup component add clippy` |
| `biome` | Fast TS/JS linter + formatter | `bun install -D @biomejs/biome` / `npm install -D @biomejs/biome` |
| `knip` | Find unused TS exports/deps/files | `bunx knip` / `npx knip` |
| Project linter | Language-specific checks | Check project config (`.eslintrc`, `.golangci.yml`, `biome.json`, `pyproject.toml`) |

## Phase 0 — Project Context Discovery

Before applying any clean code principle, **understand the project you're working in.** Refactoring or deduplicating without context leads to wrong abstractions, broken conventions, and wasted effort.

### Discovery Commands

```bash
# 1. Find project documentation — README, ADRs, contributing guides
fd -t f -i '(README|CONTRIBUTING|ADR|ARCHITECTURE|CONVENTIONS|STYLE_GUIDE)' .

# 2. Find configuration files that reveal conventions and tooling
fd -t f '(\.eslintrc|\.prettierrc|\.editorconfig|\.golangci|pyproject\.toml|biome\.json)' .

# 3. Check for a CLAUDE.md or similar AI-agent instructions
fd -t f 'CLAUDE.md' .

# 4. Read the project's commit style to match refactoring commits
git log --oneline -20

# 5. Check for existing shared utilities — avoid creating duplicates
fd -t f -i '(utils|helpers|shared|common|lib)' src/
```

### Key Questions

| Question | Why it matters | Where to find it |
|----------|---------------|------------------|
| Does the project have a style guide or coding conventions? | Your refactoring must follow existing patterns, not introduce new ones | `CONTRIBUTING.md`, linter configs, ADRs |
| Are there existing shared utility modules? | Before extracting a helper, check if one already exists | `utils/`, `shared/`, `lib/`, `common/` dirs |
| What's the test strategy (unit, integration, e2e)? | Determines how you verify refactoring safety | `README.md`, CI config, test directory structure |
| Are there architectural boundaries (modules, packages, bounded contexts)? | Deduplicating across boundaries may violate the architecture intentionally | `ARCHITECTURE.md`, ADRs, module/package structure |
| Is there a dependency injection or service pattern in use? | Extracting code the wrong way can break DI wiring | Entry points, main files, DI containers |

### Decision Rules

- **If a style guide exists** → follow it, even if it contradicts Clean Code principles. Project consistency wins over theoretical purity.
- **If shared utils already exist** → add to them instead of creating parallel helpers.
- **If ADRs document a decision to keep duplication** → respect it. Not all duplication is accidental.
- **If no tests exist** → write characterization tests before any refactoring (see Phase 3).
- **If no documentation exists** → read code structure, git history, and CI config to infer conventions.

> **Rule: context before cleanup.** A "clean" refactoring that ignores project conventions creates more mess than the duplication it removed.

## Phase 1 — Code Quality Audit

Scan the codebase for code smells. Each smell includes a description and detection method.

| # | Smell | Description | Detection |
|---|-------|-------------|-----------|
| 1 | **Rigidity** | One change forces a cascade of dependent changes | Count how many files a single-line change touches |
| 2 | **Fragility** | Breaks in many places when you make a change | Look for high coupling with no clear interface boundary |
| 3 | **Immobility** | Useful parts are entangled with unneeded details | Functions that import half the project to do a simple task |
| 4 | **Viscosity** | Easier to hack than to follow the design | Devs keep bypassing an abstraction — it's too cumbersome |
| 5 | **Needless Complexity** | Premature abstraction or speculative generality | Unused interfaces, empty abstract methods, config nobody changes |
| 6 | **Needless Repetition** | Same logic in multiple places | `npx jscpd ./src` or review similar function bodies |
| 7 | **Feature Envy** | A method accesses another object's data more than its own | Chains: `order.getCustomer().getAddress().getCity()` |
| 8 | **Shotgun Surgery** | A single change requires edits across many files | `git log --name-only` — same files always change together |
| 9 | **Divergent Change** | One class changed for many different reasons | File with commits from unrelated features |

### Principle Checks

For each file under review, verify against the core principles. See [references/PRINCIPLES.md](references/PRINCIPLES.md) for full details.

- **Names**: Intention-revealing, searchable, pronounceable?
- **Functions**: Small (<30 lines), do one thing, ≤2 arguments?
- **Comments**: Can any comment be eliminated by making the code clearer?
- **Formatting**: Newspaper metaphor — high-level at top, details at bottom?
- **Objects**: Law of Demeter respected? No `a.getB().getC().doSomething()`?
- **Error Handling**: Exceptions over return codes? No null returns/passes?
- **Tests**: F.I.R.S.T. principles followed?
- **Classes**: Single Responsibility Principle?

### Language-Specific Checks

For language-specific smells, idioms, and detection commands:

- **Go**: See [references/GOLANG.md](references/GOLANG.md) — stuttering names, empty interface abuse, `init()` side effects, naked returns, oversized interfaces, functional options
- **Rust**: See [references/RUST.md](references/RUST.md) — `unwrap()` abuse, unnecessary `clone()`, stringly typed APIs, `Arc<Mutex<>>` overuse, monolithic error enums, boolean parameters
- **TypeScript**: See [references/TYPESCRIPT.md](references/TYPESCRIPT.md) — `any` abuse, excessive type assertions, enum vs union, barrel file bloat, god interfaces, class overuse
- **Bun**: See [references/BUN.md](references/BUN.md) — Node.js APIs vs Bun natives, unnecessary polyfills, `dotenv`/`jest`/`express` replacements, `Bun.file`/`Bun.serve`/`Bun.password`

## Phase 2 — Duplication Detection

### Types of Duplication

| Type | Description | How to Detect |
|------|-------------|---------------|
| **Exact clones** | Identical blocks copied verbatim | `npx jscpd ./src`, PMD CPD, `flay` (Ruby), `dupfinder` (C#) |
| **Structural clones** | Same structure, different variable names | Review functions with similar signatures and bodies |
| **Semantic duplicates** | Same logic, different implementation | Functions that accomplish the same task under different names |
| **Data duplication** | Constants, configs, or URLs repeated across files | `rg -c '"[^"]{10,}"' --type ts \| sort -t: -k2 -rn \| head -20` |

### Detection Commands

```bash
# Multi-language clone detection
npx jscpd --min-lines 5 --min-tokens 50 ./src

# Find functions with similar names (Go)
rg 'func (get|fetch|retrieve|load)(User|Account|Profile)' --type go

# Find functions with similar names (Rust)
rg 'fn (get|fetch|retrieve|load)_(user|account|profile)' --type rust

# Find functions with similar names (TypeScript)
rg '(function|const) (get|fetch|retrieve|load)(User|Account|Profile)' --type ts

# Find similar exported functions (TypeScript)
rg 'export (async )?function (get|fetch|retrieve|load)' --type ts

# Detect repeated magic strings (top 20)
rg -c '"[^"]{10,}"' --type ts | sort -t: -k2 -rn | head -20

# Detect repeated string literals (Rust)
rg -c '"[^"]{10,}"' --type rust | sort -t: -k2 -rn | head -20

# Find Bun-replaceable npm packages
rg '"(node-fetch|cross-fetch|dotenv|better-sqlite3|glob|fast-glob|bcrypt|jest|ts-jest|nodemon)"' package.json

# Detect repeated URLs and endpoints
rg '(http://|https://)[a-zA-Z0-9./-]+' -o | sort | uniq -c | sort -rn | head -10

# Detect repeated struct/object literals (Go)
rg -U 'gin\.H\{"error"' --type go | sort | uniq -c | sort -rn

# Detect repeated error patterns (Rust)
rg '\.map_err\(|\.with_context\(' --type rust --count-matches | sort -t: -k2 -rn | head -10
```

### When NOT to Deduplicate

Not all repetition is bad. Before extracting, ask:

- **Accidental vs real duplication**: Two blocks look the same *today* but represent different domain concepts that will evolve independently. Coupling them creates fragility.
- **Rule of Three**: Tolerate 2 copies. Extract on the 3rd. The pattern needs to prove itself.
- **Different rate of change**: If similar pieces belong to different bounded contexts or teams, keeping them separate avoids shotgun surgery across team boundaries.
- **Premature abstraction**: If the "shared" function needs 4 parameters and 2 boolean flags to handle all cases, the cure is worse than the disease.

## Phase 3 — Safe Refactoring

Apply refactoring patterns to resolve the issues found in Phases 1 and 2. For concrete before/after diffs, see [references/PATTERNS.md](references/PATTERNS.md).

### Available Patterns

| Pattern | Use When | Result |
|---------|----------|--------|
| **Extract Function** | Identical blocks across multiple call sites | Auth check in every handler → middleware |
| **Extract Constant/Config** | Magic values repeated across files | `30 * time.Second` in 3 files → `config.DefaultTimeout` |
| **Generic/Parameterized Function** | Near-identical functions differing by one call | `GetUser`, `GetOrder` → `getByID[T]` |
| **Template Method / Strategy** | Similar flows with one varying step | PDF/CSV generators → `GenerateReport(data, renderer)` |

### Step 1 — Secure the starting point

```bash
# Ensure all tests pass BEFORE you start
go test ./...          # Go
cargo test             # Rust
bun test               # Bun
npm test               # Node/TS
pytest                 # Python

# Ensure a clean git state
git status             # should be clean, or stash first
git stash              # if needed

# Create a dedicated branch
git checkout -b refactor/describe-the-change
```

**Rule: never refactor on a dirty working tree.** Mixing feature changes with refactoring makes rollback impossible.

### Step 2 — One transformation at a time

Each refactoring step must be **atomic** — a single, small, independently verifiable change.

| Step | Action | Verify |
|------|--------|--------|
| 1 | Extract function / constant / type | Run tests |
| 2 | Replace first call site with the new abstraction | Run tests |
| 3 | Replace next call site | Run tests |
| 4 | Remove old dead code | Run tests |
| 5 | Commit | `git commit -m "refactor: extract getByID generic handler"` |

**Never batch multiple extractions into a single step.**

```bash
# After EACH small change:
go test ./...  # or your project's test command
git add -p     # stage only the relevant change
git commit -m "refactor: step N — description"
```

### Step 3 — Verify behavior preservation

```bash
# Go: check exported symbols haven't changed
go doc ./pkg/handlers
go vet ./...
golangci-lint run ./...

# Rust: clippy + format + test
cargo clippy -- -W clippy::pedantic
cargo fmt -- --check
cargo test

# TypeScript / Bun: type check + lint
bunx tsc --noEmit          # or: npx tsc --noEmit
bunx biome check .         # or: npx eslint .
bun test                   # or: npx vitest run

# Find unused exports and dependencies (TypeScript / Bun)
bunx knip

# Run integration/e2e tests if available
npm run test:e2e

# Check for unused imports/variables introduced by refactoring
go vet ./...                                            # Go
cargo machete                                           # Rust
bunx knip                                               # TypeScript / Bun
npx eslint --rule '{"no-unused-vars": "error"}' src/    # TypeScript (eslint)
```

### Step 4 — Rollback strategy

```bash
# Undo current uncommitted change (keep committed steps)
git checkout -- .

# Revert just one committed step
git revert <commit-hash>

# Abandon the entire refactoring branch
git checkout main
git branch -D refactor/describe-the-change
```

The branch-per-refactoring approach means you never risk `main`.

### Common Pitfalls

- **Changing behavior during refactoring**: Resist the urge to "fix that bug while I'm here." Refactoring and behavior changes are separate commits — always.
- **Refactoring without tests**: If the code has no tests, **write characterization tests first** — tests that capture current behavior, even if that behavior has bugs.
- **Big-bang refactoring**: Rewriting an entire module at once. Prefer the Strangler Fig pattern — replace piece by piece.
- **Skipping the test run**: "It's just a rename." Type aliases, reflection, serialization, string-based routing — all break on renames.

## Implementation Checklist

- [ ] Is this function smaller than 30 lines?
- [ ] Does this function do exactly one thing?
- [ ] Are all names searchable and intention-revealing?
- [ ] Have I avoided comments by making the code clearer?
- [ ] Am I passing too many arguments?
- [ ] Is there a failing test for this change?
- [ ] Is there duplicated logic that could be extracted into a shared function?
- [ ] Are magic strings/numbers extracted into named constants?
- [ ] Did I check for existing utilities before writing a new helper?
- [ ] If I extracted a shared abstraction, is it used in 3+ places (Rule of Three)?
- [ ] Did I run all tests before AND after refactoring?
- [ ] Is each refactoring step in its own commit (one transformation per commit)?
- [ ] Did I avoid mixing behavior changes with structural refactoring?
- [ ] If the code had no tests, did I write characterization tests before refactoring?
