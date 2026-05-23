> Reference companion for the [code-optimization](../SKILL.md) skill.

# Python Performance Reference

Targets: CPython 3.13 (default), CPython 3.14, **CPython 3.14t** (free-threaded build, PEP 779). Frameworks: FastAPI 0.115+, Django 5.x, Flask 3.x. Package managers: uv, poetry, pip.

## 1. Tooling matrix

| Concern | Tool | Invocation |
| --- | --- | --- |
| Function-level CPU | `cProfile` (stdlib) | `python -m cProfile -o /tmp/prof.out app.py` ; visualize with `snakeviz /tmp/prof.out` |
| Sampling CPU (production-safe) | `py-spy` | `py-spy record -d 30 -o /tmp/profile.svg --pid $(pgrep -f uvicorn)` |
| Line-level | `line_profiler` | decorate with `@profile` + `kernprof -lv app.py` |
| Memory snapshot diff | `tracemalloc` (stdlib) | `tracemalloc.start(); snap1 = take_snapshot(); ...; snap2.compare_to(snap1, 'lineno')` |
| Memory in tests | `pytest-memray` | `pytest --memray --memray-bin-path=/tmp/memray.bin` ; flamegraph via `memray flamegraph` |
| Asyncio leak | `pytest-asyncio --strict-mode` + `asyncio.all_tasks()` | strict mode flags un-awaited coroutines |
| GIL contention | `py-spy --gil` | shows % time holding the GIL |
| Free-threaded testing | `python3.14t` | `uv run --python 3.14t pytest tests/` |
| Lint (perf-aware) | `ruff` | `ruff check --select=PERF,SIM,B,C90,UP .` (PERF + simplification + complexity + pyupgrade) |
| Type check (catches perf typing) | `mypy --strict` or `pyright` | both fine; mypy is reference |
| Duplication | `jscpd` | `jscpd src/` |
| Micro-bench | `pytest-benchmark` | `pytest --benchmark-only --benchmark-save=baseline` |

## 2. Hot-path antipatterns

### 2.1 Async pitfalls

| Anti-pattern | Fix |
| --- | --- |
| `for u in users: await fetch(u.id)` (sequential) | `await asyncio.gather(*(fetch(u.id) for u in users))` (cap with semaphore) |
| Sync I/O inside async handler (`requests.get`, `time.sleep`) | swap to `httpx.AsyncClient`, `asyncio.sleep`; if no async alt, `await asyncio.to_thread(blocking_fn)` |
| Forgetting to `await` a coroutine | `pytest-asyncio --strict-mode` flags; runtime warns with `coroutine '...' was never awaited` |
| `asyncio.create_task(...)` without storing the reference | task may be GC'd mid-flight — store in a set: `tasks = set(); t = asyncio.create_task(...); tasks.add(t); t.add_done_callback(tasks.discard)` |
| Blocking the event loop with CPU work | offload via `loop.run_in_executor` or `asyncio.to_thread` (3.9+); for CPU-heavy use `ProcessPoolExecutor` |

### 2.2 GIL and free-threaded 3.14t

CPython 3.13 has the GIL by default. CPython 3.14 ships with experimental free-threaded builds (`python3.14t`) per PEP 779 (officially supported in 3.14).

| Workload | GIL impact | Recommendation |
| --- | --- | --- |
| I/O-bound (HTTP, DB) | GIL released during I/O → near-linear scaling with threads | stay on 3.13/3.14 default; do not switch |
| CPU-bound pure Python | GIL serializes — multi-threading useless | C extensions (`numpy`, `polars`), `ProcessPoolExecutor`, or `python3.14t` build |
| CPU-bound with C ext | GIL released by ext (`numpy`, `pandas`) → threads scale | 3.13/3.14 default works |
| Mixed Python/C | partial scaling | benchmark `python3.14t` if scaling matters |

**Free-threaded caveats:**
- Single-threaded performance is ~5–10% slower than GIL build.
- Many C extensions need updates; check `pip-audit` / package compatibility before recommending.
- Use Hypothesis `RuleBasedStateMachine` for property-based race tests against 3.14t.

### 2.3 Memory and object overhead

| Anti-pattern | Fix |
| --- | --- |
| Plain class for high-frequency DTO (1000s/sec) | `__slots__` reduces instance dict overhead ~50% |
| `pydantic.BaseModel` with `Config.arbitrary_types_allowed = True` everywhere | Pydantic v2 is fast; keep schemas tight |
| `dict.copy()` in hot loop | shallow copy is cheap; **dict comprehension** for transformations |
| `list + list` for concatenation | `list.extend()` (in-place) |
| `str +=` in loop | `"".join(parts)` |
| `frozenset({...})` literal recreated per call | hoist outside the function or use module-level constant |
| `functools.lru_cache(maxsize=None)` on user-input function | unbounded cache = memory leak. Cap `maxsize` |
| `re.compile` per call inside hot loop | hoist regex to module level |

### 2.4 Serialization

| Library | When |
| --- | --- |
| `json` (stdlib) | default; OK for low-throughput |
| `orjson` | 2–3× faster on dict-heavy payloads, handles `datetime` / `UUID` natively |
| `ujson` | older alternative; orjson preferred |
| `msgspec` | even faster; supports schemas and binary format (MessagePack) |
| FastAPI: `ORJSONResponse` | swap `JSONResponse` default |

### 2.5 Resources / leaks

- `tracemalloc` snapshot diff in test fixture:

```python
import tracemalloc

@pytest.fixture
def alloc_diff():
    tracemalloc.start()
    snap = tracemalloc.take_snapshot()
    yield
    new = tracemalloc.take_snapshot()
    for stat in new.compare_to(snap, "lineno")[:10]:
        print(stat)
```

- `pytest-memray` for flamegraph attribution.
- `asyncio.all_tasks()` to count leaked tasks at end of test.

## 3. Framework-specific notes

### 3.1 FastAPI

- **Default JSON response is slow** — swap with `ORJSONResponse`:
  ```python
  app = FastAPI(default_response_class=ORJSONResponse)
  ```
- **`Depends` is cached per-request** — don't fear deep dep graphs; same-instance reuse is automatic.
- **Pydantic v2 (`model_dump(mode='json')`)** is much faster than v1's `.dict()`. Migrate any v1 leftovers.
- **`StreamingResponse`** for large payloads.
- **`uvicorn[standard]` (uvloop + httptools)** is 2× faster than the pure-Python default loop.
- **Background tasks** vs Celery: in-process `BackgroundTasks` blocks worker shutdown; use Celery / RQ / arq for durable work.

### 3.2 Django

- **N+1**: `select_related` (FK / OneToOne — single SQL JOIN) vs `prefetch_related` (M2M / reverse FK — second SQL). Combine: `.select_related('user').prefetch_related('orders')`.
- **`.only(...)` / `.defer(...)`** to limit columns when serializing only a subset.
- **`Prefetch(...)` with a queryset** to filter prefetched relations.
- **`assertNumQueries(n)`** in tests locks in the query count.
- **`bulk_create` / `bulk_update`** instead of `.save()` in loops.
- **`QuerySet.iterator(chunk_size=)`** for large result sets to avoid loading all in memory.
- **Async views** (`async def view(...)`) require async ORM — Django 5.x has it; mixing sync/async in handlers blocks the worker.

### 3.3 Flask + SQLAlchemy

- **SQLAlchemy 2.0 syntax** (`select(User)` + `session.execute(stmt).scalars().all()`) is faster than 1.x ORM.
- **`selectinload(User.orders)`** (preferred, separate SELECT, no Cartesian) vs `joinedload` (single JOIN, may inflate rows for one-to-many).
- **`scoped_session`** per request; `flask-sqlalchemy` handles this — don't roll your own.
- **`Flask-Caching`** with Redis backend for view-level caching.
- **`flask --debug` in prod** kills performance — assert `FLASK_DEBUG=0`.

## 4. Connection pools

- **SQLAlchemy `engine = create_engine(url, pool_size=20, max_overflow=10, pool_pre_ping=True, pool_recycle=3600)`** — `pre_ping` checks liveness before use; `recycle` defeats stale connections.
- **`asyncpg.create_pool(min_size=10, max_size=20)`** for async Postgres.
- **`httpx.AsyncClient`** as a singleton (or per-event-loop); never instantiate per request.

## 5. Profiling recipes

```bash
# cProfile + snakeviz
python -m cProfile -o /tmp/prof.out -m app.main
uv pip install snakeviz
snakeviz /tmp/prof.out  # opens browser

# py-spy live (no instrumentation)
py-spy top --pid $(pgrep -f uvicorn)

# py-spy record to flamegraph
py-spy record -d 30 -o /tmp/profile.svg --pid $(pgrep -f uvicorn) --subprocesses

# line_profiler — decorate target functions with @profile (no import)
kernprof -lv app/handlers.py

# tracemalloc on a script
PYTHONTRACEMALLOC=20 python app.py 2>&1 | tail -50

# pytest-memray
pytest tests/ --memray --memray-bin-path=/tmp/memray.bin
memray flamegraph /tmp/memray.bin

# Free-threaded test (3.14t)
uv python install 3.14t
uv run --python 3.14t pytest tests/concurrency/
```

## 6. Verification

- **`pytest-benchmark`** captures stats: `mean`, `stddev`, `ops/s`. Compare runs with `--benchmark-compare`.
- **`pytest --memray --memray-fail-if-grows-by=10MB`** to catch leaks in CI.
- **`py-spy top` in staging** is safe (sampling, no overhead) — gold standard for live findings.

## 7. Anti-patterns specific to Python perf findings

- **"Use `asyncio` everywhere"** — async adds overhead for short CPU-bound work. Benchmark before recommending the migration.
- **"Switch to PyPy"** — major undertaking; only worth it for long-running CPU-bound services. Most web frameworks have caveats. Demand a load-test baseline.
- **"Add Cython / Rust extension"** — Effort=L; only recommend after profile shows CPU dominated by a small set of pure-Python functions.
- **"Use `@functools.cache`"** — unbounded; cap with `lru_cache(maxsize=...)`.
- **"Just import `uvloop`"** — works on Linux/macOS; not on Windows native. Verify the deployment target.

## 8. References (external)

- CPython 3.14 What's New: https://docs.python.org/3.14/whatsnew/3.14.html
- PEP 779 (free-threaded build support): https://peps.python.org/pep-0779/
- FastAPI docs (cite via context7 `mcp__context7__resolve-library-id` for "FastAPI").
- SQLAlchemy 2.0 ORM loading docs.
- py-spy README on GitHub for live profiling guarantees.
