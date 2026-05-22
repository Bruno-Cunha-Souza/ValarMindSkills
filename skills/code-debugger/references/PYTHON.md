# Code Debugger — Python Reference

> Reference companion for the [code-debugger](../SKILL.md) skill. Python-specific debugging techniques, command snippets, and bug-class playbooks for CPython 3.13 / 3.14. Pairs with [code-review/references/PYTHON.md](../../code-review/references/PYTHON.md) (static smell catalogue) and [code-security-review (Python branch)](../../code-security-review/references/python/API.md) (security-driven runtime issues).

## Tools

| Tool | Purpose | Install / Use |
| --- | --- | --- |
| `pdb` / `breakpoint()` | Step debugger built-in | bundled (`python -m pdb script.py`) |
| `python -m pdb -p <PID>` | Remote attach to running process | Python 3.14+ (PEP 768, `sys.remote_exec`) |
| `python -X faulthandler` | Crash trace on segfault / fatal signal | bundled |
| `python -X tracemalloc=10` | Allocation tracking + snapshot diff | bundled |
| `python -X dev` | Dev mode: warnings + asyncio debug | bundled |
| `PYTHONASYNCIODEBUG=1` | Slow callback + leaked coroutine warnings | env var |
| `PYTHONBREAKPOINT=ipdb.set_trace` | Override `breakpoint()` target | env var |
| `py-spy` | Sampling profiler (CPU, attach to PID, flame graph) | `pipx install py-spy` |
| `viztracer` | Execution trace + flamegraph + viewer | `pipx install viztracer` |
| `cProfile` + `snakeviz` | Deterministic profile + UI | bundled / `pipx install snakeviz` |
| `aiomonitor` / `aiodebug` | Live async runtime introspection | `pip install aiomonitor` |
| `pytest` + `pytest-asyncio` + `pytest-repeat` | Test runner + async + flake hunt | per-project |
| `gdb` / `lldb` (with `python3-dbg`) | C-extension segfault, ref-count corruption | system package |
| `sys.monitoring` (PEP 669) | Low-overhead trace API (Python 3.12+) | bundled |
| `annotationlib` (PEP 749) | Inspect deferred annotations | bundled (3.14+) |

## Quick reproducer commands

```bash
# Run a single test
pytest path/to/test_module.py::TestClass::test_name -v
pytest -k 'test_name and not slow' -v
pytest --lf                                     # last failed only

# Repeat (flake hunt) — requires pytest-repeat
pytest path/to/test_module.py::test_name --count=200
pytest -p no:randomly path/to/test_module.py    # disable test-order randomization

# Run with breakpoints / pdb
python -m pdb script.py
pytest --pdb path/to/test_module.py             # drop into pdb on failure
PYTHONBREAKPOINT=ipdb.set_trace python script.py

# Remote attach (Python 3.14+, PEP 768)
python -m pdb -p <PID>                          # attach to a running process

# Dev mode + warnings + asyncio debug
python -X dev script.py
python -X dev -W error script.py                # turn DeprecationWarning into error
PYTHONASYNCIODEBUG=1 python script.py
PYTHONDEVMODE=1 python script.py

# Crash diagnostics
python -X faulthandler script.py
python -X tracemalloc=10 script.py              # track top-10 alloc frames

# Async debug
python -c "import asyncio; asyncio.run(main(), debug=True)"

# Free-threaded build (Python 3.14, PEP 779)
python3.14t script.py                           # GIL disabled
python3.14  script.py                           # GIL enabled (default)

# JIT (Python 3.13 experimental, opt-in build)
PYTHON_JIT=1 python3.13 script.py
```

## Bug-class playbooks

### Unhandled exception / `AttributeError: 'NoneType' object has no attribute 'X'`

Pattern: traceback ends with `AttributeError`, line shows `obj.X` where `obj` is `None`.

Procedure:

1. Read the traceback top-down — first non-stdlib frame is the failure site.
2. At that line, log or `pp` the suspect value before the access: `print(repr(obj))`.
3. Common roots: function returned `None` implicitly (no `return`), `.get(key)` on missing key, `find_one`/`find_first` returned `None`, optional field unset.
4. Fix at the producer (return a proper sentinel or raise) or at the consumer (`if obj is None: …` guard); do not paper over with `obj or default` unless `default` is semantically correct.

### `TypeError` from type confusion at a boundary

Pattern: `TypeError: unsupported operand`, `TypeError: '<' not supported between …`, `TypeError: argument of type 'NoneType' is not iterable`.

Procedure:

1. Boundary is where untyped data enters the typed core: `request.json()`, env vars (`os.environ["X"]`), CLI args, ORM raw rows.
2. Add a runtime validator at the boundary — pydantic v2 (`Model.model_validate(...)`), msgspec, attrs with converters.
3. Re-run; the new error pinpoints the offending field with field name + path.

### `RecursionError: maximum recursion depth exceeded`

Procedure:

1. Stack itself names the recursive frame.
2. Common roots: missing base case, `__repr__`/`__str__` calling itself (e.g., dataclass containing self), property accessor calling itself, `__getattr__` re-triggering attribute lookup.
3. Walk the recursion at the top frame with `pdb` — set `sys.setrecursionlimit` temporarily to catch sooner if needed.

### Mutable default argument

Pattern: function called multiple times shares state across calls.

```python
def append_item(item, items=[]):     # BUG — list is created once at def time
    items.append(item)
    return items
```

Fix: use `None` sentinel + create inside the body. Same trap with `dataclasses.field(default=[])` (use `default_factory=list`) and `dict`/`set`.

### `is` vs `==` singleton confusion

Pattern: `x is True` / `x is 0` / `x is "abc"` works in some CPython versions and fails in others (interning is an implementation detail).

Fix: `==` for equality, `is None` / `is not None` only for singletons (`None`, `True`, `False`, sentinel objects).

### Memory growth / reference cycle

Procedure:

1. Run under `python -X tracemalloc=10` and snapshot before/after a representative load:
   ```python
   import tracemalloc, gc
   tracemalloc.start(10)
   snap1 = tracemalloc.take_snapshot()
   run_load()
   gc.collect()
   snap2 = tracemalloc.take_snapshot()
   for stat in snap2.compare_to(snap1, "lineno")[:20]:
       print(stat)
   ```
2. Top growth source by file:line is the lead.
3. Common roots: long-lived dict cache without bound, request-scoped object held by a module-level container, `__del__` blocking gc (cycles + `__del__`), `weakref` not used where it should be, closures capturing large state.
4. `gc.get_referrers(obj)` and `objgraph.show_backrefs(obj)` (third-party) trace ownership.

### Async deadlock / `coroutine '...' was never awaited`

Pattern: `RuntimeWarning: coroutine '<func>' was never awaited` or hang.

Procedure:

1. Run with `python -X dev` or `PYTHONASYNCIODEBUG=1` — warnings become traceable.
2. Add `asyncio.run(main(), debug=True)` at entry.
3. Common roots: forgotten `await`, `asyncio.gather` with a coroutine that holds a lock around an `await`, sync `Lock` used in async code (use `asyncio.Lock`), nested `asyncio.run()` calls.
4. Inspect live state: `aiomonitor.start_monitor(loop=asyncio.get_event_loop())` exposes `ps`, `where`, `signal SIGSEGV`-style commands over a telnet socket.

### Async task leak

Pattern: `asyncio.all_tasks()` count grows; `python -X dev` warns "Task was destroyed but it is pending!".

Procedure:

1. At a steady state, snapshot `asyncio.all_tasks()` — names + coroutine state.
2. Common roots: `asyncio.create_task(...)` without holding the task reference (gc collects it mid-run), background task in long-lived service never shut down on cancellation.
3. Keep a strong reference: `self._bg.add(task); task.add_done_callback(self._bg.discard)`.

### Blocking call inside a coroutine

Pattern: latency spikes; `loop.slow_callback_duration` warnings; event loop "stalls".

Procedure:

1. `asyncio.run(main(), debug=True)` and watch for `Executing <Task pending …> took N seconds`.
2. Common roots: `time.sleep`, `requests.get` (sync HTTP), `open(...).read()` on large files, `subprocess.run`, blocking ORM call, sync `socket.recv`.
3. Fix: replace with async equivalents (`asyncio.sleep`, `httpx.AsyncClient`, `aiofiles`, `asyncio.subprocess`, async ORM) — or wrap in `loop.run_in_executor(None, sync_fn)` if no async client exists.

### Free-threaded race (Python 3.13t / 3.14t)

The GIL no longer serializes bytecode in the free-threaded build. Races previously hidden surface immediately.

Procedure:

1. Confirm the build: `python -VV` should show `experimental free-threading build` or `free-threading build`.
2. Reproduce on `python3.14t` (supported per PEP 779) or `python3.13t` (still experimental — pre-PEP 779) under load — if the bug disappears on `python3.14`, the GIL was hiding the race.
3. Audit shared mutable state: module-level dicts, class attributes, `collections.deque` shared across threads.
4. Fix: `threading.Lock` / `RLock` around the critical section; replace with thread-safe primitives (`queue.Queue`, `collections.Counter` is **not** atomic, `dict.setdefault` is not atomic on free-threaded).
5. Hunt with `python -X tracemalloc` for divergent allocations; structured logging with thread IDs (`threading.get_ident()`) traces ordering.

### Flaky test

Procedure:

1. Reproduce rate: `pytest path::test --count=200`.
2. Common roots:
   - **Order dependency** — install `pytest-randomly`; re-run with seed; if it fails only under specific order, fixture leaks state.
   - **Time** — `freezegun.freeze_time` or `pytest-freezer`; assert ranges, not exact timestamps.
   - **Real network** — `pytest-httpx` / `responses` / `vcrpy` to mock.
   - **Module-level state** — `monkeypatch` it; or restructure to dependency-inject.
   - **Concurrent tests sharing tmp dir** — `tmp_path` fixture per test.
   - **Async warning shadowing** — capture `warnings.filterwarnings("error", category=RuntimeWarning)` in the test.

### Wrong type at runtime (type hints lied)

Type hints are not runtime checks. If a runtime value disagrees with its annotation, the cause is upstream — `Any` leakage, `cast(...)`, JSON without validation, ORM row passed straight through, `# type: ignore` covering a real bug.

Procedure:

1. Add a `pydantic`/`msgspec`/`attrs` validator at the boundary.
2. The validator's `ValidationError` pinpoints the offending field with its path.
3. Fix the producer (correct annotation, parse upstream) or the consumer (validate at entry).

### Deferred annotation resolution failure (PEP 649 / 749 — default in 3.14)

Pattern: `NameError` only at `inspect.get_annotations(obj)` or `typing.get_type_hints(obj)` time, not at import; or sudden `RecursionError` from forward-ref resolution.

Procedure:

1. Check the Python version: 3.14 evaluates annotations lazily by default; legacy `from __future__ import annotations` is no longer required (and ignored when both are set).
2. Use `inspect.get_annotations(obj, format=annotationlib.Format.STRING)` to fetch annotations as strings without resolution.
3. Use `format=annotationlib.Format.FORWARDREF` to get unresolved `ForwardRef` placeholders for cycles.
4. Fix: ensure the referenced name is importable in the module's namespace at lookup time; avoid mutual recursion via forward refs.

### Generator / iterator exhaustion

Pattern: second iteration over a generator yields nothing; `list(gen)` is empty.

Procedure:

1. Confirm with `pdb` that the generator was consumed earlier (`itertools.tee` accidentally exhausting; reuse after `for` loop).
2. Fix: materialize once into `list(...)` or convert to a callable that returns a fresh generator on each call.

### C-extension segfault / ref-count corruption

Pattern: hard crash (no Python traceback), `Segmentation fault`, or `Fatal Python error`.

Procedure:

1. Enable `python -X faulthandler` to get a Python stack at crash time.
2. Reproduce under `gdb python3 -ex 'r script.py'` (install `python3-dbg` for symbol info).
3. At crash: `(gdb) py-bt` gives Python stack; `(gdb) bt full` gives C stack.
4. Common roots: missing `Py_INCREF`/`Py_DECREF` pair in C extension, GIL released over an API call that needs it, free-threaded build with C extension not declaring `Py_mod_gil = Py_MOD_GIL_NOT_USED` (forces GIL re-enable — also a perf surprise).
5. Run with `PYTHONMALLOC=debug` to catch buffer overruns; `valgrind --tool=memcheck python3 ...` for heap corruption (slow but exhaustive).

## pdb / pdb -p quick recipe

```bash
# Start with breakpoint on entry
python -m pdb script.py
# Inside:
#   b path/to/file.py:42        # set breakpoint
#   c                            # continue
#   pp obj                       # pretty-print
#   p obj.attr                   # print
#   l                            # list source
#   w / where                    # show stack
#   u / d                        # up / down frames
#   interact                     # drop into a Python REPL with current locals
#   b file:line, condition       # conditional breakpoint
#   q                            # quit

# Remote attach (Python 3.14+, PEP 768)
python -m pdb -p 12345           # attach to PID 12345
# The target process must be running CPython 3.14+. sys.remote_exec writes a
# path to a file containing pdb commands into the target's memory; safer than
# injecting code directly.

# pytest integration
pytest --pdb                     # drop into pdb on failure
pytest --trace                   # drop in at the start of every test

# Trigger from code
breakpoint()                     # hits PDB by default; respects PYTHONBREAKPOINT
```

## py-spy / viztracer / cProfile quick recipe

```bash
# Live top — like htop for Python
py-spy top --pid 12345

# Record a flamegraph
py-spy record -o flame.svg --pid 12345
py-spy record -o flame.svg -- python script.py

# Dump current stack of every thread (great for hangs)
py-spy dump --pid 12345

# viztracer — execution trace + interactive HTML viewer
viztracer script.py              # produces result.json + result.html
viztracer --max_stack_depth 10 script.py
vizviewer result.json            # open viewer

# Deterministic profile (slower but exact)
python -m cProfile -o out.prof script.py
snakeviz out.prof                # browser UI

# Async-aware timing
PYTHONASYNCIODEBUG=1 python script.py
# slow_callback_duration logs in stderr when a callback exceeds 0.1s
```

## Python 3.13 / 3.14 specific notes

- **3.14 is the latest stable release** (October 2025; 3.14.5 is the current point release). Distros and tooling defaults lag — Ubuntu 24.04 LTS ships 3.12, Homebrew defaults to 3.13 in early 2026. Treat `python --version` as project-dependent, not 3.14 by assumption.
- **Free-threaded build (`python3.14t`)** — PEP 779 promoted from experimental to supported. The interpreter omits the GIL; threads run Python code on multiple cores in one process. **Trade-off:** single-threaded code runs ~5–10% slower; many C extensions need `Py_mod_gil = Py_MOD_GIL_NOT_USED` declared or they force the GIL back on at import. Always benchmark on both builds before deploying.
- **PEP 768 remote pdb (`python -m pdb -p PID`)** — only works on 3.14+. The target process is paused via `sys.remote_exec`, given the path to a file holding pdb commands, then resumed. Safer than injecting raw code.
- **PEP 649 / 749 deferred annotations** — default on 3.14. `from __future__ import annotations` is now redundant. Investigate annotation resolution with `inspect.get_annotations(obj, format=...)` and the new `annotationlib` module (formats: `VALUE`, `FORWARDREF`, `STRING`).
- **PEP 750 t-strings** — new literal type, distinct from f-strings. The `t""` literal produces a `Template` object holding interpolation segments without rendering, enabling safer downstream rendering (SQL, HTML, shell). Treat suspect template renderers (logging, SQL builders) as candidates for migration.
- **Experimental JIT (3.13, opt-in build)** — enable with `--enable-experimental-jit` at build time and `PYTHON_JIT=1` at runtime. Tier 2 micro-op interpreter + copy-and-patch JIT. Treat as a primary suspect for release-vs-debug-style bugs that disappear when `PYTHON_JIT=0`.
- **`sys.monitoring` (PEP 669, 3.12+)** — preferred over `sys.settrace` for profilers, debuggers, and coverage tools. Low overhead; per-tool event masks; survives optimization passes the JIT may introduce.
- **`asyncio.eager_task_factory`** — opt-in synchronous-first task scheduling reduces hot-path latency when the coroutine doesn't actually await. Use when profiles show task creation overhead dominating.

## Common false leads

- **`DeprecationWarning` from a dependency** — not your bug; pin or upgrade the dep separately.
- **`pytest` collection warnings** — usually fixture import issues, not the bug under investigation.
- **`RuntimeWarning: coroutine '...' was never awaited` from a pytest fixture** — often the fixture itself returns the wrong thing (returned the coroutine instead of awaiting and returning the value). The bug is in the fixture, not the system under test.
- **Lint complaint inside the failing area** — lead, not cause; the linter cannot reason about runtime.
- **`# type: ignore` near the failing line** — the assertion lied; the runtime value is what matters.
- **A `print` inside a test that's never visible** — pytest captures stdout by default. Use `-s` to disable capture or `caplog` for log assertions.

## Hand-off triggers

- API runtime issue with security implication → `@code-security-review` (Python branch — `references/python/`).
- Refactor / clean-code root cause → `@clean-code`.
- Static review of code that isn't failing → `@code-review` ([references/PYTHON.md](../../code-review/references/PYTHON.md)).
- Performance regression at the framework layer (FastAPI/Django/Flask) → `@code-review` (`references/PYTHON.md`) performance sweep, then `@code-security-review` (Python branch) Phase 5 if the regression has an auth/SSRF component.
