# Code Review — Python Reference

> Reference companion for the [code-review](../SKILL.md) skill. Python-specific patterns, sweeps, and example findings for CPython 3.13 / 3.14 (FastAPI / Django / Flask). Pairs with [code-debugger/references/PYTHON.md](../../code-debugger/references/PYTHON.md) (runtime playbooks) and [@code-security-review (Python branch)](../../code-security-review/references/python/API.md) (security lifecycle). Hand off API security audits to that skill.

## Tools

| Tool | Purpose | Install / Run |
| --- | --- | --- |
| `ruff check` / `ruff format` | Fast lint + format (replaces flake8/black/isort/pyupgrade/most of pylint) | `pipx install ruff` |
| `mypy --strict` | Strict static type check | `pipx install mypy` |
| `pyright` | Alternative type checker (Microsoft, drives Pylance) | `pipx install pyright` |
| `bandit -r` | SAST mapped to CWE | `pipx install bandit` |
| `pip-audit` | CVE scan via PyPI Advisory DB | `pipx install pip-audit` |
| `safety check` | Secondary CVE DB | `pipx install safety` |
| `semgrep` | Polyglot SAST + Python rule packs | `pipx install semgrep` |
| `vulture` | Dead-code detection | `pipx install vulture` |
| `radon` / `xenon` | Cyclomatic complexity metrics | `pipx install radon` |
| `pytest` (+ `pytest-asyncio`, `pytest-cov`) | Test runner (optional verification only) | per-project |
| `uv` | Fast package manager + lockfile auditor (Astral) | `pipx install uv` |

## Quick sweep

```bash
# Static sweep from the touched package/project root
ruff check .
ruff format --check .
mypy --strict .                                # or: pyright

# Security SAST
bandit -r src/ -q
semgrep --config=auto --error

# Dependency CVE scan
pip-audit
safety check --json

# Dead code + complexity
vulture src/
radon cc -s -a src/                            # cyclomatic; flag > 10

# Optional verification only
pytest --collect-only                          # confirms tests load
pytest -q                                      # only when explicitly requested
```

## Findings catalog — 28 patterns to scan

Run patterns against changed Python files through the [Diff Scope Contract](../SKILL.md#01-diff-scope-contract), then open matching files before filing a finding.

### 1. `Any` in a public signature

```bash
rg -n ':\s*Any\b' --type py
rg -n '^(def|async def)\s+[a-z][\w_]*\([^)]*:\s*Any\b' --type py
```

Severity floor: **Medium** for exported symbols, **Low** for internal narrow boundaries (with comment).

### 2. `cast(...)` / `# type: ignore` without a code

```bash
rg -n '\bcast\s*\(' --type py
rg -n '#\s*type:\s*ignore(?!\[)' --type py     # missing [error-code]
```

Severity floor: **Medium**. Each cast taxes the type system; each blanket `type: ignore` hides a real error. Require justification.

### 3. Mutable default argument

```bash
rg -n 'def\s+\w+\([^)]*=\s*(\[\]|\{\}|set\(\))' --type py
rg -n 'field\(default\s*=\s*(\[\]|\{\}|set\(\))' --type py
```

Severity floor: **High** in handler / request-scoped code, **Medium** elsewhere. Fix with `None` sentinel + body init, or `dataclasses.field(default_factory=list)`.

### 4. `except:` / bare `except Exception:` swallow

```bash
rg -n '^\s*except\s*:\s*$' --type py
rg -n '^\s*except\s+Exception\s*:' --type py
rg -n 'except[^:]*:\s*(pass|\.\.\.|continue)' --type py
```

Severity floor: **High**. Either name the specific exception or `raise` after logging.

### 5. `assert` for runtime invariants

```bash
rg -n '^\s*assert\s+' --type py
```

`python -O` strips assertions. Severity floor: **High** when used for auth / authz / input validation; **Low** for test-only invariants.

### 6. `eval` / `exec` / dynamic `compile`

```bash
rg -n '\b(eval|exec|compile)\s*\(' --type py
```

Severity floor: **Critical**. CWE-95. Use `ast.literal_eval` for trusted literals only; never on untrusted input.

### 7. `pickle.loads` / `marshal.loads` / `yaml.load` on untrusted input

```bash
rg -n '\b(pickle|marshal)\.loads?\s*\(' --type py
rg -n '\byaml\.load\s*\(' --type py            # without SafeLoader
rg -n '\b(jsonpickle|dill)\b' --type py
```

Severity floor: **Critical**. CWE-502. Use `yaml.safe_load`, JSON, msgspec, or protobuf — none execute code on parse.

### 8. `subprocess(..., shell=True)` with user input

```bash
rg -n 'subprocess\.(run|call|Popen|check_output)[^)]*shell\s*=\s*True' --type py
rg -n 'os\.(system|popen)\s*\(' --type py
```

Severity floor: **Critical**. CWE-78. Use the list form (`subprocess.run(["cmd", arg1, arg2])`) and pass user input as a list element.

### 9. SQL via f-string in `cursor.execute`

```bash
rg -n '(cursor|conn|db)\.execute\s*\(\s*f["\x27]' --type py
rg -n '(cursor|conn|db)\.execute\s*\([^)]*%\s*(\(|\[)' --type py
rg -n '(\.format\(|\+ )\s*["\x27]\s*SELECT|INSERT|UPDATE|DELETE' --type py
```

Severity floor: **Critical**. CWE-89. Use parameterized queries: `cursor.execute("SELECT ... WHERE id = %s", (uid,))` or the ORM. For SQLAlchemy raw, use `text("...:p")` with bound params.

### 10. `requests.get(user_url)` without allowlist

```bash
rg -n '(requests|httpx|urllib\.request)\.(get|post|put|delete)\s*\([^)]*\b(request\.|input|params|body|query)' --type py
```

Severity floor: **High** to **Critical** (when reachable from a public endpoint). CWE-918 SSRF. Validate scheme + hostname against an allowlist; resolve once and pass the resolved IP to block DNS rebinding.

### 11. Path traversal via `open(os.path.join(base, user_path))`

```bash
rg -n 'open\s*\([^)]*os\.path\.join\([^)]*\b(request|input|args|params|body)' --type py
rg -n 'Path\([^)]*\b(request|input)' --type py
```

Severity floor: **High**. CWE-22. Use `pathlib.Path(base).resolve()` + `(base / user_path).resolve().is_relative_to(base)`; reject otherwise.

### 12. `hashlib.md5` / `sha1` for security

```bash
rg -n 'hashlib\.(md5|sha1)\s*\(' --type py
```

Severity floor: **High** for security-sensitive use (signatures, password hashing, token derivation); **Low** for non-security checksums (with comment). Use `hashlib.sha256` / `blake2b` for general hashes; `argon2-cffi` or `bcrypt` (cost ≥ 12) for passwords.

### 13. `random.random()` / `random.choice` for tokens

```bash
rg -n 'random\.(random|choice|randint|randrange|sample|shuffle)\s*\(' --type py
```

Severity floor: **Critical** when used for tokens, IDs, password reset codes, CSRF, session. Use `secrets.token_urlsafe`, `secrets.token_hex`, `secrets.SystemRandom`.

### 14. `Jinja2(autoescape=False)` / `Markup(user_input)`

```bash
rg -n 'Environment\([^)]*autoescape\s*=\s*False' --type py
rg -n 'jinja2\.Template\(' --type py
rg -n '\bMarkup\(' --type py
```

Severity floor: **High**. CWE-79 / CWE-1336. Use `select_autoescape(["html", "xml"])` (default in modern Jinja2). Never `Markup(user_input)`.

### 15. `lxml.etree.parse` with default parser (XXE)

```bash
rg -n 'lxml\.etree\.(parse|fromstring|XMLParser)\(' --type py
rg -n '\bxml\.(etree|dom|sax)\.' --type py
```

Severity floor: **High**. CWE-611. Use `defusedxml` or `lxml` with `XMLParser(resolve_entities=False, no_network=True, huge_tree=False)`.

### 16. Hardcoded `SECRET_KEY` / `DEBUG = True`

```bash
rg -n 'SECRET_KEY\s*=\s*["\x27]' --type py
rg -n 'DEBUG\s*=\s*True' --type py
rg -n 'ALLOWED_HOSTS\s*=\s*\[\s*["\x27]\*' --type py
```

Severity floor: **Critical** (`SECRET_KEY` hardcoded) / **High** (`DEBUG=True` in committed code or env-default). Read from env via `pydantic-settings` or `django-environ`; fail closed if absent.

### 17. `from xyz import *`

```bash
rg -n '^from\s+\S+\s+import\s+\*' --type py
```

Severity floor: **Low**. Promotes shadowing; obscures provenance. Replace with explicit imports.

### 18. Logger leaks `Authorization` / `password` / `token`

```bash
rg -n 'log(ger)?\.(info|debug|warning|error)\s*\([^)]*\b(password|token|secret|cookie|authorization|api[_-]?key|jwt)\b' --type py
```

Severity floor: **High**. CWE-532. Use structured logging with a redactor (`structlog` processors) or mask explicitly.

### 19. `print` in production code paths

```bash
rg -n '^\s*print\(' --type py --glob '!**/tests/**' --glob '!**/scripts/**' --glob '!**/cli/**'
```

Severity floor: **Low**. Use `logging` (structlog/loguru) so output is configurable and capturable.

### 20. `async def` that never `await`s anything

```bash
rg -n -B 1 -A 30 '^async def' --type py        # manual scan: body should contain `await`
```

Or use `ruff` with `RUF029` (`unused-async`). Severity floor: **Low**. Either drop the `async` or the function is misused.

### 21. `await` inside a loop

```bash
rg -n -C 3 '^\s*for .*:|await\s' --type py
```

Severity floor: **Medium**. Use `asyncio.gather(*[coro(x) for x in xs])` (with concurrency limit via `asyncio.Semaphore`) when iterations are independent.

### 22. Blocking call inside a coroutine

```bash
rg -n -B 2 -A 8 'async def' --type py | rg 'time\.sleep|requests\.|open\(.*\.read\(\)|subprocess\.run|psycopg2|pymongo'
```

Severity floor: **High** on hot path. Replace `time.sleep` → `asyncio.sleep`; `requests` → `httpx.AsyncClient`; `open(...).read()` → `aiofiles`; sync ORM → async driver (`asyncpg`, `motor`).

### 23. CORS `allow_origins=["*"]` + `allow_credentials=True`

```bash
rg -n -A 3 'CORSMiddleware|add_middleware\(CORS' --type py
rg -n 'allow_origins\s*=\s*\[\s*["\x27]\*' --type py
rg -n 'allow_credentials\s*=\s*True' --type py
```

Severity floor: **Critical** when both appear together (CVE-2025-34291 anti-pattern, Langflow). Pin origins to a literal allowlist; credentials require non-wildcard origins.

### 24. FastAPI endpoint reading `request.json()` without a schema

```bash
rg -n 'await\s+request\.json\(\)' --type py
rg -n '^\s*(async\s+)?def\s+\w+\s*\([^)]*body\s*[:=]' --type py
```

Severity floor: **Medium**, promote to **High** when the unchecked input controls auth / money movement / file paths / outbound URLs / SQL filters. Use Pydantic `BaseModel` parameters; refuse raw `request.json()` in route handlers.

### 25. Mutable global state at module top-level

```bash
rg -n '^[A-Z_]+\s*=\s*(\[\]|\{\}|set\(\)|defaultdict|Counter\(\))' --type py
```

Severity floor: **Medium** in libraries; **Low** in app code with documented ownership. Mutable globals plus the free-threaded build (3.13t / 3.14t) without a `Lock` become race conditions.

### 26. Lockfile drift

```bash
git diff "$DIFF_RANGE" -- pyproject.toml requirements*.txt uv.lock poetry.lock Pipfile.lock setup.cfg setup.py
```

Severity floor: **Medium**. Lockfile must be updated alongside the manifest. Re-resolve: `uv lock` / `poetry lock --no-update` / `pip-compile`.

### 27. `dataclasses.field(default=[])` (mutable default trap)

```bash
rg -n 'field\(default\s*=\s*(\[\]|\{\}|set\(\))' --type py
```

Severity floor: **High**. Fix: `field(default_factory=list)`. Same trap as #3 but the linter often misses it because the default is wrapped in a function call.

### 28. `__eq__` / `__hash__` pair broken

```bash
rg -n 'def\s+__eq__\s*\(' --type py
rg -n 'def\s+__hash__\s*\(' --type py
```

Severity floor: **Medium**. Defining `__eq__` without `__hash__` silently sets `__hash__ = None`, making the object unhashable. If equality is value-based, define both; if equality should be by identity (`is`), define neither.

## Python 3.13 / 3.14 specific patterns

- **Free-threaded build (`python3.14t` / `python3.13t`)** — PEP 779 promoted free-threading from experimental to **supported on `3.14t` only**; `3.13t` remains experimental. Both runtimes drop the GIL, so race conditions surface identically — but support status differs and affects deployment grading. Modules with mutable global state need explicit `Lock`/`RLock`. Sweep candidates: `rg -n '^[A-Z_]+\s*=\s*(\[\]|\{\}|set\(\))' --type py` (cross-reference #25). C extensions must declare `Py_mod_gil = Py_MOD_GIL_NOT_USED` or they force the GIL back on at import.
- **PEP 649 / 749 deferred annotations** — default on 3.14. `from __future__ import annotations` is now redundant. Prefer `inspect.get_annotations(obj, format=annotationlib.Format.STRING)` over `obj.__annotations__` direct access — the latter triggers evaluation.
- **PEP 750 t-strings** — `t"..."` produces a `Template` object, distinct from f-strings. Safer for SQL, HTML, shell composition because interpolated values stay structured until the renderer decides how to escape them. Investigate template-style call sites for migration.
- **PEP 742 `TypeIs` vs `TypeGuard`** — `TypeIs` narrows in both branches; `TypeGuard` narrows only in the truthy branch. Sweep for `TypeGuard` and recommend `TypeIs` when both branches need narrowing.
- **Experimental JIT (3.13)** — opt-in build (`--enable-experimental-jit`). Observability footnote only; do not raise findings on JIT presence/absence.
- **`asyncio.eager_task_factory`** — opt-in synchronous-first task scheduling reduces hot-path latency when the coroutine doesn't actually await. Flag as an Info observation for high-QPS services.

## Test smell sweep

```bash
# Tests without assertions
rg -L '(assert |self\.assert)' --glob '**/test_*.py' --glob '**/*_test.py'

# Skipped tests without a reason
rg -n '(@pytest\.mark\.skip(\b|\()|@unittest\.skip\b)' --type py | rg -v 'reason='

# print() in tests (debugging leftover) — pytest captures by default
rg -n '^\s*print\(' --glob '**/test_*.py' --glob '**/*_test.py'

# pytest fixtures missing scope (default "function" is right almost always)
rg -n '@pytest\.fixture\(.*scope=' --type py

# pytest-asyncio mode not set
rg -n 'asyncio_mode' pyproject.toml pytest.ini setup.cfg tox.ini 2>/dev/null
```

## Performance sweep

```bash
# await in loop (#21)
rg -n -C 3 '^\s*for .*:|await\s' --type py

# Sync I/O on hot paths
rg -n '\b(time\.sleep|requests\.|open\(.+\.read\(\))' --type py

# Large json.dumps on the request path
rg -n 'json\.dumps\(' --type py --glob '!**/tests/**' --glob '!**/scripts/**'

# re.compile inside a hot loop (allocations per iteration)
rg -n -C 3 '^\s*for .*:|re\.(match|search|fullmatch|findall|sub)\(' --type py

# N+1 ORM
rg -n -C 3 'for .*:|\.objects\.(get|filter|first)\b|session\.query\(' --type py
rg -n -C 3 'for .*:|SELECT.*WHERE.*\.(id|pk)\s*=' --type py

# SQLAlchemy lazy-load surprise (no eager loading)
rg -n 'relationship\(' --type py | rg -v 'lazy='
```

## Hand-off triggers

- API security review (design + active testing + framework-specific vulns) → `@code-security-review` (Python branch — [`references/python/`](../../code-security-review/references/python/API.md)).
- Refactor / clean-code → `@clean-code`.
- Runtime exception, memory leak, async deadlock, free-threaded race → `@code-debugger` ([references/PYTHON.md](../../code-debugger/references/PYTHON.md)).
- Type-system rework crossing many modules → propose a `mypy --strict` rollout plan; do not absorb the change into a code-review finding.
