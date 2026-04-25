# Code Debugger — Evidence Format

> Reference companion for the [code-debugger](../SKILL.md) skill. Templates and rules for producing citable evidence at every step.

## Why evidence matters

LLM debuggers fail in two predictable ways:

1. **Confabulation** — invented stack frames, fabricated error messages, plausible-sounding but wrong root causes.
2. **Premature commitment** — the first hypothesis becomes "the answer" without falsification.

Evidence rules below are designed to make both failure modes visible. Every claim has a citation; every hypothesis has a falsification test; every fix has a verification command.

## Bug report template

Fill out before investigation starts. If a field is unknown, write `unknown` — never invent.

```text
TITLE:        <one-line summary>
SEVERITY:     <Critical | High | Medium | Low>
ENVIRONMENT:
  Language:   <go 1.23 | rust 1.81 | node 20.10 | bun 1.1.30>
  OS:         <darwin 24.4 | linux 6.6 | windows ...>
  Branch:     <git rev>
  Deps:       <relevant lockfile entries>

SYMPTOM:
  Error:      <verbatim error message>
  Stack:      <verbatim stack trace, all frames>
  Output:     <expected> ↔ <observed>

REPRODUCTION:
  Command:    <copy-paste-ready>
  Frequency:  <always | flaky N/N | once-off>
  Last good:  <git rev or "unknown">

CONTEXT:
  Recent changes: <git log --oneline -10 of the affected files>
  Related logs:   <verbatim excerpts, redacted>
  Related issues: <links>
```

## Evidence rules

### Rule 1 — Quote, do not paraphrase

Wrong:

> The handler crashes with a nil pointer error.

Right:

> ```
> panic: runtime error: invalid memory address or nil pointer dereference
> [signal SIGSEGV: segmentation violation code=0x1 addr=0x18 pc=0x1042c84]
> goroutine 47 [running]:
> example.com/api/handlers.(*Order).List
>   api/handlers/order.go:54 +0x84
> ```

Quotes are byte-for-byte. If the user pasted the trace, copy from the message; do not retype.

### Rule 2 — Cite, always

Every claim about the code must point to `path/to/file.ext:LINE`. Without that, the claim is conjecture.

Wrong:

> The middleware doesn't run on this route.

Right:

> The middleware does not run on this route. `api/router.go:88` registers `r.GET("/orders/:id", handlers.Order.Get)` outside the `authRequired` group declared at `api/router.go:50–86`.

### Rule 3 — Show the command, show the output

Wrong:

> The test passes after the fix.

Right:

> ```
> $ go test -run '^Test_ListMyOrders$' -count=10 -v ./api/handlers
> === RUN   Test_ListMyOrders
> --- PASS: Test_ListMyOrders (0.04s)
> === RUN   Test_ListMyOrders
> --- PASS: Test_ListMyOrders (0.03s)
> ...
> PASS
> ok      example.com/api/handlers    0.347s
> ```

The command must be **copy-paste-ready**. The output must be the actual run; do not synthesize.

### Rule 4 — Mark hypothesis status explicitly

Each hypothesis is `open`, `confirmed`, or `rejected`. Status changes only when evidence lands.

```text
H1: claims context value missing on this route
    Evidence-for:    stack trace top frame is `claims.(*Claims).UserID`
    Evidence-against: middleware order in router.go:42 looks correct
    Test:            log c.Keys at handler entry
    Outcome:         CONFIRMED — c.Keys = []; route is outside authRequired group
    Status:          confirmed
```

### Rule 5 — Drop falsified hypotheses

Once `Evidence-against` clearly disproves a hypothesis, status flips to `rejected` and the hypothesis is closed. Do not "save" it as backup. The hypothesis log records what was tried and what was learned.

### Rule 6 — Distinguish observation from interpretation

- **Observation** — what the tool / log / code says.
- **Interpretation** — what you think it means.

Example:

> Observation: `c.Get("claims")` returns `(nil, false)` when the handler runs.
>
> Interpretation: the middleware that sets the value did not run for this request.

Mixing the two leads to "I observed that the middleware is broken" — which is not what was observed.

### Rule 7 — Never invent

If the user has not pasted a stack trace, do not write one. If a tool was not run, do not present its output. If a CVE was not in the scanner output, do not cite it. The skill **must ask** when evidence is missing.

## Hypothesis log format

Maintain in the working notes; copy a condensed version into the final report.

```text
HYPOTHESIS LOG — <bug title>
Started: <YYYY-MM-DD HH:MM>

H1: <claim>
    Test:      <action>
    Cost:      <minutes>
    Evidence:  <observations>
    Outcome:   <confirmed | rejected | open>
    Closed:    <YYYY-MM-DD HH:MM>

H2: ...

CONFIRMED ROOT CAUSE: <H#>
```

## Fix evidence

A fix needs three artefacts in the report:

1. **The diff** — unified diff with 3 lines of context, applied to the verbatim source.
2. **The pre-fix verification** — running the failing test produces the same failure as Phase 0.
3. **The post-fix verification** — running the failing test passes.

```text
PRE-FIX:
  $ go test -run '^Test_ListMyOrders$' ./api/handlers
  --- FAIL: Test_ListMyOrders (0.02s)
      order_test.go:34: expected 200, got 500

POST-FIX:
  $ go test -run '^Test_ListMyOrders$' ./api/handlers
  --- PASS: Test_ListMyOrders (0.02s)
```

If the failure is intermittent, the post-fix run must be repeated and the count reported:

```text
  $ go test -run '^Test_ListMyOrders$' -count=200 ./api/handlers
  --- PASS: 200/200 runs
```

## Regression test format

The regression test must:

- Be located in the test file matching the production code.
- Have a name that reads as a sentence (`Test_ListOrders_RejectsOtherUserId`).
- Assert the **invariant**, not the implementation.
- Fail on the pre-fix code (verify by reverting the fix temporarily; or by reasoning if the test expresses a violated invariant).

```text
REGRESSION TEST:
  Path:     api/handlers/order_test.go
  Name:     Test_ListMyOrders_RejectsUnauthenticatedRequest
  Invariant: handler returns 401 when no claims are present in the context
  Pre-fix:   would have returned 500 (panic)
  Post-fix:  returns 401
```

## Anti-patterns the LLM debugger must refuse

- "Probably it's …" — debugging is not probabilistic without evidence.
- "Try changing X and see" — random changes invalidate every previous hypothesis.
- "This usually means Y" — usual is not specific to this bug.
- "Stack trace says Z" without quoting the trace — write the trace.
- "Test passes" without showing the command and output — show it.
- "The fix is …" without first showing the failing code — show before, then after.
- "Let me also clean up …" while debugging — scope creep masks the root cause.
- "I'll add error handling everywhere" — that is a refactor, not a fix.
- "Add a try/catch and log it" as a fix — that is a workaround. State explicitly when proposing a workaround vs a fix.
