> Reference companion for the [ci-cd-generator](../SKILL.md) skill.

# Python Pipeline Template

Generated when Phase 0 detects `pyproject.toml`, `requirements.txt`, or `setup.py`. Defaults assume Python 3.13+ (3.14 latest stable). Package-manager detection: `uv.lock` → uv; `poetry.lock` → poetry; otherwise → pip+venv. Framework-aware snippets (FastAPI / Django / Flask) live inline — the pipeline shape is identical; only the test-helper and N+1 assertion differ.

For the runtime debugging and lint companion sweep, see [../../code-debugger/references/PYTHON.md](../../code-debugger/references/PYTHON.md) and [../../code-review/references/PYTHON.md](../../code-review/references/PYTHON.md). For the security-review lifecycle (Pydantic Settings, ASGI middleware, JWT alg confusion), see [../../code-security-review/references/python/API.md](../../code-security-review/references/python/API.md).

## Tooling matrix

| Concern | Tool | Action |
| --- | --- | --- |
| Toolchain | `actions/setup-python@v5` | `python-version-file: .python-version` or `pyproject.toml`; `cache: pip\|poetry` (uv handles its own cache) |
| PM (uv) | `astral-sh/setup-uv@v3` | `enable-cache: true`; orders of magnitude faster than pip |
| PM (poetry) | `snok/install-poetry@v1` | `virtualenvs-in-project: true` |
| Format | `ruff format --check` | exit non-zero on unformatted |
| Lint | `ruff check` | replaces flake8 + isort + pyupgrade; `--select S` enables bandit subset |
| Type check | `mypy --strict` or `pyright` | per-project preference |
| Security lint | `bandit -r .` | CWE-mapped SAST |
| Test + coverage | `pytest --cov` | `--cov-fail-under=60` (built into `pytest-cov`) |
| Async leak | `pytest-asyncio --strict-mode` | flags unawaited coroutines + leaked tasks |
| Free-threaded race | `python3.14t -m pytest` | opt-in, PEP 779 supported |
| Vulnerability scan | `pip-audit` + `safety` | both for redundancy (different DBs) |
| OSV cross-check | `osv-scanner` | `--lockfile=uv.lock` or `poetry.lock` |
| Build | `python -m build` or `uv build` | sdist + wheel |
| Release | `pypa/gh-action-pypi-publish@release/v1` | OIDC trusted publishing, gated on tag |

## Default `python-version` strategy

- Prefer `python-version-file: .python-version` or `python-version-file: pyproject.toml` over hardcoding — the project's `requires-python` directive is the source of truth.
- Matrix for libraries that need multi-version support: `python: ['3.13', '3.14', '3.14t']`. The `3.14t` entry tests under the free-threaded build (PEP 779 supported in 3.14).
- For application repositories, single version is sufficient.

## Package-manager detection

```bash
# Step 1 — pm
test -f uv.lock        && echo "pm: uv"
test -f poetry.lock    && echo "pm: poetry"
test -f Pipfile.lock   && echo "pm: pipenv"   # legacy
test -f requirements.txt && [ ! -f uv.lock ] && [ ! -f poetry.lock ] && echo "pm: pip"

# Step 2 — framework (single branch; affects test snippets, not workflow shape)
# Regex tolerates list-style deps in pyproject.toml (e.g. dependencies = ["fastapi>=0.115"])
# and plain `fastapi==X` in requirements.txt.
grep -qE '(^|[[:space:]"])fastapi[>=<~!"[:space:]]' pyproject.toml requirements.txt 2>/dev/null && echo "framework: fastapi"
grep -qE '(^|[[:space:]"])django[>=<~!"[:space:]]'  pyproject.toml requirements.txt 2>/dev/null && echo "framework: django"
grep -qE '(^|[[:space:]"])flask[>=<~!"[:space:]]'   pyproject.toml requirements.txt 2>/dev/null && echo "framework: flask"
```

The pipeline emits the same job graph regardless of framework; only the N+1 helper and Django settings module path change inline.

## Cache strategy

| PM | Cache action | Key |
| --- | --- | --- |
| pip | `actions/setup-python@v5` with `cache: pip` | `cache-dependency-path: requirements*.txt` |
| poetry | `actions/setup-python@v5` with `cache: poetry` | `cache-dependency-path: poetry.lock` |
| uv | `astral-sh/setup-uv@v3` with `enable-cache: true` | uv manages its own cache; do not enable pip cache concurrently |

## Canonical workflow

```yaml
name: ci

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

permissions:
  contents: read

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

env:
  COVERAGE_MIN: "60"
  COVERAGE_TARGET: "80"
  PYTHONDONTWRITEBYTECODE: "1"
  PIP_DISABLE_PIP_VERSION_CHECK: "1"

jobs:
  meta:
    name: actionlint
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: rhysd/actionlint@v1

  lint:
    needs: meta
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version-file: pyproject.toml
          cache: pip
      - name: install dev tools
        run: pip install ruff mypy
      - name: ruff format
        run: ruff format --check .
      - name: ruff check
        run: ruff check --output-format=github .
      - name: mypy
        run: mypy --strict .

  test:
    needs: meta
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version-file: pyproject.toml
          cache: pip
      - name: install project (with test extras)
        run: pip install -e '.[test]' || pip install -r requirements-dev.txt
      - name: pytest + coverage gate
        run: |
          pytest --cov --cov-report=xml --cov-report=term \
            --cov-fail-under="${COVERAGE_MIN}" \
            --strict-markers --strict-config \
            -W error::DeprecationWarning
      - name: warn under target
        if: success()
        run: |
          pct=$(python -c "import xml.etree.ElementTree as ET; print(int(float(ET.parse('coverage.xml').getroot().attrib['line-rate'])*100))")
          echo "coverage=${pct}%"
          if [ "${pct}" -lt "${COVERAGE_TARGET}" ]; then
            echo "::warning::coverage ${pct}% < target ${COVERAGE_TARGET}%"
          fi
      - uses: actions/upload-artifact@v4
        with:
          name: coverage-${{ github.sha }}
          path: coverage.xml

  security:
    needs: meta
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version-file: pyproject.toml
      - name: install scanners
        run: pip install bandit pip-audit safety
      - name: bandit
        run: bandit -r . -ll -q -x tests,build,dist
      - name: pip-audit
        run: pip-audit --strict --disable-pip
      - name: safety
        run: safety check --full-report
        continue-on-error: true   # safety v2 free-tier DB has stale data; do not block
      - uses: google/osv-scanner-action@v1.9
        with:
          scan-args: --recursive .

  build:
    needs: [lint, test, security]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version-file: pyproject.toml
      - name: build sdist + wheel
        run: |
          pip install build
          python -m build
      - uses: actions/upload-artifact@v4
        with:
          name: dist-${{ github.sha }}
          path: dist/
```

Required secrets: none for the canonical workflow.

## uv variant (replaces `setup-python` cache + install steps)

```yaml
- uses: astral-sh/setup-uv@v3
  with:
    enable-cache: true
    cache-dependency-glob: "uv.lock"
- run: uv sync --all-extras --dev
- run: uv run pytest --cov --cov-fail-under=${COVERAGE_MIN}
```

`uv` ships its own Python interpreter via `uv python install`; `setup-python` is not required when `uv` is the source of truth. Use one or the other, never both.

## Coverage gate

`pytest-cov` integrates `--cov-fail-under=N` directly — no separate awk gate needed (unlike Go). Two-tier reporting via the env vars:

- `COVERAGE_MIN=60` — pytest exits non-zero below this. Hard fail.
- `COVERAGE_TARGET=80` — post-step warning if coverage falls between min and target. Non-blocking annotation.

For Django projects, point `pytest-django` at the settings module:

```toml
# pyproject.toml
[tool.pytest.ini_options]
DJANGO_SETTINGS_MODULE = "myproject.settings.test"
addopts = "--cov --cov-fail-under=60 --cov-report=xml"
```

## N+1 detection templates

Three variants, all run inside the standard `test` job — no separate workflow needed.

### Django (built-in `assertNumQueries`)

```python
# tests/test_users_view.py
from django.test import TestCase

class UserListTests(TestCase):
    def test_list_at_most_3_queries(self):
        with self.assertNumQueries(3):
            self.client.get("/users/")
```

### FastAPI + SQLAlchemy 2.0 (event listener)

```python
# conftest.py
import pytest
from sqlalchemy import event
from sqlalchemy.engine import Engine

@pytest.fixture
def query_counter():
    counts = {"n": 0}
    def _count(conn, cursor, statement, params, context, executemany):
        counts["n"] += 1
    event.listen(Engine, "before_cursor_execute", _count)
    yield counts
    event.remove(Engine, "before_cursor_execute", _count)

# tests/test_users.py
def test_get_users_query_budget(client, query_counter):
    response = client.get("/users")
    assert response.status_code == 200
    assert query_counter["n"] <= 3, f"N+1 suspected: {query_counter['n']} queries (max 3)"
```

### Flask + SQLAlchemy

Same `event.listen(Engine, "before_cursor_execute", ...)` pattern as FastAPI. The pipeline is framework-agnostic on this axis.

## Memory leak / async leak detection

Three layers, pick by leak class:

| Layer | Tool | CI command | Catches |
| --- | --- | --- | --- |
| Async resource leak | `pytest-asyncio --strict-mode` | `pytest --asyncio-mode=strict` | unawaited coroutines, leaked tasks |
| Heap-growth diff | `tracemalloc` | snapshot + `compare_to()` in fixture | allocated-but-not-freed bytes between tests |
| Allocation profile | `pytest-memray` (Bloomberg) | `pytest --memray --memray-bin-path=memray.bin` | flamegraph of allocators; useful for fork-safe stress |

```python
# conftest.py — heap diff fixture
import gc, tracemalloc, pytest

@pytest.fixture(autouse=True)
def _heap_diff():
    gc.collect()
    tracemalloc.start()
    before = tracemalloc.take_snapshot()
    yield
    gc.collect()
    after = tracemalloc.take_snapshot()
    diff = after.compare_to(before, "lineno")[:5]
    leaked = sum(s.size_diff for s in diff if s.size_diff > 0)
    tracemalloc.stop()
    if leaked > 1_000_000:   # 1 MB threshold
        pytest.fail(f"heap grew by {leaked} bytes after test")
```

Workflow integration: install the test-time tooling once in the test job. Runtime memory limits (Docker `--memory`, Kubernetes `resources.limits.memory`) live in the deployment manifest, not the workflow.

## Free-threaded race testing (Python 3.14t, PEP 779)

3.14 ships the free-threaded build (`python3.14t`) as a supported, opt-in interpreter. GIL removal exposes races that were silently safe under the lock. Two integration points:

```yaml
race-pbt:
  needs: meta
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - uses: astral-sh/setup-uv@v3
      with:
        enable-cache: true
    - name: install 3.14t
      run: uv python install 3.14t
    - name: free-threaded race tests
      run: uv run --python 3.14t pytest tests/concurrency/ -W error
      continue-on-error: true   # remove once concurrency suite is mature
```

The companion test uses `hypothesis` stateful PBT:

```python
# tests/concurrency/test_counter.py
from hypothesis.stateful import RuleBasedStateMachine, rule, invariant
import threading

class CounterState(RuleBasedStateMachine):
    @rule()
    def inc_concurrent(self):
        ts = [threading.Thread(target=self.counter.add, args=(1,)) for _ in range(8)]
        for t in ts: t.start()
        for t in ts: t.join()

    @invariant()
    def balance_non_negative(self):
        assert self.counter.value >= 0
```

If the project does not yet have concurrency tests, the generator emits the job with `continue-on-error: true` and a header comment marking the gap.

## Release workflow (optional, PyPI trusted publishing)

When the user opts in, the generator emits `.github/workflows/release.yml` using OIDC (no PyPI token needed — configure trusted publishing once on PyPI):

```yaml
# .github/workflows/release.yml
name: release
on:
  push:
    tags: ['v*']

permissions:
  id-token: write   # required for OIDC -> PyPI
  contents: read

jobs:
  publish:
    runs-on: ubuntu-latest
    environment: pypi   # require manual approval per release
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version-file: pyproject.toml
      - name: build
        run: |
          pip install build
          python -m build
      - uses: pypa/gh-action-pypi-publish@release/v1
        with:
          packages-dir: dist/
          attestations: true   # 3.14+, sigstore attestations
```

Trusted publishing replaces long-lived `PYPI_API_TOKEN` secrets with short-lived OIDC tokens — set up once at <https://pypi.org/manage/account/publishing/>.

## Caveats

- `ruff` substitutes flake8 + isort + black + pyupgrade in one tool; do not pin minor versions (moves fast). Pin to `ruff~=0.x` and let dependabot keep it current.
- `mypy --strict` is unrealistic on legacy codebases; use `--strict-equality --warn-unused-ignores --warn-return-any` as an intermediate tier and ratchet up.
- `pytest --cov-fail-under` is built into `pytest-cov` — no awk gate needed (unlike Go).
- `safety check` v2 (free) is good enough for public CI; v3 (Safety DB API) needs `SAFETY_API_KEY`. The canonical workflow does **not** block on safety because its DB lags `pip-audit` by 1–2 weeks; treat it as a secondary signal.
- `uv` is in rapid iteration (0.5.x as of this writing). Pin the patch version in production workflows to avoid surprise behavior changes.
- `pytest-asyncio` mode must be `strict` (set in `pyproject.toml` `[tool.pytest.ini_options]`) — `auto` mode hides leaked tasks.
- For Django, run migrations as a separate test-job step before pytest (`python manage.py migrate --run-syncdb`) when the test DB is non-persistent.
- The free-threaded interpreter (`3.14t`) is single-threaded ~5–10% slower than `3.14`. Do not make it the default — gate it behind a dedicated `race-pbt` job.
