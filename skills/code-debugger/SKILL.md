---
name: code-debugger
description: "Lifecycle debug Go/Rust/TS — symptom→reproduction→root cause→fix→regression test. Evidence-first (cites cmd output or stack frame). For runtime errors, test failures, panics, races, leaks, flaky tests. Triggers: 'debug', 'depurar', 'root cause', '/code-debugger'."
source: ValarMindSkills
---

# Code Debugger Lifecycle

> "Debugging is twice as hard as writing the code in the first place. Therefore, if you write the code as cleverly as possible, you are, by definition, not smart enough to debug it." — Brian Kernighan.

This skill walks a structured root-cause analysis. It is **evidence-first**: every step produces a citable artifact (a command output, a log line, a stack frame, a diff). It is **language-aware** for Go, Rust, and TypeScript; other languages are best-effort. It assumes nothing about the symptom — it asks until it has enough to reproduce.

The skill exists because LLM debuggers tend to confabulate: invented stack frames, fabricated error messages, premature root-cause claims, and "fixes" that change unrelated code. Every guardrail in the Constraints section is there to push back on those failure modes.

## When to Use

- A test is failing and the failure mode is not obvious from the message alone.
- An error appears in logs and the user wants to know where it originates.
- A panic / crash / unhandled rejection happened and the user has a stack trace.
- A program produces wrong output for a known input.
- A race, deadlock, or goroutine / task leak is suspected.
- A flaky test fails intermittently.
- A memory leak or steady performance regression is observed.
- A production incident needs post-mortem-grade root cause analysis.
- The user explicitly asks: `'debug'`, `'depurar'`, `'investigar erro'`, `'root cause'`, `'analisar stack trace'`, or invokes `/valarmindskills:code-debugger`.

## Do not use when

- The user wants a **review** of code that is not failing — use `@code-review`.
- The user wants the code refactored or simplified — use `@clean-code`.
- The user has no symptom to investigate (no error, no failing test, no observable issue) — debugging needs a starting signal.
- The user wants to write **new code** — use the relevant builder skill (`@code-security-review` for Go/Next API hardening, `@ci-cd-generator` for pipelines, etc.).
- The bug is in a third-party library outside the user's control and the user is not asking how to work around it — escalate to the library's issue tracker.
- The bug is in **infrastructure** (DNS, networking, cluster) without a code fingerprint — use ops tooling, not this skill.

## Prerequisites

| Tool | Purpose | Install |
| --- | --- | --- |
| `git` | History, blame, bisect | system package |
| `rg` (ripgrep) | Pattern search across the repo | `brew install ripgrep` |
| `delve` (`dlv`) | Go debugger | `go install github.com/go-delve/delve/cmd/dlv@latest` |
| `pprof` | Go CPU / heap / goroutine profiler | bundled with Go |
| `goleak` | Goroutine leak detection | `go get go.uber.org/goleak` |
| `gdb` / `lldb` | Native debugger (Rust, C bindings) | system package |
| `tokio-console` | Async runtime introspection (Rust + tokio) | `cargo install tokio-console` |
| `cargo expand` | Macro expansion | `cargo install cargo-expand` |
| `node --inspect` / `bun --inspect` | TypeScript / Node / Bun debugger | bundled |
| `clinic` | Node performance diagnostics (`doctor`, `flame`, `bubbleprof`) | `npm i -g clinic` |
| `0x` | Node flame graph generator | `npm i -g 0x` |

Required access:

- [ ] Read access to the source code, including the failing test
- [ ] Permission to run the failing test / command on the host
- [ ] Logs from the failing run (or the ability to reproduce locally)
- [ ] If the bug is timing-dependent: the ability to run the test repeatedly (`-count=N`)
- [ ] If the bug is in production: the relevant log range and (if available) a profile / heap dump

The skill does **not** assume write access. It produces a recommended diff in Phase 5; the user applies it.

## Phase 0 — Capture & Reproduce

Before forming a hypothesis, **make the bug reproducible**. A bug you cannot reproduce is a bug you cannot fix; without reproduction, every later phase is conjecture.

### 0.1 Capture the symptom

Collect, verbatim, **all** of the following before proceeding:

1. The exact **error message** (copy-paste, no paraphrasing).
2. The **stack trace** if any.
3. The **command** that triggered it (or the request, the test name, the input).
4. The **expected behavior** (what should have happened instead).
5. The **observed behavior** (what actually happened).
6. The **environment** — language version, OS, dependency versions, recent changes.
7. The **frequency** — first occurrence, always-fails, intermittent, only on CI.

If any of those is missing, ask the user. Do not guess. The skill **must not invent error messages** or stack frames; if the user has not pasted one, ask for it.

### 0.2 Reproduce locally

```bash
# Find the failing test
rg -n "<symbol from stack trace>" --type <lang>

# Run the failing test in isolation
go test -run '^Test_<name>$' -v ./<pkg>            # Go
cargo test --test <file> -- --exact <name>          # Rust
bun test <file> -t '<name>'                         # Bun
npx vitest run -t '<name>'                          # Vitest
npx jest -t '<name>'                                # Jest
```

Confirm the failure is observable on the local machine with the same error message captured in 0.1. If the failure is not reproducible:

- For flaky tests: re-run with `-count=100` (Go), `--repeat 100` (cargo nextest), `--retry 100` in test runner config (TS). Capture the failure rate.
- For environment-specific bugs: replicate the env (container, CI matrix, OS version).
- For timing bugs: vary `GOMAXPROCS`, increase load, run with `-race`.

If still not reproducible after a reasonable attempt, **stop and report**. A non-reproducible bug needs more telemetry (logs, traces, profiles) before debugging continues.

### 0.3 Reduce to minimum example

Strip the reproduction down to the smallest input that still fails. Each removal must keep the bug present; a removal that masks the bug is data — note it.

```bash
# git bisect when the bug appeared after a known-good commit
git bisect start
git bisect bad HEAD
git bisect good <last-known-good-tag-or-sha>
# follow git's prompts; "good" / "bad" per step
```

`git bisect run <script>` automates the loop when the failure is detectable from a script's exit code. The script must return 0 for "good" and non-zero for "bad" — verify by hand on at least the endpoints before delegating.

## Phase 1 — Isolate

Narrow the failure to one component. The goal of this phase is to be able to say: "the bug is in `path/to/file.ext` between line A and line B" with evidence.

### 1.1 Read the stack trace

For each frame, top to bottom:

- Note the file, line, and function.
- Map the line to the source file (verify the version matches the binary that produced the trace — `git rev-parse HEAD` against the build).
- Identify which frame is **the user's code** (vs library / runtime / framework).
- The first user-frame from the top is usually where the bug surfaces; the bug itself may be deeper.

### 1.2 Boundary check

For each user-frame in the trace, list:

- **Inputs received** — what does this function get? Are any nil / zero / out-of-range?
- **Pre-conditions assumed** — what must be true on entry?
- **Post-conditions promised** — what must be true on exit?
- **Resources acquired** — locks, handles, goroutines, sockets.

This is the same checklist as `@code-review` Phase 2.2 but applied to the trace, not the diff.

### 1.3 Recent change check

```bash
# Files in the failing path with recent commits
for f in $(<list of files in the trace>); do
  git log --oneline -5 -- "$f"
done

# Who last changed the failing line
git blame -L <START>,<END> <file>
```

Recent changes in the failing path are **leads**, not conclusions. Read the commit messages and the diff before assuming causation.

## Phase 2 — Form Hypotheses

A hypothesis is a falsifiable claim about the cause. Each hypothesis has a test that can disprove it.

### 2.1 Hypothesis log

Maintain a running log:

```text
H1: <claim about cause>
    Evidence-for: <observation supporting it>
    Evidence-against: <observation contradicting it, or "none yet">
    Test: <action that would falsify or confirm this>
    Status: open | confirmed | rejected
```

Example:

```text
H1: The handler panics because the JWT claims context value is missing
    Evidence-for: stack trace top frame is `claims.(*Claims).UserID`
    Evidence-against: middleware order looks correct in router.go:42
    Test: print the keys present in c.Keys at handler entry
    Status: open
```

### 2.2 Don't skip — falsify cheap hypotheses first

Order hypotheses by **cost to falsify**, not by likelihood. A 30-second `printf` beats a 30-minute analysis.

| Hypothesis class | Falsify with |
| --- | --- |
| "The value is nil here" | log it before the use site |
| "This branch is not taken" | log on entry to each branch |
| "This goroutine never runs" | log on entry; or `runtime.NumGoroutine()` |
| "The map iteration order matters" | run the test 10× — does it flip? |
| "The cache is stale" | clear cache and re-run |
| "The build is stale" | full rebuild (`go clean -testcache && go test ...`) |
| "It works on my machine" | run on the user's environment via container |

### 2.3 Use the `5 Whys`

For each confirmed proximate cause, ask "why" five times. Stop when "why" no longer has an answer in the code. The last answer is the **root cause**. See [references/ROOT_CAUSE_ANALYSIS.md](references/ROOT_CAUSE_ANALYSIS.md) for full procedure.

## Phase 3 — Instrument

When inspection alone is insufficient, add observability. Each instrumentation must be **temporary**, **strategic**, and **revertible**.

### 3.1 Instrumentation hierarchy (cheapest first)

1. **Read existing logs** — does the code already log near the failing path?
2. **Add `printf` / `println` / `log.Debug`** at the boundary of the suspected function.
3. **Add a structured log field** for the suspect variable.
4. **Attach a debugger** (`dlv`, `gdb`, `node --inspect`, `bun --inspect`) — set a breakpoint, inspect state.
5. **Capture a profile** — CPU (`pprof.Profile`), heap (`pprof.Lookup("heap")`), goroutine (`pprof.Lookup("goroutine")`), allocations.
6. **Capture a core dump / heap dump** for offline analysis.

Each step costs more than the last. Stop at the first that reveals the answer.

### 3.2 Strategic logging — what to log

- **Identity** — request ID, trace ID, test name.
- **Inputs** — function arguments at the boundary (mask secrets).
- **Decisions** — which branch was taken.
- **Resource state** — cache keys, queue depth, goroutine count.
- **Timing** — time spent between two points.
- **Output** — the value about to be returned.

Do **not** log secrets, full request bodies, or PII without masking. See `@code-review` references for the cross-language sensitive-data list.

### 3.3 Cleanup

Each piece of instrumentation added in this phase must be reverted before the fix lands, unless the instrumentation is itself the right long-term observability. Track each addition in the hypothesis log.

## Phase 4 — Identify Root Cause

A root cause is a code-level statement of why the bug occurs. It must satisfy three tests:

1. **Sufficiency** — fixing this alone makes the bug stop.
2. **Necessity** — without this, the bug would not occur.
3. **Locality** — it points to a specific file:line span you can quote.

If any test fails, you do not yet have the root cause — you have a contributing factor or a symptom.

### 4.1 Patterns across languages

| Pattern | Language | Detection |
| --- | --- | --- |
| Nil / null dereference | all | the trace shows the nil value's use site |
| Race / data race | Go, Rust, JS (workers) | `-race`, `loom`, `tsan`, repro under load |
| Deadlock | Go, Rust, async-TS | trace shows two stuck goroutines / tasks holding each other's lock |
| Goroutine / task / promise leak | Go, Rust, TS | count grows without bound; `pprof.goroutine`, `tokio-console` |
| Off-by-one | all | input boundary value triggers it |
| Wrong default | all | input is "missing" rather than "wrong" |
| Re-entrancy | Go, Rust, TS | the same code runs twice and sees its own intermediate state |
| Time-of-check / time-of-use | all | a value is checked, then re-read, then used |
| Type coercion | TS, JS | `==` vs `===`, string vs number |
| Lifetime / borrow | Rust | borrow checker error or use-after-move |
| Async cancellation | Go, Rust, TS | parent task cancelled, child still writing |

Each language reference ([GOLANG](references/GOLANG.md), [RUST](references/RUST.md), [TYPESCRIPT](references/TYPESCRIPT.md)) has the language-specific detection commands and example fixes.

## Phase 5 — Apply Minimal Fix

The fix targets the **root cause**, not the symptom. It is the smallest change that satisfies the three tests in Phase 4.

### 5.1 Fix discipline

- **One change at a time.** Do not "while you're there" refactor.
- **Behavior preservation elsewhere.** The fix must not change other tests; if it does, those tests must be re-justified.
- **No swallowed errors.** The fix should not hide a future symptom of the same class.
- **No `// fixed bug` comments.** The git history records why; comments rot.
- **Risk tag.** Same convention as `@code-review`: `SAFE` / `REVIEW` / `BREAKING`.

### 5.2 Diff format

The skill produces the fix as a unified diff in the report. It does **not** apply the change automatically — the user reviews and applies. See Output format.

## Phase 6 — Verify & Prevent

A fix without verification is a hypothesis.

### 6.1 Verify

```bash
# Re-run the original failing test
<the same command from Phase 0.2>

# Run the full test suite for the affected package
go test ./<pkg>/...                                # Go
cargo test --package <pkg>                          # Rust
bun test <dir>                                      # Bun
npx vitest run <dir>                                # Vitest

# For timing bugs, run repeatedly
go test -run '^Test_<name>$' -count=100 ./<pkg>     # Go
cargo nextest run --test <file> --partition count:100/1   # Rust
```

Capture the command and its full output. The report must include the **exact command** and a **trimmed but verbatim** quote of the success indication.

### 6.2 Regression test

A fix without a regression test invites regression. Add one test:

- That **fails on the pre-fix code** (verify by reverting the fix temporarily — or by reasoning if the test expresses an invariant the pre-fix code violated).
- That **passes on the post-fix code**.
- That asserts the **invariant**, not the implementation. (Bad: "function called once". Good: "user A cannot read user B's record".)

### 6.3 Prevention

For each root cause, identify whether the same class of bug exists elsewhere:

```bash
# Sweep the codebase for the same pattern
rg -n '<the failing pattern>' --type <lang>
```

If yes, list each candidate site with `file:line`. Do **not** fix them in this PR — file follow-up tasks. The fix in this PR is for **this** bug.

Optional but valuable: propose a lint rule, a test helper, or a CI check that would have caught this class of bug. State it as a recommendation, not as part of the fix.

## Constraints

- **Never invent an error message, stack frame, or log line.** If the user has not provided one, ask for it.
- **Never claim a test passes without showing the command and its output.** Quote the success/failure line; do not paraphrase.
- **Never propose a fix without quoting the failing code first.** Read the file at the cited line; the quote must match byte-for-byte.
- **Never claim "root cause" without satisfying sufficiency + necessity + locality** (Phase 4 tests).
- **Never edit code automatically.** Suggested fixes are diffs in the report. The user applies them.
- **Never hide instrumentation in the final fix.** All `printf`/`println`/`log.Debug` added during Phase 3 are reverted unless the user explicitly keeps them.
- **Never skip Phase 0.** A bug you cannot reproduce is a bug you cannot fix.
- **Never expand scope.** The fix targets the root cause of **the reported bug**. Other smells encountered are listed as Info, not patched.
- **Always provide a regression test.** A fix without a regression test is rejected.
- **Always include the tool versions used** (`go version`, `cargo --version`, `node --version` / `bun --version`).
- **Always cross-link to the dedicated skill** when the root cause belongs to its domain (`@code-review`, `@clean-code`, `@code-security-review` — Go branch `references/golang/`, Next branch `references/nextjs/`; performance regressions in Next.js → `@code-review` `references/NEXTJS.md`).
- **Must drop a hypothesis the moment evidence-against arrives.** Do not hold onto a theory because it would be elegant.
- **Must escalate when stuck.** After three falsified hypotheses without progress, summarize the state and ask the user (more telemetry, second pair of eyes).

## Output format

Print verbatim after the investigation. Sections may be empty if the phase did not apply, but the skeleton is fixed.

```text
code-debugger: <one-line title of the bug>
  language:        <go | rust | typescript | other>
  toolchain:       <go 1.23 | rust 1.81 | node 20.10 | bun 1.1.30>
  reproducer:      <command + args, copy-paste-ready>
  duration:        Phase 0–6 walked

Symptom (Phase 0):
  Error:           <verbatim error message>
  Stack (top frames):
    | <file>:<line> <function>
    | <file>:<line> <function>
    | ...
  Reproduction:    <command + args>
  Frequency:       <always | flaky N% | once-off | env-specific>

Hypotheses tested (Phase 2):
  H1: <claim>
      Test:     <falsification action>
      Outcome:  <confirmed | rejected: evidence>
  H2: <claim>
      Test:     ...
      Outcome:  ...

Root cause (Phase 4):
  Location:        <path/to/file.ext:LINE>
  Code (verbatim, before fix):
    | <quoted code>
  Why it fails:    <one-paragraph explanation tied to the quoted code>
  Sufficiency:     <evidence the fix alone stops the bug>
  Necessity:       <evidence the bug requires this code path>

Fix (Phase 5) — Risk: <SAFE | REVIEW | BREAKING>
  Diff:
    | --- a/<path>
    | +++ b/<path>
    | @@ -<old> +<new> @@
    |  <unchanged context>
    | -<removed line>
    | +<added line>
    |  <unchanged context>
  Rationale:       <one paragraph>

Verification (Phase 6):
  Pre-fix:        <command> →  FAILED (<excerpt>)
  Post-fix:       <command> →  PASSED (<excerpt>)
  Repeat run:     <command -count=N> →  PASSED N/N

Regression test:
  Location:        <path/to/file_test.ext>
  Test name:       <Test_...>
  Asserts:         <invariant in plain language>

Prevention:
  Same-class sites swept:
    <path:line — needs follow-up>
    <path:line — needs follow-up>
  Lint / CI suggestion: <optional, one line>

Skill version: code-debugger @ <git rev of SKILL.md>
```

When the skill cannot reach root cause, print the same skeleton truncated at the last completed phase, plus a `Blocked` section listing the missing telemetry and the questions outstanding for the user.

## Related Skills

- `@code-review` — for static review of code that is not failing; also useful after a fix to spot collateral risk. For Next.js performance regressions, see `@code-review` `references/NEXTJS.md`.
- `@clean-code` — when the root cause is a maintainability smell that recurred (god function, unclear name, hidden dependency).
- `@code-security-review` — when the bug is in the API surface and security review (design + active testing) helps. Go-specific runtime bugs (race, slowloris, pprof) — see `references/golang/`. Next.js App Router security-driven runtime bugs (RSC, Server Actions, `proxy.ts`) — see `references/nextjs/`.
- `@github-commit` — when the user wants help drafting the fix commit.
- `@superpowers` — engineering posture (TDD, evidence-first) for the user fixing more bugs of the same class.
- `@ci-cd-generator` — to add the lint / test that would have caught this class of bug to the pipeline.

## References

- [ROOT_CAUSE_ANALYSIS](references/ROOT_CAUSE_ANALYSIS.md) — 5 Whys, fishbone, bisect, sufficiency/necessity tests
- [EVIDENCE_FORMAT](references/EVIDENCE_FORMAT.md) — bug report template, hypothesis log, evidence rules
- [GOLANG](references/GOLANG.md) — Go-specific debugging (delve, pprof, race, goroutine, panic)
- [RUST](references/RUST.md) — Rust-specific debugging (gdb/lldb, RUST_BACKTRACE, tokio-console, miri)
- [TYPESCRIPT](references/TYPESCRIPT.md) — TS / Node / Bun debugging (inspector, source maps, async stacks, leak hunting)
- [EXAMPLE](EXAMPLE.md) — end-to-end worked debug of a Go panic in production
