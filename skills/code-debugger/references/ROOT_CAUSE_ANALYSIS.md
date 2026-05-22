# Code Debugger — Root Cause Analysis

> Reference companion for the [code-debugger](../SKILL.md) skill. Procedures and tests for distinguishing symptoms from root cause.

## The three tests

A claim is a root cause only when **all three** hold. If any fails, you have a contributing factor or a symptom.

### Sufficiency

Fixing this alone makes the bug stop. Falsify by mentally (or really) applying the fix and asking: would the test still fail? If yes, sufficiency fails.

### Necessity

Without this code, the bug would not occur. Falsify by asking: if I remove this code path, is the bug still possible? If yes, necessity fails — the cause is upstream.

### Locality

The cause is in a specific span you can quote `path:line`–`path:line`. If the cause is "the architecture" or "the design", you have a smell, not a debuggable root cause. The fix for non-local causes is a different conversation (`@clean-code`, refactor, ADR).

## 5 Whys

A linear procedure to drill from symptom to root cause. Stop when the next "why" no longer has an answer **in the code**.

### Procedure

1. Start with the symptom.
2. Ask "why does that happen?" Answer using only what the code shows.
3. Ask "why" of the answer. Repeat.
4. Stop at the answer where the next "why" leaves the code (becomes "because that was the design", "because the requirement says so", etc.).

### Worked example — Go panic

```text
S: Handler responded with 500 and process died.
W1: Why?  Because the handler panicked at order.go:54.
W2: Why?  Because claims.UserID was called on a nil claims pointer.
W3: Why?  Because c.Get("claims") returned (nil, false).
W4: Why?  Because the auth middleware was never registered for this route.
W5: Why?  Because the route was added in router.go:88 without grouping under
          authMiddleware (the new endpoint is outside the auth-required group).
```

Root cause: `router.go:88` — new route registered outside the `authRequired` group. This passes the three tests:

- **Sufficiency**: moving the route under the group stops the panic.
- **Necessity**: without that misplacement, the auth middleware would have rejected the unauthenticated request before the handler ran.
- **Locality**: `router.go:88`.

### Anti-pattern

A false 5 Whys lands on a non-local "cause":

```text
W5: Why?  Because the team's onboarding for new endpoints is unclear.
```

This is a process improvement, not a debuggable root cause. File it as a follow-up; do not call it the fix.

## Fishbone (Ishikawa) — for systemic bugs

When 5 Whys produces several candidates without converging, switch to a fishbone:

```text
                                  the bug
                                     ▲
        ┌────────┬────────┬────────┬────────┐
        │ code   │ tests  │ build  │ env    │
        │        │        │        │        │
        H1.1     H2.1     H3.1     H4.1
        H1.2     H2.2     H3.2     H4.2
```

Each branch is a category. Each twig is a candidate cause. Fishbone is useful when:

- The bug is intermittent (timing, env, infrastructure).
- Multiple parties touched the affected code recently.
- The symptom appears in more than one place.

Convert each twig into a hypothesis (Phase 2 in the SKILL) and test in cost order.

## `git bisect`

When the bug appeared after a known-good revision and there is a script that detects it, bisect mechanically locates the introducing commit.

### Manual bisect

```bash
git bisect start
git bisect bad HEAD
git bisect good <known-good-tag-or-sha>
# git checks out a midpoint; you run the test and answer:
git bisect good   # if the midpoint is good
git bisect bad    # if the midpoint reproduces the bug
# repeat until git points to a single commit
git bisect reset  # restore HEAD when done
```

### Automated bisect

```bash
# Script must exit 0 on "good", non-zero on "bad"
git bisect start HEAD <good>
git bisect run ./scripts/repro.sh
```

Validate the script by hand on at least the endpoints (`good` and `bad`) before letting bisect run it dozens of times. A faulty script gives a confident wrong answer.

### When bisect finds the commit

The introducing commit is **a fact**. Whether it is the **root cause** still requires the three tests:

- The bug may have been latent before, just not exercised. The commit revealed it without causing it.
- The commit may be a band-aid for a deeper bug elsewhere; reverting it would mask the symptom.

Always read the commit diff and ask: does this code change satisfy sufficiency + necessity + locality?

## Bug taxonomies (helps generate hypotheses)

When stuck, scan this taxonomy for matches:

### Memory-class bugs

- Use-after-free / dangling pointer / dropped reference held elsewhere
- Memory leak (allocation without release)
- Buffer overrun / underrun
- Stack overflow (unbounded recursion, oversized stack frame)
- Incorrect alignment (rare; mostly Rust `unsafe` / FFI)

### Concurrency-class bugs

- Race condition (lost update, ABA, Time-of-check / time-of-use)
- Deadlock (lock-order inversion, circular wait)
- Livelock (every actor yields to the others)
- Starvation (one actor never progresses)
- Goroutine / task / promise leak (spawned, never joined)
- Async cancellation propagation broken

### Logic-class bugs

- Off-by-one
- Wrong default value
- Inverted condition (`!=` where `==` was meant)
- Branch falls through (Go `switch` is fine; `case` in C-like; `match` in Rust forces exhaustive)
- Time / timezone (UTC vs local; DST; system clock vs monotonic)
- Floating-point comparison
- Integer overflow / truncation

### Boundary-class bugs

- Invalid input not rejected
- Sanitization happens after use
- Charset / encoding (UTF-8 vs UTF-16 vs ASCII)
- URL parsing edge case (port, percent-encoding, IDN)
- Path traversal (Phase 3 in code-review)

### Environment-class bugs

- Wrong dependency version (lockfile mismatch, transitive)
- Wrong build mode (debug vs release; cgo on/off)
- Wrong feature flag default
- Stale cache (build cache, test cache, Docker layer)
- File not committed (works locally, fails on CI)

### Test-class bugs

- The test is wrong (asserts the wrong thing)
- The test depends on order
- The test depends on the clock
- The test depends on the network (fix: mock or skip in CI)
- The test depends on a previous test's leftover state

## Stop conditions

Stop investigating and report when:

- **Root cause confirmed** — proceed to Phase 5.
- **Three hypotheses falsified without progress** — escalate. State the open hypotheses, the evidence collected, and the questions for the user.
- **Reproduction failed after reasonable attempts** — state the gap; ask for more telemetry.
- **The code in question is in a third-party library** — confirm version; check the issue tracker; consider workaround vs upgrade.
- **The user reports the bug stopped on its own** — record the state and ask whether to keep investigating; intermittent bugs that "fixed themselves" almost always come back.

A good debug report is honest about its limits. Saying "I do not know yet, here is what I know" is better than confabulating an answer.
