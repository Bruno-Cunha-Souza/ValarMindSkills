# Example — code-optimization on a FastAPI service

End-to-end walkthrough of the lifecycle: Phase 0 (Detect) → Phase 6 (Report). Sample project: a FastAPI 0.115 + SQLAlchemy 2.0 + PostgreSQL service with three known latent issues (N+1, slow JSON serialization, unpaginated endpoint).

## Project layout

```text
sample-fastapi/
├── pyproject.toml                  # requires-python = ">=3.13"; depends: fastapi, sqlalchemy, uvicorn[standard]
├── uv.lock
├── README.md                       # mentions p99 SLO < 200ms
├── api/
│   ├── main.py                     # FastAPI() with default JSONResponse
│   ├── users.py                    # GET /users — N+1 (lazy loads .profile per row)
│   ├── orders.py                   # GET /orders — returns all rows for user (no pagination)
│   └── deps.py
├── models/
│   ├── user.py
│   ├── profile.py
│   └── order.py
├── services/
│   └── export.py                   # CSV export with O(N²) string concat
└── tests/
    └── test_users.py
```

## Invocation

```text
User: /code-optimization
```

## Phase 0 — Detection (skill output)

```text
[Phase 0] Detecting project...
  language:     python
  framework:    fastapi 0.115
  pm:           uv
  runtime:      cpython3.13 (from .python-version)
  docs found:   README.md (mentions p99 SLO < 200ms)

  loading references:
    - PYTHON.md, DUPLICATION.md, RESOURCES.md, CALLS.md,
      SEVERITY_RUBRIC.md, REPORT_TEMPLATE.md
```

## Phase 1 — Scope triage

```text
[Phase 1] Counting files and LOC...
  files:        14 .py files
  LOC:          ~1850 lines (sloc)
  threshold:    ≤ 100 files / ≤ 20k LOC → full sweep OK

  scope:        full project
```

## Phase 2 — Static & profile sweep

```text
[Phase 2] Static perf sweep...
  $ ruff check . --select=PERF,SIM,B,C90
    services/export.py:88 PERF401: use `str.join` instead of `for`-loop concat

  $ mypy --strict .
    (clean)

  $ jscpd --min-lines 5 --min-tokens 50 .
    no clones over threshold

  $ ruff format --check .
    (clean)

  py-spy: skipped (no running process; user can opt in later).
  pytest-benchmark: skipped (no benchmarks defined).

  tool versions captured: ruff 0.7.4, mypy 1.13, jscpd 4.0.5
```

## Phase 3 — Manual read + pattern sweep

```text
[Phase 3] Reading hot paths...

  → api/users.py:42 — GET /users handler
    Found N+1 pattern: `for u in users: out.append(u.profile.name)`
    Draft finding O001 — Impact High (50ms p99 in test), SAFE, Effort S

  → api/orders.py:67 — GET /orders handler
    Returns `db.query(Order).filter(user_id=...).all()` — no LIMIT/cursor
    Draft finding O002 — Impact Critical (OOM risk for users with many orders), BREAKING, Effort M

  → api/main.py:18 — FastAPI() default JSONResponse
    Draft finding O003 — Impact High (orjson 2–3× faster), REVIEW, Effort S

  → services/export.py:88 — CSV export `csv += "..."` in loop
    Draft finding O004 — Impact Medium (O(N²)), SAFE, Effort S

  4 draft findings captured.
```

## Phase 4 — External validation (conditional)

```text
[Phase 4] Cross-validating High/Critical findings with Confidence < High...

  O001 (N+1, draft Confidence Medium) — High Impact → validate.
    WebSearch: "FastAPI SQLAlchemy 2.0 N+1 selectinload best practice"
    context7: /sqlalchemy/sqlalchemy §loading.html
      "selectinload() emits a SELECT IN (...) per relationship, no Cartesian"
    → Confidence promoted to High.

  O002 (no pagination, draft Confidence High) — already High, skip.

  O003 (default JSONResponse, draft Confidence Medium) — High Impact → validate.
    WebSearch: site:fastapi.tiangolo.com orjson
    → https://fastapi.tiangolo.com/advanced/custom-response/#orjsonresponse
      "ORJSONResponse is the fastest JSON response."
    → Confidence promoted to High.

  O004 (CSV concat) — Medium Impact, skip.

  2 findings cross-validated.
```

## Phase 5 — Classification

```text
[Phase 5] Tri-axis classification + quadrants...

  O001  Impact High      Risk SAFE       Effort S  →  QUICK WIN
  O002  Impact Critical  Risk BREAKING   Effort M  →  STRATEGIC
  O003  Impact High      Risk REVIEW     Effort S  →  QUICK WIN
  O004  Impact Medium    Risk SAFE       Effort S  →  POLISH
```

## Phase 6 — Report write (skill writes file)

```text
[Phase 6] Writing OPTIMIZATION_REPORT.md at project root...
  ✓ written (4.2 KB, 4 findings)
```

## Terminal summary printed to user

```text
code-optimization: main @ a1b2c3d
  language(s):    python
  framework:      fastapi 0.115
  runtime:        cpython3.13
  pm:             uv
  scope:          14 files / 1850 LOC  (full)
  tools:          ruff 0.7.4, mypy 1.13, jscpd 4.0.5
  validation:     2 findings cross-validated via web+context7
  report:         OPTIMIZATION_REPORT.md (written, 4.2 KB, 4 findings)

Findings summary (tri-axis):
  Impact       Critical: 1   High: 2   Medium: 1   Low: 0
  Effort       S: 3   M: 1   L: 0
  Quick wins (High impact + Low effort):   2  (O001, O003)
  Strategic  (High impact + Med/Large):    1  (O002)

Next steps:
  1. Read OPTIMIZATION_REPORT.md.
  2. Address Quick wins first (O001, O003) — total estimated effort: ~1.5h.
  3. Open ticket for Strategic (O002) — pagination migration.
  4. Re-run /code-optimization after fixes to confirm Impact resolution.
```

## Contents of `OPTIMIZATION_REPORT.md` (written file)

```markdown
# Optimization Report — sample-fastapi

> Generated by `@code-optimization` on 2026-05-23 against `main` @ `a1b2c3d`.
> Skill version: code-optimization @ <git rev of SKILL.md>

## Summary

| Axis  | Critical | High | Medium | Low |
| ----- | -------- | ---- | ------ | --- |
| Count | 1        | 2    | 1      | 0   |

**Quadrant counts:**
- Quick wins (High/Critical Impact × Small Effort): 2  (O001, O003)
- Strategic (High/Critical Impact × M/L Effort): 1  (O002)
- Polish (Med/Low Impact × Small Effort): 1  (O004)
- Deferred: 0

## Context

- **Language(s):** python (3.13)
- **Framework:** fastapi 0.115
- **Runtime:** cpython3.13
- **Package manager:** uv
- **Scope:** 14 files / 1850 LOC  (full sweep)
- **Base ref:** main @ a1b2c3d
- **Tools:** ruff 0.7.4, mypy 1.13, jscpd 4.0.5
- **External validation:** 2 findings (O001, O003) cross-validated via WebSearch + context7
- **Assumptions:** p99 SLO < 200ms inferred from README.md

## Findings

### Quick Wins

#### O001 — N+1 query in `GET /users`

| Axis       | Value |
| ---------- | ----- |
| **Impact** | High — 200 users → 201 queries (~50ms p99 added) |
| **Risk**   | SAFE — same response shape |
| **Effort** | S (< 1h) |
| **Confidence** | High |

**File:** `api/users.py:42`

**Code (verbatim):**
\`\`\`python
@router.get("/users")
def list_users(db: Session = Depends(get_db)):
    users = db.query(User).all()
    return [{"id": u.id, "profile_name": u.profile.name} for u in users]
\`\`\`

**Suggested fix (SAFE):**
\`\`\`python
from sqlalchemy.orm import selectinload

@router.get("/users")
def list_users(db: Session = Depends(get_db)):
    users = db.query(User).options(selectinload(User.profile)).all()
    return [{"id": u.id, "profile_name": u.profile.name} for u in users]
\`\`\`

**Validation:** context7 `/sqlalchemy/sqlalchemy` §loading.html.

**Verification:**
- pytest with `event.listen(Engine, "before_cursor_execute", counter)`; assert query count drops from 201 to 2.

---

#### O003 — Default `JSONResponse` (slow `json` module)

| Axis       | Value |
| ---------- | ----- |
| **Impact** | High — orjson is 2–3× faster |
| **Risk**   | REVIEW — affects all JSON responses |
| **Effort** | S (< 1h) |
| **Confidence** | High |

**File:** `api/main.py:18`

**Code (verbatim):**
\`\`\`python
app = FastAPI()
\`\`\`

**Suggested fix (REVIEW):**
\`\`\`python
from fastapi.responses import ORJSONResponse
app = FastAPI(default_response_class=ORJSONResponse)
\`\`\`

**Validation:** https://fastapi.tiangolo.com/advanced/custom-response/#orjsonresponse

**Verification:** load test with `wrk` before/after; expect 15–25% CPU drop on JSON-heavy endpoints.

---

### Strategic

#### O002 — `GET /orders` returns full table without pagination

| Axis       | Value |
| ---------- | ----- |
| **Impact** | Critical — OOM risk for users with many orders |
| **Risk**   | BREAKING — response shape changes |
| **Effort** | M (1–8h) |
| **Confidence** | High |

**File:** `api/orders.py:67`

**Code (verbatim):**
\`\`\`python
@router.get("/orders")
def list_orders(user_id: int, db: Session = Depends(get_db)):
    return db.query(Order).filter(Order.user_id == user_id).all()
\`\`\`

**Suggested fix (BREAKING):**
- Add cursor pagination (`?cursor=<order_id>&limit=100`, max 500).
- Migration: dual-version as `/v2/orders` with pagination; deprecate v1 over 1 release with `Deprecation` header.

**Verification:** load test with 100k-order user, assert constant memory and p99 < 200ms.

**Cross-link:** `@code-security-review` — same finding doubles as DoS surface (OWASP API4 Unrestricted Resource Consumption).

---

### Polish

#### O004 — O(N²) string concat in CSV export

| Axis       | Value |
| ---------- | ----- |
| **Impact** | Medium — O(N²) growth on export |
| **Risk**   | SAFE |
| **Effort** | S (< 30min) |
| **Confidence** | High |

**File:** `services/export.py:88`

**Code (verbatim):**
\`\`\`python
csv = ""
for row in rows:
    csv += ",".join(row) + "\n"
\`\`\`

**Suggested fix (SAFE):**
\`\`\`python
csv = "\n".join(",".join(row) for row in rows)
\`\`\`

**Validation:** none required — well-known antipattern (`ruff PERF401`).

---

## Methodology

- Phase 0–6 walked, full sweep.
- ruff `PERF` rules clean except for O004.
- mypy strict clean.
- 2 findings cross-validated via WebSearch + context7.

## Next steps

1. Address Quick Wins (O001, O003) — total estimated effort ~1.5h.
2. Open ticket for Strategic O002 with migration plan; aim for next sprint.
3. Re-run `/code-optimization` after fixes to confirm Impact resolution.
```

## What this example demonstrates

1. **Phase 0 detection** is silent and structured — language, framework, PM, docs.
2. **Phase 4 validation** is conditional — only High/Critical with Confidence < High trigger it; not every finding pays the latency cost of WebSearch + context7.
3. **Tri-axis classification** lets the user prioritize: O001 and O003 are Quick Wins (high impact, small effort); O002 is Strategic (needs sprint planning); O004 is Polish (opportunistic).
4. **Report is one file** at project root — versionable in git; replaces previous content on re-run.
5. **Terminal summary** is the at-a-glance; the file is the durable artifact.
6. **Cross-link to `@code-security-review`** appears on O002 because the same antipattern is a DoS surface.
