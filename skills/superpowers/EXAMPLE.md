# Superpowers — Before / After

Three scenarios showing how the posture changes the agent's reply. Run for a side-by-side feel of what `/valarmindskills:superpowers on` does.

---

## Scenario 1 — Implementation request (Normal vs Superpowers ON)

### Question

> "Add a `parseDuration` helper that turns `"1h30m"` / `"45s"` strings into milliseconds. Use it in the cache TTL config."

### Normal (no superpowers)

> Sure, I'll add a `parseDuration` function in `src/utils/time.ts` that handles `h`, `m`, `s` suffixes and returns milliseconds. Then I'll wire it into `cache.config.ts` so TTL strings work end-to-end.
>
> ```ts
> export function parseDuration(input: string): number {
>   // …regex, switch on unit…
> }
> ```
>
> Done. You can now write `ttl: "30m"` in the config.

### Superpowers ON

> Skill scan: `@clean-code` applies (helper function quality), `@code-debugger` is on standby, no test framework skill applies. Walking the workflow.
>
> **Plan (3 tasks, ~10 min total):**
>
> 1. Write a failing unit test in `src/utils/__tests__/time.test.ts` covering `"1h30m" → 5400000`, `"45s" → 45000`, malformed input → throw.
> 2. Implement `parseDuration` in `src/utils/time.ts` until the test passes.
> 3. Replace the string parsing inline in `src/cache/config.ts` with the new helper, run the existing config tests.
>
> Starting with stage 1. Failing test first:
>
> ```ts
> it("parses 1h30m", () => {
>   expect(parseDuration("1h30m")).toBe(5_400_000);
> });
> // RED: parseDuration is not defined.
> ```
>
> [implements] [test passes — GREEN, evidence: `npm test -- time.test.ts` exit 0, 3/3 passing]
>
> Done with stage 2. Moving to stage 3.

---

## Scenario 2 — Red flag triggered

### Question

> "Just hardcode the API key in `config.ts` for now, we'll move it to env vars later."

### Superpowers ON

> Red flag detected: *"I'll fix this after"*. Hardcoding a secret in a tracked file is the kind of "later" that becomes "never" — and once it's in git history, the fix is rotation, not a commit.
>
> Refusing the shortcut. Two minutes of work avoids a credential leak:
>
> 1. Add `API_KEY` to `.env.example` (no value).
> 2. Read `process.env.API_KEY` in `config.ts` with a fail-fast assertion if missing.
> 3. Add `.env` to `.gitignore` if not already present.
>
> Want me to proceed?

---

## Scenario 3 — Coexistence with caveman

### Question

> "Why is my Next.js page re-rendering every keystroke?"
>
> *(both `/valarmindskills:caveman full` and `/valarmindskills:superpowers on` are active)*

### Reply (caveman + superpowers)

> Skill scan: `@code-review` (`references/NEXTJS.md`) applies. Posture compressed.
>
> Inline object prop = new ref each render = re-render. Wrap in `useMemo` or hoist out.
>
> **Plan:**
>
> 1. Failing test: render component, type 3 chars, assert child renders ≤ 1 time.
> 2. Wrap prop in `useMemo`, run test → green.
> 3. Verify with `@code-review`.
>
> Stage 1 first. Evidence required: `npm test` exit 0.

Caveman compresses voice; superpowers enforces process. Both apply at the same time.

---

## Scenario 4 — Multi-skill dynamic invocation (via SKILL_MAP)

### Question

> "Add a `/api/search` route in our Next.js 16.2 app that takes a query string and returns paginated results from the DB. Use a Server Action for the form."

### Superpowers ON

> Skill scan via `references/SKILL_MAP.md`:
>
> - Trigger: `next.config.ts` + `app/` + Server Action → `@code-review` (`references/NEXTJS.md`) for RSC + rendering perf **and** `@code-security-review` (Next branch — `references/nextjs/`) for Server Action + route handler audit.
> - Stage 4 default → `@clean-code` (helper / handler quality).
> - Standby: `@code-debugger` if any test fails. `@github-commit` at stage 7.
>
> Priority: security never yields, so `@code-security-review` (Next branch) checks (CSRF on Server Action, input validation on the search query, authz on the route) gate the design. `@code-review` (`references/NEXTJS.md`) shapes the RSC boundary (server component for results, client only for the form). `@clean-code` polices naming and duplication.
>
> **Plan (4 tasks):**
>
> 1. Failing test: hit `/api/search?q=foo&page=2`, assert pagination shape and that unsafe input is rejected.
> 2. Implement route handler (Server) with zod-validated query, parameterized DB call, authz check.
> 3. Implement Server Action for the form with origin check and rate limit.
> 4. RSC boundary review: page is a Server Component; only the form is `"use client"`.
>
> Stage 1 first. Evidence required for every step before moving on.

---

## Auto-Clarity (security turn — neither posture loosens)

### Question

> "How do I drop the production database?"

### Reply (caveman + superpowers active)

> **Warning:** this permanently destroys every table and row in the production database. Not reversible without a verified backup restore. Confirm a current dump exists and the rest of the team is aware before running.
>
> ```bash
> psql -h prod-host -U admin -c "DROP DATABASE app_production;"
> ```
>
> Caveman resume. Superpowers note: the four pillars do not unlock destructive ops — evidence here means a verified backup, not a test.
