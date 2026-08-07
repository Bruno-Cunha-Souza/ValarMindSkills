# Dead Code

> Reference companion for the [clean-code](../SKILL.md) skill. Detection per language, the guardrails that must clear before deleting a symbol, and the removal protocol.

Dead code is a symbol nothing reaches: a function never invoked, an import never used, a variable assigned and never read, a branch that cannot execute. It costs review time on every pass, widens the blast radius of every refactor, and lies to the next reader about what the system does.

> **Every tool below reasons over the static call graph.** Reflection, dependency injection, registries, framework decorators, serialization, and string-based routing are invisible to that graph. A symbol they reach looks dead to the tool, passes the test suite when deleted, and fails in production. §3 is not optional.

## Tools

| Tool | Purpose | Install / Run |
|------|---------|---------------|
| `deadcode` | Go reachability analysis from `main()` | `go install golang.org/x/tools/cmd/deadcode@latest` |
| `staticcheck` | Go unused identifiers (`U1000`) | `go install honnef.co/go/tools/cmd/staticcheck@latest` |
| `knip` | TS/Bun unused files, exports, types, and deps in one pass | `bunx knip` / `npx knip` |
| `vulture` | Python dead code with confidence tiers | `pipx install vulture` |
| `deptry` | Python unused / missing / transitive dependencies | `pipx install deptry` |
| `cargo-machete` | Rust unused dependencies, stable toolchain | `cargo install cargo-machete` |
| `rg` | The cross-asset sweep no dead-code tool performs | `brew install ripgrep` |

## 1. Types and what confirms each

| Type | Signal | Confirmed dead only when |
|------|--------|--------------------------|
| **Unreferenced function / method** | `deadcode`, `knip`, `vulture` | Zero call sites in source **and** tests **and** templates **and** config **and** CI; not a published API |
| **Unreferenced type / class / struct** | `staticcheck U1000`, rustc `never constructed`, `knip` | As above, **plus** it is not a serialization target — no marshaller, ORM, or schema derives from it |
| **Unreferenced enum variant / case** | rustc `never constructed`, `knip` | No wire format, DB column, or persisted record ever carried that value |
| **Unused import** | `ruff F401`, `biome`, `go vet` | Not a side-effect import (driver registration, `init()`, polyfill, monkeypatch) and not a re-export |
| **Assigned-never-read variable** | `ruff F841`, `ineffassign`, `--noUnusedLocals` | Not an intentional `_` placeholder; the right-hand side has no side effect being relied on |
| **Unused parameter** | `unparam`, `ruff ARG`, `--noUnusedParameters` | The signature is not fixed by an interface, trait, ABC, callback contract, or override |
| **Unreachable branch** | `vulture --min-confidence 100`, `staticcheck`, 0% coverage | The guard is provably constant: dead feature flag, code after `return`/`raise`, `if False` |
| **Commented-out code block** | `ruff ERA001`, `rg '^\s*(//\|#)\s*(if\|for\|func\|def\|return)'` | Always dead. Git is the archive — delete unconditionally |
| **Unused dependency** | `knip`, `depcheck`, `deptry`, `cargo machete`, `go mod tidy` diff | Not used by a build step, generated code, plugin loader, or type-only import |
| **Orphan file / module** | `madge --orphans`, `knip --include files` | Nothing imports it **and** no entry-point manifest names it |
| **Permanently skipped test** | `rg '@pytest.mark.skip\|t.Skip(\|it.skip\|#\[ignore\]'` | Skipped across more than one release with no linked issue. Fix it or delete it — never leave it |
| **Dead config key / env var** | `rg -F 'KEY_NAME'` across code, charts, and CI | Read nowhere in code and absent from every deployment manifest |
| **Lint suppression with no target** | `ruff RUF100`, `golangci-lint --enable=nolintlint` | The thing it suppressed is gone. Delete the suppression, not the code around it |

## 2. Command matrix

### Go

```bash
deadcode ./...                                   # reachability from main() — the authoritative answer
deadcode -test ./...                             # counts tests as roots; fewer false positives
staticcheck -checks 'U1000' ./...                # unused package-level identifiers
golangci-lint run --enable=unused,unparam,ineffassign,nolintlint ./...
go mod tidy && git diff --exit-code go.mod go.sum    # a non-empty diff means unused module requirements
rg '//nolint' --type go                          # existing suppressions — read the reason before overriding
```

### Rust

```bash
cargo build --all-targets 2>&1 | rg 'never used|never read|never constructed'   # rustc dead_code lint
cargo clippy --all-targets -- -W unused_crate_dependencies
cargo machete                                    # unused deps, fast, stable toolchain
cargo +nightly udeps --all-targets               # unused deps, more accurate
rg '#\[allow\(dead_code\)\]' --type rust         # someone already decided this — read why first
cargo build --all-features                       # re-run: cfg-gated code looks dead in the default build
```

### TypeScript / Bun

```bash
bunx knip                                        # unused files, exports, types, and deps in one pass
bunx tsc --noEmit --noUnusedLocals --noUnusedParameters
bunx biome check .                               # or: npx eslint . --rule '{"no-unused-vars":"error"}'
bunx madge --orphans --extensions ts,tsx src/    # files nothing imports
bunx depcheck                                    # package.json deps only — knip is the superset
```

### Python

Confidence tiers are vulture's own: 100% for unused arguments and unreachable code, 90% for imports, 60% for attributes, classes, functions, methods, properties, and variables.

```bash
vulture src/ tests/ --min-confidence 100         # unreachable code + unused arguments — act on these
vulture src/ tests/ --min-confidence 90          # + unused imports — verify the side-effect cases
vulture src/ tests/                              # + functions, classes, attributes — assume false positives until proven
ruff check --select=F401,F811,F841,ARG,ERA001,RUF100 .
deptry .                                         # unused, missing, and transitive dependencies
pytest --cov=src --cov-report=term-missing       # 0% coverage is evidence of deadness, never proof
```

Pass `tests/` as an extra root or every fixture and test helper is reported as dead. Persist framework hooks once with `vulture --make-whitelist src/ > whitelist.py` and commit the file, so later runs stay clean instead of re-litigating the same false positives.

### Polyglot — the sweep every tool above misses

```bash
SYM=SymbolName

# 1. Real references in source
rg -w "$SYM" --stats

# 2. Non-source assets: config, templates, SQL, IaC, docs
rg -F "$SYM" -g '*.{yaml,yml,json,toml,ini,cfg,env,sql,html,jinja,jinja2,tmpl,vue,svelte,md,tf,tfvars}' \
             -g 'Dockerfile*' -g 'Makefile*' -g '.github/**'

# 3. Entry points declared outside the module graph
rg -n 'scripts|entry_points|console_scripts|\[\[bin\]\]|"bin"|"exports"|__all__' \
   pyproject.toml setup.cfg setup.py Cargo.toml package.json 2>/dev/null

# 4. History: was it ever used, and how old is it?
git log --oneline -S "$SYM" -- . | tail -5
git log --diff-filter=A --format='%ad %h %s' --date=short -S "$SYM" | tail -1
```

## 3. False-positive guardrails

Each item below is a way a symbol is reached without appearing in the static call graph. Walk every one that applies to the stack. **A hit means the symbol is live, not dead.**

- **Reflection and dynamic attribute access.** Go `reflect`, Python `getattr` / `globals()` / `importlib.import_module` / `__subclasses__()`, TS `obj[key]` / `Function`, Rust `Any` downcast. Sweep: `rg 'getattr\(|importlib|globals\(\)|__subclasses__|reflect\.|\[\s*\w+Name\s*\]'`.
- **DI containers and registries.** wire/fx/dig providers, NestJS decorators, Spring-style autowiring, `init()`-time registration, Rust `linkme`/`ctor`. The provider is referenced by *type*, never by name.
- **A framework decorator as the only call site.** `@app.route`, `@router.get`, `@celery.task`, `@shared_task`, `@pytest.fixture` in `conftest.py`, `@field_validator`, `@app.on_event`, Django `Command.handle` under `management/commands/`, Django signal receivers, Alembic `upgrade`/`downgrade`.
- **Serialization boundary.** A field "nobody reads" is written by a marshaller and consumed by a client or a DB column. Deleting it is a schema change, not a cleanup.
- **Entry points declared outside code.** `pyproject.toml [project.scripts]`, `package.json` `bin`/`exports`, `Cargo.toml [[bin]]`, a subcommand invoked by cron, a Makefile target, a k8s `command:`, a GitHub Actions step.
- **String-based routing and templates.** Django URLconf strings, `getattr(handler, verb)` dispatch, a Jinja or Handlebars template calling a helper, a SQL function name, an i18n key, a serializer named by string in a queue payload.
- **Published API surface.** Unused *inside* this repo but exported to consumers: a published crate or npm package, an exported Go package symbol, anything in `__all__`, anything `#[no_mangle]`. Deleting it is a semver-major break, not dead-code removal.
- **Build-config-conditional code.** `#[cfg(feature = "x")]`, `//go:build tag`, `if TYPE_CHECKING:`, `process.env.NODE_ENV` branches, platform-specific modules. The tool analyzed **one** configuration — re-run across the others before believing it.
- **Generated code.** protobuf, OpenAPI clients, sqlc, Prisma, GraphQL codegen. Never hand-delete generated output; change the generator input or its config.
- **Recently added or dark-launched.** `git log --diff-filter=A` shows the symbol landed days ago behind an off feature flag. Not dead — unreleased. Ask before touching.
- **Migrations and one-shot scripts.** Invoked once historically, still required for replay, rollback, or a fresh environment. Permanently unreferenced by design.
- **Test-only usage.** A symbol reached only from tests is not dead. It means either an untested production path or a test helper living in production code. Move it — do not delete it.

## 4. Removal protocol

1. **Two independent signals.** A tool finding **plus** an empty §2 polyglot sweep. One signal is a hypothesis, not evidence.
2. **Guardrails cleared.** Walk §3 and record which ones you checked in the commit body, so the deletion can be audited later.
3. **One deletion class per commit.** Unused imports in one commit, unreferenced functions in another. A mixed deletion commit cannot be partially reverted.
4. **Deletion is its own commit, never mixed with a refactor.** In [SKILL.md](../SKILL.md) Phase 3 this is step 4: the extraction lands and tests pass first, the old code dies after.
5. **Full test, build, and lint run after each deletion commit.** A build failure here is the good outcome — it is the case a silent runtime failure would otherwise have become.
6. **When in doubt, deprecate instead of deleting.** Mark it, log a warning on call, ship, wait one release, then delete with production evidence of zero calls. Cheaper than an incident.

Dead code is deleted, not commented out — git already keeps the history, and a commented block is dead code that survives every future sweep.

For what else is worth deleting beyond dead symbols — speculative abstractions, dependencies the standard library replaces, config nobody sets — run `@ponytail-review`.
