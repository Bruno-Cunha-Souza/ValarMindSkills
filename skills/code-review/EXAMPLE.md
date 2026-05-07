# Example — Go pull request review

End-to-end walkthrough of `@code-review` on a Go service pull request. The user invokes the skill on PR #248 of an internal Gin-based order service.

## Input

User prompt:

> /valarmindskills:code-review
>
> review PR #248 — adds a "list my orders" endpoint and a small refactor in the auth middleware

Repository state at `gh pr checkout 248`:

```text
.
├── api/
│   ├── handlers/
│   │   ├── order.go            (modified, +42 -3)
│   │   └── order_test.go       (modified, +12 -0)
│   ├── middleware/
│   │   └── auth.go             (modified, +6 -8)
│   └── store/
│       └── orders.go           (modified, +18 -0)
├── go.mod
└── go.sum
```

## Phase 0 — Detection

```text
language:    go
go-toolchain: 1.23 (from go.mod)
framework:   gin (github.com/gin-gonic/gin v1.10.0)
diff size:   4 files / 78 added / 11 deleted   (under cap; proceed)
PR base:     main
```

## Phase 1 — Static analysis sweep

Tool versions captured:

| Tool | Version | Result |
| --- | --- | --- |
| `golangci-lint` | 1.62.0 | 2 warnings (errcheck, ineffassign) |
| `staticcheck` | 2024.1.1 | clean |
| `gosec` | 2.21.4 | 1 finding (G104) |
| `govulncheck` | 1.1.4 | clean |
| `go vet` | bundled | clean |

Optional verification was not run; CI was already green on the PR branch.

All linter findings start at **Medium** severity per [SEVERITY_RUBRIC.md](references/SEVERITY_RUBRIC.md). Manual confirmation in Phase 2.

## Phase 2 — Manual read-through

Files reviewed in this order: `order_test.go` → `orders.go` (store) → `order.go` (handler) → `auth.go` (middleware).

Notes during the read:

- The new endpoint returns the caller's orders. The handler reads `c.Param("user_id")` and queries by it — a smell: the user is taken from the URL, not from the auth claims.
- The store query has no `LIMIT`. The user could legitimately have hundreds of orders, but no upper bound exists in the path.
- The logger in the auth middleware was changed to include `c.GetHeader("Authorization")` for "easier debugging".
- The test file adds two cases: happy path and 404. No test asserts that user A cannot read user B's orders.

## Phase 3 — Security review

OWASP API1 (BOLA) confirmed — `user_id` is taken from the URL, not from the JWT claims attached by the auth middleware. Matches the [GOLANG sweep](references/GOLANG.md) entry on missing ownership checks.

OWASP API8 (Security Misconfiguration) confirmed — Authorization header is logged verbatim. Matches the [GOLANG sweep](references/GOLANG.md) entry #16.

## Phase 4 — Performance review

The `SELECT * FROM orders WHERE user_id = $1` has no `LIMIT`. Pattern #2 in Phase 4 of the SKILL ("missing index hint / unbounded query"). Floor: Medium per matrix.

## Phase 5 — Test & maintainability

- Negative authorization path missing in tests (BOLA test).
- Handler is 41 lines — under the 60-line finding threshold but worth a refactor note (Info).

## Phase 6 — Output

```text
code-review: PR #248 — feat(orders): list my orders
  language(s):     go
  mode:            static review
  base:            main @ 9f4c2a1
  scope:           4 files / 78+ / 11-
  tools:           golangci-lint 1.62.0, staticcheck 2024.1.1, gosec 2.21.4,
                   govulncheck 1.1.4, go vet (bundled)
  verification:    not run (CI green)
  duration:        Phase 0–6 walked

Findings (ranked by severity, then by file):

| ID   | Sev      | Conf   | Risk     | File:Line                    | Title                                    |
| ---- | -------- | ------ | -------- | ---------------------------- | ---------------------------------------- |
| R001 | High     | High   | REVIEW   | api/handlers/order.go:54     | BOLA — user_id taken from URL, not JWT   |
| R002 | High     | High   | SAFE     | api/middleware/auth.go:31    | Authorization header logged verbatim     |
| R003 | Medium   | High   | SAFE     | api/store/orders.go:22       | Unbounded SELECT (no LIMIT)              |
| R004 | Medium   | Medium | SAFE     | api/handlers/order_test.go:14 | Missing BOLA negative test               |
| R005 | Low      | High   | SAFE     | api/handlers/order.go:48     | Stuttering name OrderOrderHandler        |
| I001 | Info     | High   | SAFE     | api/handlers/order.go:38-79  | Handler 41 lines — consider extracting   |

Detailed findings:

  R001 — BOLA — user_id taken from URL, not JWT  (Severity: High, Confidence: High, Risk: REVIEW)
    File:        api/handlers/order.go:54
    Code:
      | userID := c.Param("user_id")
      | orders, err := h.store.ListByUser(ctx, userID)
      | if err != nil {
      |     c.AbortWithStatus(500)
      |     return
      | }
      | c.JSON(200, orders)
    Impact:      Any authenticated user can list any other user's orders by
                 changing the URL path segment. CWE-639. OWASP API1:2023.
    Suggested fix (REVIEW):
    -   userID := c.Param("user_id")
    +   claims, ok := c.Get("claims")
    +   if !ok { c.AbortWithStatus(401); return }
    +   userID := claims.(*authn.Claims).UserID
        orders, err := h.store.ListByUser(ctx, userID)
    Verification: add an integration test in api/handlers/order_test.go
                  asserting a 403 (or 404 — pick one and document) when
                  user A requests /orders/<user-B-id>.
    Cross-link:  See @code-security-review (Go branch — references/golang/API.md
                 Phase 2) for full BOLA audit; the store layer has at least one
                 more endpoint with the same pattern (api/handlers/order.go:91).

  R002 — Authorization header logged verbatim  (Severity: High, Confidence: High, Risk: SAFE)
    File:        api/middleware/auth.go:31
    Code:
      | log.Info("auth ok", "header", c.GetHeader("Authorization"))
    Impact:      Bearer tokens written to logs persist in any sink (stdout,
                 ELK, Datadog). Replay risk if logs leak. CWE-532.
    Suggested fix (SAFE):
    -   log.Info("auth ok", "header", c.GetHeader("Authorization"))
    +   log.Info("auth ok", "subject", claims.Subject, "iss", claims.Issuer)
    Verification: re-run the request locally; verify token is absent from
                  log output.

  R003 — Unbounded SELECT (no LIMIT)  (Severity: Medium, Confidence: High, Risk: SAFE)
    File:        api/store/orders.go:22
    Code:
      | const q = `SELECT id, user_id, total, created_at
      |            FROM orders WHERE user_id = $1 ORDER BY created_at DESC`
      | rows, err := db.QueryContext(ctx, q, userID)
    Impact:      A user with many orders can exhaust handler memory. The
                 query also returns rows in unbounded order without
                 pagination, making the endpoint hard to consume.
    Suggested fix (SAFE):
    -   const q = `SELECT id, user_id, total, created_at
    -              FROM orders WHERE user_id = $1 ORDER BY created_at DESC`
    -   rows, err := db.QueryContext(ctx, q, userID)
    +   const q = `SELECT id, user_id, total, created_at
    +              FROM orders WHERE user_id = $1
    +              ORDER BY created_at DESC LIMIT $2 OFFSET $3`
    +   rows, err := db.QueryContext(ctx, q, userID, limit, offset)
    Verification: add a test that inserts 1500 orders for a user and
                  verifies the response carries at most `limit` rows.

  R004 — Missing BOLA negative test  (Severity: Medium, Confidence: Medium, Risk: SAFE)
    File:        api/handlers/order_test.go:14
    Code:
      | func TestListOrders_HappyPath(t *testing.T) { ... }
      | func TestListOrders_NotFound(t *testing.T) { ... }
    Impact:      The fix to R001 has no regression test. A future refactor
                 can re-introduce the BOLA without CI failure.
    Suggested fix (SAFE): add Test_ListMyOrders_RejectsOtherUser —
                  authenticated as user A, request user B's id, expect 403.

  R005 — Stuttering name OrderOrderHandler  (Severity: Low, Confidence: High, Risk: SAFE)
    File:        api/handlers/order.go:48
    Code:        type OrderOrderHandler struct { ... }
    Impact:      Name reads as "order order handler"; slows readers.
    Suggested fix (SAFE): rename to `Handler` (package context already says
                 `order`).

  I001 — Handler is 41 lines — consider extracting parsing
    File:        api/handlers/order.go:38-79
    Observation: Pagination parsing (limit/offset/sort) takes 14 lines at
                 the top of the handler. Extract into ParsePageQuery to
                 reuse across endpoints.

Summary:
  Critical: 0   High: 2   Medium: 2   Low: 1   Info: 1
  Blocking-merge findings: 2 (R001, R002)
  Suggested next steps:
    1. Author addresses R001 (REVIEW: middleware change) and R002 (SAFE).
    2. Author adds R004 test alongside the R001 fix.
    3. Author addresses R003 in the same PR or a follow-up.
    4. Re-review with `/valarmindskills:code-review` after fixes.
    5. Consider running @code-security-review (Go branch — references/golang/API.md
       Phase 2) across the rest of the order service to confirm no further BOLA cases.

Skill version: code-review @ HEAD
```

## What this example demonstrates

- Every finding has `path:line`, an exact code quote, an impact, a fix, a risk tag, and a confidence tag.
- Severity is calibrated by the rubric, not invented (R001 is High because single-resource BOLA has a High floor; R002 is High because CWE-532 + sensitive header).
- The skill **never** edits the code — the report contains diffs, but they are suggestions for the author.
- Cross-links steer the author to the right reference (`@code-security-review` Go branch — `references/golang/`) for follow-on work.
- Tool versions are captured so the review is reproducible.
