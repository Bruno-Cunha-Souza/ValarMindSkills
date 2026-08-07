# Python — Clean Code Reference

> Language-specific companion for the [clean-code](../SKILL.md) skill. Covers Python idioms, tooling, smells, and refactoring patterns. Security findings (mutable default arguments, bare `except`, `eval`/`pickle`, SQL injection) are out of scope — see `@code-review` (`references/PYTHON.md`, 28-pattern catalog).

Targets CPython 3.13 / 3.14. Package managers: `uv`, `poetry`, `pip`.

## Tools

| Tool | Purpose | Install / Run |
|------|---------|---------------|
| `ruff` | Linter + formatter (replaces flake8, black, isort, pyupgrade) | `pipx install ruff` → `ruff check .` |
| `mypy` | Static type checker | `pipx install mypy` → `mypy --strict .` |
| `vulture` | Dead code with confidence tiers | `pipx install vulture` |
| `deptry` | Unused, missing, and transitive dependencies | `pipx install deptry` |
| `radon` | Cyclomatic complexity and maintainability index | `pipx install radon` |
| `jscpd` | Clone detection (works on Python) | `npx jscpd src/` |
| `pytest` | Test runner — the safety net for every refactor | per-project |

### Quick Audit

```bash
# Lint + format check
ruff check .
ruff format --check .

# Type check — catches refactoring regressions the tests miss
mypy --strict .

# Complexity: flag anything over 10
radon cc -s -a src/
radon mi -s src/                    # maintainability index per file

# Dead code and unused deps
vulture src/ tests/ --min-confidence 90
ruff check --select=F401,F841,ARG,ERA001,RUF100 .
deptry .

# Duplication
npx jscpd --min-lines 5 --min-tokens 50 src/
ruff check --select=SIM,C90,PLR0911,PLR0912 .
```

## Python-Specific Smells

### 1. Dict-as-Object

A `dict` used as a record: the keys are a contract nothing checks.

```diff
# Bad — a typo in a key is a KeyError in production
- def build_user(row):
-     return {"id": row[0], "name": row[1], "role": row[2]}
-
- def is_admin(user):
-     return user["role"] == "admin"

# Good — the shape is checked and the role set is closed
+ class Role(StrEnum):
+     ADMIN = "admin"
+     MEMBER = "member"
+
+ @dataclass(frozen=True, slots=True)
+ class User:
+     id: int
+     name: str
+     role: Role
+
+ def is_admin(user: User) -> bool:
+     return user.role is Role.ADMIN
```

`@dataclass` also deletes the `__init__` / `__repr__` / `__eq__` boilerplate that gets copy-pasted between classes — a duplication fix and a readability fix in one move. Use `TypedDict` when the value must stay a real `dict` at a boundary (a JSON payload): it types the keys without changing the runtime type. Use `Enum` / `StrEnum` for any closed set of string constants.

**Detect:** `rg -n '\[["\x27]\w+["\x27]\]' --type py | head -30` and `rg -n 'def \w+\([^)]*\)\s*->\s*dict' --type py`

### 2. `if/elif` Dispatch Chain

The chain that grows on every new case — and grows in every function that switches on the same value.

```diff
# Bad — one new format means editing every chain that knows about formats
- def export(data, fmt):
-     if fmt == "csv":
-         return to_csv(data)
-     elif fmt == "json":
-         return to_json(data)
-     elif fmt == "parquet":
-         return to_parquet(data)
-     raise ValueError(f"unknown format {fmt!r}")

# Good — one table; a new format is one entry
+ EXPORTERS: dict[str, Callable[[Data], bytes]] = {
+     "csv": to_csv,
+     "json": to_json,
+     "parquet": to_parquet,
+ }
+
+ def export(data: Data, fmt: str) -> bytes:
+     try:
+         exporter = EXPORTERS[fmt]
+     except KeyError:
+         raise ValueError(f"unknown format {fmt!r}") from None
+     return exporter(data)
```

Keep the `raise`. Replacing a chain with a lookup removes the repetition, not the duty to reject unknown input. When the dispatch is on a *type* rather than a string, `functools.singledispatch` is the idiomatic form — see Refactoring Patterns below. When the cases are exhaustive over a union, `match` plus a `typing.assert_never` default lets the type checker prove no case is missing.

**Detect:** `rg -c '^\s*elif ' --type py | sort -t: -k2 -rn | head -10`

### 3. `**kwargs` Soup

A signature that documents nothing and silently accepts typos.

```diff
# Bad — a caller passing fmt= instead of format= gets the default, no error
- def create_report(**kwargs):
-     title = kwargs.get("title", "")
-     rows = kwargs.get("rows", [])
-     fmt = kwargs.get("format", "csv")

# Good — explicit, type-checked, discoverable from the signature
+ def create_report(*, title: str, rows: Sequence[Row], fmt: str = "csv") -> Report:
```

Legitimate `**kwargs`: transparent pass-through to a wrapped callable (decorators with `functools.wraps`, subclass `__init__` forwarding). Any function that *reads keys* out of `kwargs` with `.get` has a real signature it is hiding.

**Detect:** `rg -n 'kwargs\.get\(|kwargs\[' --type py`

### 4. Boolean Flag Parameter

`send_email(user, True, False)` at the call site tells the reader nothing.

```diff
# Bad — positional booleans
- def send_email(user, urgent, dry_run):

# Good — keyword-only makes every call site self-documenting
+ def send_email(user: User, *, urgent: bool = False, dry_run: bool = False) -> None:

# Better — when the flag selects a different behavior, it is two functions
+ def send_email(user: User) -> None: ...
+ def preview_email(user: User) -> str: ...
```

A flag that only tunes behavior stays a keyword argument. A flag whose branches share no code is two functions wearing one name — the `if flag:` at the top of the body is the tell.

**Detect:** `rg -n 'def \w+\([^)]*: bool' --type py` then the call sites: `rg -n '\((True|False)[,)]|, (True|False)[,)]' --type py`

### 5. Stateless Class

A class whose only state is the module it lives in.

```diff
# Bad — a namespace pretending to be an object
- class EmailValidator:
-     def __init__(self):
-         pass
-
-     def validate(self, address: str) -> bool:
-         return EMAIL_RE.fullmatch(address) is not None
-
- EmailValidator().validate(addr)

# Good — a function
+ def is_valid_email(address: str) -> bool:
+     return EMAIL_RE.fullmatch(address) is not None
```

A class earns its keep when it holds state, satisfies a `Protocol` with several members, or has to be swapped at runtime. `Manager`, `Helper`, `Handler`, `Util` with one method and an empty `__init__` is a namespace, and Python already has modules for that.

**Detect:** `rg -n -A3 'class \w+(Manager|Helper|Handler|Service|Util)' --type py`

### 6. Import-Time Side Effects

Importing the module opens a socket.

```diff
# Bad — import order decides whether the app boots; tests cannot import this
- engine = create_engine(os.environ["DATABASE_URL"])
- cache = Redis.from_url(os.environ["REDIS_URL"])
-
- def get_user(uid): ...

# Good — the caller decides when the connection happens
+ @lru_cache(maxsize=1)
+ def get_engine() -> Engine:
+     return create_engine(os.environ["DATABASE_URL"])
```

Import-time work makes tests import-order dependent, breaks `pytest --collect-only`, and turns a missing env var into a traceback at import instead of a clear startup failure. This is Python's version of the `init()` smell in [GOLANG.md](GOLANG.md).

**Detect:** `rg -n '^[a-z_]+ = (create_engine|Redis|Client|connect|Session|boto3\.client)\(' --type py`

### 7. Missing Type Hints on the Public API

```diff
# Bad — the caller has to read the body to learn the contract
- def parse(payload, strict=False):

# Good
+ def parse(payload: bytes, *, strict: bool = False) -> Invoice:
```

Hints on the public surface are documentation the checker enforces, and they are what makes a later refactor safe: renaming a field is a type error instead of a runtime surprise. Internal one-liners can stay bare; anything exported or crossing a module boundary should not.

**Detect:** `mypy --strict src/` — or narrow it with `ruff check --select=ANN201,ANN001 src/`

### 8. Duplicated Sync / Async Twins

Two implementations of one business rule, drifting apart.

```diff
# Bad — the rounding rule lives in two places and already disagrees
- def fetch_invoice(uid: str) -> Invoice:
-     row = db.execute(QUERY, uid).fetchone()
-     return Invoice(id=row[0], total=row[1] / 100)
-
- async def afetch_invoice(uid: str) -> Invoice:
-     row = await adb.execute(QUERY, uid)
-     return Invoice(id=row[0], total=round(row[1] / 100, 2))

# Good — one home for the rule; the twins carry I/O only
+ def _to_invoice(row: Row) -> Invoice:
+     return Invoice(id=row[0], total=round(row[1] / 100, 2))
+
+ def fetch_invoice(uid: str) -> Invoice:
+     return _to_invoice(db.execute(QUERY, uid).fetchone())
+
+ async def afetch_invoice(uid: str) -> Invoice:
+     return _to_invoice(await adb.execute(QUERY, uid))
```

The rule generalizes: when a sync and an async path must both exist, the shared part is everything that is not `await`. Push it into a pure function that neither owns.

**Detect:** `rg -o 'def a?(\w+)' -r '$1' --type py | sort | uniq -d | head -20` — names appearing twice are candidate twins.

## Python Refactoring Patterns

### Parametrized Tests

Eliminates duplicated test bodies — the Python analogue of table-driven tests in [GOLANG.md](GOLANG.md).

```diff
# Before: one function per case
- def test_add_positives():
-     assert add(1, 2) == 3
- def test_add_negatives():
-     assert add(-1, -2) == -3
- def test_add_zero():
-     assert add(0, 0) == 0

# After: one function, named cases
+ @pytest.mark.parametrize(
+     ("a", "b", "want"),
+     [(1, 2, 3), (-1, -2, -3), (0, 0, 0)],
+     ids=["positives", "negatives", "zero"],
+ )
+ def test_add(a: int, b: int, want: int) -> None:
+     assert add(a, b) == want
```

Keep `ids=` — without it a failure reports `test_add[1-2-3]` instead of `test_add[positives]`.

### Single Dispatch

Replaces an `isinstance` chain with type-based dispatch.

```diff
# Before: the chain every new shape has to be added to
- def area(shape):
-     if isinstance(shape, Circle):
-         return math.pi * shape.r ** 2
-     elif isinstance(shape, Rect):
-         return shape.w * shape.h
-     raise TypeError(f"unsupported shape {type(shape).__name__}")

# After: the base case is the error path; each type registers itself
+ @singledispatch
+ def area(shape: object) -> float:
+     raise TypeError(f"unsupported shape {type(shape).__name__}")
+
+ @area.register
+ def _(shape: Circle) -> float:
+     return math.pi * shape.r**2
+
+ @area.register
+ def _(shape: Rect) -> float:
+     return shape.w * shape.h
```

The base implementation keeps raising. Dispatch adds cases; it never removes the rejection of unsupported input.

### Context Manager for Repeated Setup/Teardown

Kills duplicated `try/finally` blocks.

```diff
# Before: the same acquire/release/log wrapper in three importers
- def import_users(path):
-     conn = pool.acquire()
-     start = time.perf_counter()
-     try:
-         ...
-     finally:
-         pool.release(conn)
-         log.info("import_users took %.3fs", time.perf_counter() - start)

# After: one context manager, three call sites
+ @contextmanager
+ def unit_of_work(name: str) -> Iterator[Connection]:
+     conn = pool.acquire()
+     start = time.perf_counter()
+     try:
+         yield conn
+     finally:
+         pool.release(conn)
+         log.info("%s took %.3fs", name, time.perf_counter() - start)
+
+ def import_users(path: Path) -> None:
+     with unit_of_work("import_users") as conn:
+         ...
```

The `finally` must stay inside the manager — that is the point. Releasing the connection is not optional cleanup that callers may forget.

### Protocol Instead of Inherited ABC

Decouples implementations from the module that defines the interface.

```diff
# Before: nominal typing — every implementation must import this module
- class Notifier(ABC):
-     @abstractmethod
-     def send(self, msg: str) -> None: ...

# After: structural typing — anything with the right shape qualifies
+ class Notifier(Protocol):
+     def send(self, msg: str) -> None: ...
+
+ def notify_all(notifiers: Iterable[Notifier], msg: str) -> None:
+     for n in notifiers:
+         n.send(msg)
```

`Protocol` is the Python counterpart of "accept interfaces, return structs": the consumer declares what it needs, and test doubles satisfy it without inheriting anything.

## Python Dead Code

Run the confidence tiers and the removal protocol from [DEAD_CODE.md](DEAD_CODE.md) — this section only names what makes Python noisier than the other languages.

`vulture` reports a symbol as unused whenever the only thing reaching it is a decorator, and Python frameworks reach almost everything that way: `@pytest.fixture` in `conftest.py`, `@app.route` / `@router.get`, `@celery.task`, `@field_validator`, Django signal receivers and `management/commands/` handlers, Alembic `upgrade`/`downgrade`. Add `tests/` as a scan root, generate the whitelist once with `vulture --make-whitelist src/ > whitelist.py`, and commit it.

```bash
vulture src/ tests/ whitelist.py --min-confidence 90
ruff check --select=F401,F811,F841,ARG,ERA001,RUF100 .
deptry .
```

`getattr(obj, name)` dispatch and `importlib.import_module` plugin loading defeat every static tool. Grep for both before deleting anything a tool flagged.

## Python Verification Commands

```bash
# Tests — the refactor safety net
pytest -q
pytest --cov=src --cov-report=term-missing     # confirm the refactored code is covered

# Type check before and after: the diff should be empty
mypy --strict . 2>&1 | tail -1

# Lint + format
ruff check .
ruff format --check .

# Confirm no unused imports or variables were introduced
ruff check --select=F401,F841,ARG .

# Complexity did not regress
radon cc -s -a src/ | tail -3

# Public API unchanged (run before and after, diff the output)
python -c "import mypackage, inspect; print(sorted(n for n in dir(mypackage) if not n.startswith('_')))"
```
