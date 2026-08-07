# Duplication

> Reference companion for the [clean-code](../SKILL.md) skill. Owns the taxonomy, the detection probes, and the extract / do-not-extract decision.

> **Boundary with `@code-optimization`.** That skill grades a duplication finding on a **perf-impact axis** — do the copies multiply I/O, allocation, or GC pressure? — and reports it in `OPTIMIZATION_REPORT.md`. This file owns classification and detection; the refactor mechanics live in [SKILL.md](../SKILL.md) Phase 3 and the diffs in [PATTERNS.md](PATTERNS.md). Do not re-derive a perf Impact grade here — hand off to `@code-optimization` when the user needs one.

## 1. DRY

> "Every piece of knowledge must have a single, unambiguous, authoritative representation within a system."

Duplication is the same **knowledge, logic, or intent** expressed in more than one place. The test is not textual similarity — it is whether a single decision would have to be re-made in two places. Two blocks with identical syntax serving different domain concepts are not duplication; coupling them creates a worse defect than leaving them apart.

## 2. The four classes

| Class | Signature | Why it hurts | Detection |
|-------|-----------|--------------|-----------|
| **Literal** | Identical blocks copied verbatim between functions, files, or classes | Copies drift; the next fix lands in one of them, not all | Clone tools (`jscpd`, `dupl`) |
| **Logical** | Same outcome, different variable names or control flow | Invisible to clone tools — only reading finds it | Similar signatures, verb×noun families |
| **Structural** | Repeated `if/else` or `switch` chains spelling out the same decision | Adding one case means editing N sites; one site gets forgotten | Branch-chain ranking + commit history |
| **Data** | Constants, URLs, configs, error envelopes repeated across files | Values drift silently; the copies disagree under load | Literal frequency counts |

The **Structural** class is the one teams miss. A chain is not too long because the function is big — it is too long because the decision has no single home.

> Vocabulary note: `@code-optimization` uses these same four names with the same meanings. If a finding crosses the two skills, the class name carries over unchanged.

## 3. Detection commands

Every probe is language-agnostic; only the type filter changes. Substitute `<T>` with `go`, `rust`, `ts`, `tsx`, or `py`.

```bash
# Literal — polyglot anchor command; start here
jscpd --min-lines 5 --min-tokens 50 --reporters console ./src

# Literal — Go-specific AST clone detection (catches what jscpd's token pass misses)
dupl -t 50 ./...

# Logical — near-identical function families: same verb, different noun
rg -i '(get|fetch|retrieve|load|find|create|build)[_A-Z]?(user|account|profile|order|invoice)' --type <T>

# Logical — repeated error mapping / wrapping
rg -c '\.map_err\(|\.with_context\(|fmt\.Errorf\(|raise \w+Error\(' --type <T> | sort -t: -k2 -rn | head -10

# Logical — Python simplification and dedup hints from the linter
ruff check --select=SIM,C90,PLR0911,PLR0912 .

# Structural — longest branch chains: the switch that keeps growing
rg -c '^\s*(else if|elif|case |when |match )' --type <T> | sort -t: -k2 -rn | head -10

# Structural — the same discriminator branched in N files; one new case = N edits
rg -l 'switch \w*(Type|Kind|Status|Channel)|match \w*(type|kind|status)|if \w+_type ==' --type <T>

# Data — files densest in long string literals
rg -c '"[^"]{10,}"' --type <T> | sort -t: -k2 -rn | head -20

# Data — repeated URLs and endpoints
rg -o '(http|https)://[a-zA-Z0-9./-]+' | sort | uniq -c | sort -rn | head -10

# Data — repeated response envelopes and error payloads
rg -o 'gin\.H\{"error"|res\.status\([0-9]+\)\.json|JSONResponse\(status_code=' | sort | uniq -c | sort -rn | head -10

# Data — npm packages a Bun native already replaces
rg '"(node-fetch|cross-fetch|dotenv|better-sqlite3|glob|fast-glob|bcrypt|jest|ts-jest|nodemon)"' package.json
```

Clone tools report **candidates**, not findings. Every hit needs a read before it becomes a refactor: `jscpd` cannot tell a copied validation rule from two unrelated structs that happen to share field order.

## 4. Reading the Structural signal

A file at the top of the branch-chain ranking is a suspect, not a verdict. Confirm with history:

```bash
# Did the chain grow in separate commits? Parallel growth = missing dispatch
git log -p --follow <file> | rg '^\+.*(else if|elif|case |when )' | head -20

# How many files changed together the last time a case was added?
git log --format='%h %s' -S 'case "push"' -- . | head -5
git show --stat <that-commit>
```

Three or more commits each adding one branch to the same chain, or a single commit touching the same chain in three files, is the structural pattern. Fix with [PATTERNS.md](PATTERNS.md) §6 — dispatch table first, interface only if the cases carry several behaviors each.

## 5. When NOT to deduplicate

**Rule of Three: tolerate two copies, extract on the third.** The pattern has to prove itself before it earns an abstraction. Before extracting on the third, check:

- **Accidental vs real duplication** — the blocks look identical today but represent different domain concepts that will evolve independently. Coupling them creates fragility worse than the duplication.
- **Different rate of change** — the copies belong to different bounded contexts, services, or teams. Coupling them forces shotgun surgery across boundaries.
- **Premature abstraction** — the shared function needs 4 parameters and 2 boolean flags to serve every caller. The cure is worse than the disease; leave them apart and revisit later.
- **An ADR documents the duplication** — it was a decision, not an accident. Respect it; do not relitigate it through a refactor.
- **Test duplication is often correct** — explicit, repetitive test setup reads better than a helper that hides what is under test. Deduplicate tests only when the repetition hides a missing case.

Cross-boundary duplication that survives these checks is a finding worth reporting even when the answer is "leave it" — say so explicitly, with the reason, so the next reader does not re-open the question.

## 6. Choosing the pattern

| Class | Pattern | Where |
|-------|---------|-------|
| Literal | Extract Function | [PATTERNS.md](PATTERNS.md) §1 |
| Data | Extract Constant / Config | [PATTERNS.md](PATTERNS.md) §2 |
| Logical — same shape, one varying value | Generic / Parameterized Function | [PATTERNS.md](PATTERNS.md) §3 |
| Logical — same flow, one varying step | Template Method / Strategy | [PATTERNS.md](PATTERNS.md) §4 |
| Logical — two implementations of one job | Substitute Algorithm | [PATTERNS.md](PATTERNS.md) §5 |
| Structural | Replace Conditional with Polymorphism | [PATTERNS.md](PATTERNS.md) §6 |

Apply them under the Phase 3 protocol in [SKILL.md](../SKILL.md): one transformation per commit, tests between each, characterization tests first when coverage is missing.
