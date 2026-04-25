# Example — Go panic in production

End-to-end walkthrough of `@code-debugger` on a real-world panic in a Gin order service. The user invokes the skill after spotting the crash in the logs.

## Input

User prompt:

> /valarmindskills:code-debugger
>
> our /orders endpoint is crashing the API process — got this from prod logs:
>
> ```
> panic: runtime error: invalid memory address or nil pointer dereference
> [signal SIGSEGV: segmentation violation code=0x1 addr=0x10 pc=0x10dc6a4]
> goroutine 47 [running]:
> example.com/api/handlers.(*Order).List(0xc0001c4000, 0xc0002b0000)
>     api/handlers/order.go:54 +0x84
> github.com/gin-gonic/gin.(*Context).Next(...)
>     vendor/gin-gonic/gin/context.go:174
> ```

## Phase 0 — Capture & reproduce

### 0.1 Symptom captured

```text
TITLE:        Panic in /orders/:id: nil pointer in claims.UserID
SEVERITY:     Critical
ENVIRONMENT:
  Language:   go 1.23
  OS:         linux/amd64 (k8s pod)
  Branch:     main @ 4f8a1c9
  Deps:       gin v1.10.0

SYMPTOM:
  Error:      runtime error: invalid memory address or nil pointer dereference
  Stack:
    | api/handlers/order.go:54 example.com/api/handlers.(*Order).List
    | vendor/gin-gonic/gin/context.go:174 (*Context).Next
  Output:     expected 200 with orders / observed 500 + process panic
  Frequency:  always for unauthenticated calls to /orders/:id

REPRODUCTION:
  Command:    curl -s http://localhost:8080/orders/abc123 -i
  Last good:  4f8a1c9~1 (commit before "feat: add list-my-orders endpoint")
```

### 0.2 Reproduce locally

```bash
$ go test -run '^Test_Order_List$' -v ./api/handlers
=== RUN   Test_Order_List
--- FAIL: Test_Order_List (0.01s)
    panic: runtime error: invalid memory address or nil pointer dereference
        api/handlers/order.go:54
FAIL    example.com/api/handlers    0.024s
```

Reproduces locally on the first attempt. Move to Phase 1.

## Phase 1 — Isolate

### 1.1 Read the trace

Top user frame: `api/handlers/order.go:54`. Open it.

```go
// api/handlers/order.go:48-58
func (h *Order) List(c *gin.Context) {
    ctx := c.Request.Context()
    claims, _ := c.Get("claims")
    userID := claims.(*authn.Claims).UserID    // ← line 54
    orders, err := h.store.ListByUser(ctx, userID)
    if err != nil { c.AbortWithStatus(500); return }
    c.JSON(200, orders)
}
```

`claims` is the second return of `c.Get`, which returns `(any, bool)`. The bool is discarded with `_`. If the key is absent, `claims` is the zero `any` (`nil`), and `claims.(*authn.Claims)` is a type assertion on `nil` — which **does** succeed for type assertions to a pointer (yields `nil, false`), but the `_` discards the bool again. Then `claims.UserID` on `nil` *panics with nil pointer*.

### 1.2 Recent change check

```bash
$ git log --oneline -5 -- api/handlers/order.go api/router.go
4f8a1c9 feat: add list-my-orders endpoint
3a2bf01 chore: bump deps
2d44e88 refactor: split handlers package
1a0c3d2 feat: order CRUD scaffolding
```

Most recent commit added the endpoint. Read it.

```bash
$ git show 4f8a1c9 -- api/router.go
diff --git a/api/router.go b/api/router.go
@@ -85,6 +85,8 @@ func newRouter(...) *gin.Engine {
         orders.GET("/:id", h.Order.Get)
         orders.POST("",    h.Order.Create)
     }
+    // public endpoint for now — TODO: wire auth
+    r.GET("/orders/:id", h.Order.List)
     return r
 }
```

The new route is registered on `r` (root engine), **not** on `orders` (which is `r.Group("/orders").Use(authMiddleware)`). So the new endpoint runs without auth. The `claims` value is never set in the context, hence the nil panic.

## Phase 2 — Hypotheses

```text
H1: claims context value missing because middleware not registered for this route
    Test:     log c.Keys at handler entry
    Outcome:  CONFIRMED — c.Keys is empty for the failing request
    Status:   confirmed

H2: claims set but with nil pointer (e.g. token decode returned nil)
    Test:     trace the auth middleware on a healthy route
    Outcome:  REJECTED — healthy routes have claims set; the failing route
              never enters the middleware (verified with a printf at
              middleware/auth.go:18).
    Status:   rejected
```

H1 confirmed. Stop hypothesising and proceed to Phase 4.

## Phase 4 — Root cause

```text
Location:    api/router.go:88
Code (verbatim, before fix):
  | // public endpoint for now — TODO: wire auth
  | r.GET("/orders/:id", h.Order.List)
Why it fails: the route is registered outside the `authRequired` group, so
              `authMiddleware` never sets `c.Set("claims", ...)`. The
              handler at api/handlers/order.go:54 panics because it
              dereferences a nil claims pointer.
Sufficiency:  moving the route under the group makes the failing test pass
              (verified in Phase 6).
Necessity:    if the route were under the group, an unauthenticated request
              would receive 401 from the middleware before reaching the
              handler. The panic requires this misplacement.
Locality:     api/router.go:88 — single line.
```

Three tests pass. This is the root cause.

## Phase 5 — Fix

```text
Risk: REVIEW (touches auth wiring)

Diff:
  | --- a/api/router.go
  | +++ b/api/router.go
  | @@ -85,8 +85,8 @@
  |      orders.GET("/:id", h.Order.Get)
  |      orders.POST("",    h.Order.Create)
  | +    orders.GET("/mine", h.Order.List)
  |  }
  | -// public endpoint for now — TODO: wire auth
  | -r.GET("/orders/:id", h.Order.List)
  |  return r
```

Rationale: registering `List` under the existing `orders` group inherits
`authMiddleware`, which guarantees `claims` is set before the handler runs.
The route also moves to `/orders/mine` — `:id` would still allow user A to
read user B's orders by passing user B's id (separate BOLA finding; raised
to `@code-review`).

A second, defensive fix in the handler — even with auth in place, never
dereference an absent context value:

```text
  | --- a/api/handlers/order.go
  | +++ b/api/handlers/order.go
  | @@ -50,6 +50,10 @@
  |  func (h *Order) List(c *gin.Context) {
  |      ctx := c.Request.Context()
  | -    claims, _ := c.Get("claims")
  | -    userID := claims.(*authn.Claims).UserID
  | +    v, ok := c.Get("claims")
  | +    if !ok {
  | +        c.AbortWithStatus(401); return
  | +    }
  | +    userID := v.(*authn.Claims).UserID
```

Defensive fix is **SAFE**. Together the two changes prevent the panic from
recurring even if a future route is wired without the middleware.

## Phase 6 — Verify

### 6.1 Pre-fix vs post-fix

```text
PRE-FIX:
  $ go test -run '^Test_Order_List$' -v ./api/handlers
  --- FAIL: Test_Order_List (0.01s)
      panic: runtime error: invalid memory address or nil pointer dereference

POST-FIX:
  $ go test -run '^Test_Order_List$' -v ./api/handlers
  --- PASS: Test_Order_List (0.02s)
  PASS
  ok      example.com/api/handlers    0.041s

  $ go test -count=100 -run '^Test_Order_List$' ./api/handlers
  ok      example.com/api/handlers    0.842s   (100/100 pass)
```

### 6.2 Regression test added

```text
Path:     api/handlers/order_test.go
Name:     Test_Order_List_Returns401WhenClaimsMissing
Invariant: handler returns 401 (not 500, not panic) when claims absent
Pre-fix:   would have panicked (verified by reverting handler fix)
Post-fix:  returns 401
```

```go
func Test_Order_List_Returns401WhenClaimsMissing(t *testing.T) {
    h := newTestOrderHandler(t)
    w := httptest.NewRecorder()
    c, _ := gin.CreateTestContext(w)
    c.Request = httptest.NewRequest("GET", "/orders/mine", nil)
    h.List(c)
    if got := w.Code; got != 401 {
        t.Fatalf("expected 401, got %d", got)
    }
}
```

### 6.3 Prevention sweep

```bash
$ rg -n 'c\.Get\("[^"]+"\).*\n.*\.\(\*' --type go --multiline
api/handlers/order.go:54        (already fixed)
api/handlers/profile.go:32      ← same pattern, needs follow-up
```

Same-class site `api/handlers/profile.go:32` filed as a follow-up task.
Recommendation: add a `staticcheck` rule custom check or a unit test fixture
that verifies every authenticated route is registered under
`authMiddleware`, so the lint catches future occurrences.

## Output

```text
code-debugger: Panic in /orders/:id — nil claims pointer
  language:        go
  toolchain:       go 1.23
  reproducer:      go test -run '^Test_Order_List$' -v ./api/handlers
  duration:        Phase 0–6 walked

Symptom (Phase 0):
  Error:           runtime error: invalid memory address or nil pointer dereference
  Stack (top frames):
    | api/handlers/order.go:54  example.com/api/handlers.(*Order).List
    | vendor/gin-gonic/gin/context.go:174  (*Context).Next
  Reproduction:    curl http://localhost:8080/orders/abc123
  Frequency:       always for the new endpoint

Hypotheses tested (Phase 2):
  H1: claims context value missing because middleware not registered
      Test:     log c.Keys at handler entry
      Outcome:  CONFIRMED — c.Keys empty
  H2: claims set but with nil pointer
      Test:     printf at middleware/auth.go:18
      Outcome:  REJECTED — middleware never runs for the failing route

Root cause (Phase 4):
  Location:        api/router.go:88
  Code:
    | r.GET("/orders/:id", h.Order.List)
  Why it fails:    Route registered outside authRequired group; claims
                   context value never set; handler dereferences nil.
  Sufficiency:     Moving the route under the group fixes the panic.
  Necessity:       The bug requires this misplacement; otherwise the
                   middleware returns 401 before the handler runs.

Fix (Phase 5) — Risk: REVIEW + SAFE (two changes)
  Diff:            (see above; router.go and order.go)
  Rationale:       Restore auth invariant + harden handler against missing
                   claims even when middleware is present.

Verification (Phase 6):
  Pre-fix:         go test -run '^Test_Order_List$' ./api/handlers → FAIL
  Post-fix:        go test -run '^Test_Order_List$' ./api/handlers → PASS
  Repeat:          go test -count=100 ... → 100/100 PASS

Regression test:
  Location:        api/handlers/order_test.go
  Name:            Test_Order_List_Returns401WhenClaimsMissing
  Asserts:         handler returns 401 when claims absent

Prevention:
  Same-class sites swept:
    api/handlers/profile.go:32 — needs follow-up (same `c.Get("claims"), _`)
  Lint suggestion: custom staticcheck rule; or test that asserts every
                   authenticated route registers under authMiddleware.

Skill version: code-debugger @ HEAD
```

## What this example demonstrates

- **Phase 0 is non-negotiable** — symptom captured verbatim; reproduction confirmed before any hypothesis.
- **Hypotheses are tested cheaply** — H1 and H2 each falsified with a one-line `printf`, not with a debugger session.
- **Root cause passes three tests** — sufficiency, necessity, locality. Each spelled out explicitly.
- **The fix targets the root cause** (router wiring) **and** adds defence-in-depth (handler guard) — but does **not** clean up the surrounding code or refactor the package.
- **Verification quotes the actual command and output**, not paraphrase.
- **Prevention sweep** finds a sibling instance and files it as follow-up; the skill does not silently fix it in this PR.
