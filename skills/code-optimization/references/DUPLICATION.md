> Reference companion for the [code-optimization](../SKILL.md) skill.

# Duplication

Duplication is the canonical Clean Code smell with a perf angle: copies drift, and drift amplifies maintenance and bug surface. From a perf lens specifically, duplication often hides allocator pressure (each copy re-allocates), redundant DB calls (each copy re-fetches), and divergent caches.

This reference covers detection, classification, and **when not to deduplicate**. For refactor mechanics, hand off to `@clean-code` Phase 3.

## 1. DRY revisited

> "Every piece of knowledge must have a single, unambiguous, authoritative representation within a system." — The Pragmatic Programmer

Duplication = same **knowledge / intent / business rule** repeated. Same syntax in different domains is not duplication.

## 2. Three classes of duplication

| Class | Description | Detection signal | Default Impact |
| --- | --- | --- | --- |
| **Literal** | Identical blocks copied verbatim between files / classes / functions | jscpd / dupl / cargo-duplicates / sonarjs `no-duplicate-string` | Medium |
| **Logical** | Different variable names or control flow, same outcome | Manual review of similar signatures; AST diff if tooling available | Medium |
| **Structural** | Repetitive `if/else` or `switch` chains spelling the same decision tree | grep for branching structures + commit history showing parallel growth | Medium → High when the chain grows on every feature |

## 3. Detection — cross-language

```bash
# jscpd (polyglot) — anchor command
jscpd --min-lines 5 --min-tokens 50 --threshold 0 --reporters console,json --output ./jscpd-report .

# Go
dupl -t 50 ./...
# (or) go install github.com/mibk/dupl/cmd/dupl@latest

# Rust
cargo install cargo-duplicates 2>/dev/null
cargo duplicates                                # transitive dep duplicates (perf via binary size + compile time)
# AST-level Rust clone: rust-code-analysis or similar; jscpd is acceptable

# TypeScript / Node / Bun
bunx jscpd --min-lines 5 --min-tokens 50 src/
bunx eslint --rule '{"sonarjs/no-duplicate-string": ["error", {"threshold": 3}]}' src/

# Python
ruff check . --select=SIM        # simplification / dedup opportunities
jscpd src/

# Repeated string literals (per language)
rg -c '"[^"]{10,}"' --type ts | sort -t: -k2 -rn | head -20
rg -c '"[^"]{10,}"' --type py | sort -t: -k2 -rn | head -20
rg -c '`[^`]{10,}`' --type rust | sort -t: -k2 -rn | head -20
```

## 4. Refactor patterns (handed off to `@clean-code`)

| Pattern | When to use | Result |
| --- | --- | --- |
| **Extract Function** | Same 3+ blocks across call sites | Auth check copied to every handler → middleware |
| **Substitute Algorithm** | Two functions do the same task in two ways — keep the cleaner one | Two CSV parsers → keep the streaming one |
| **Extract Constant / Config** | Magic value repeated across files | `30 * time.Second` in 3 files → `config.DefaultTimeout` |
| **Polymorphism (Strategy / Template Method)** | Repeated `switch` driving behavior selection | PDF / CSV / JSON exporters → `GenerateReport(data, renderer)` |
| **Generic / Parameterized Function** | Near-identical functions differing by one argument | `GetUser` + `GetOrder` → `getByID[T](id)` |

For step-by-step refactor mechanics (one transformation per commit, characterization tests first, branch-per-refactor), see `@clean-code` Phase 3.

## 5. When NOT to deduplicate

Not all repetition is a defect. Apply Rule of Three: **tolerate two copies, extract on the third**. Before extracting on the third, also check:

- **Accidental vs real duplication** — two blocks look identical today but represent different domain concepts that will evolve independently. Coupling them creates fragility worse than the duplication.
- **Different rate of change** — pieces belonging to different bounded contexts / teams. Coupling forces shotgun surgery across team boundaries.
- **Premature abstraction** — the "shared" function needs 4 parameters and 2 boolean flags to handle all cases. Cure is worse than the disease; leave them apart and re-evaluate later.
- **ADR documents the duplication intentionally** — respect the ADR; don't relitigate via refactor.

## 6. Perf-specific consequences

When choosing the Impact grade for a duplication finding, weigh these signals:

| Signal | Impact lift |
| --- | --- |
| The duplicated code does I/O (DB, HTTP) in a hot path | +1 (Medium → High) — N copies = N round-trips |
| The duplicated code allocates large structures | +1 — each copy adds GC pressure |
| The duplicated code embeds a magic constant (timeout, page size, retry count) that drifted across copies | +1 — drift causes inconsistent behavior under load |
| The duplicated code is pure CPU but inside a tight loop | +0 → +1 — depends on compiler hoisting; verify with profile |
| The duplicated code is in tests | +0 — readability concern, not perf |

## 7. Reporting

Findings of class **Literal** should be ranked by token count from the jscpd output. Top-5 clones go into the report; the rest are summarized as `N more clones below the threshold — see jscpd-report/`.

Findings of class **Logical / Structural** require a code quote from each occurrence in the report; pure summary statistics are not enough.

## 8. Cross-link to `@clean-code`

The duplication audit overlaps with `@clean-code` Phase 2. `@code-optimization` keeps the **perf-impact lens** (do I/O / allocation / GC consequences argue for promotion to Impact High?). For the **refactor mechanics** (Extract Method, Strategy, Template Method, characterization tests), point the user to `@clean-code` Phase 3.

A finding ranked Impact=High in this skill SHOULD recommend running `@clean-code` next for the safe-refactoring sequence.
