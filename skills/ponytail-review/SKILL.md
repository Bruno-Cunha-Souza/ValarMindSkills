---
name: ponytail-review
description: "Over-engineering review — finds what to DELETE, not what to fix. One line per finding with tags delete/stdlib/native/yagni/shrink and a net-lines score. Three scopes: current diff (default), whole repo ('repo'/'audit'), or 'debt' to harvest ponytail: comments into a ledger. Complements correctness review (@code-review, @github-pr-review) — this lens only hunts complexity. Use when the user says 'review for over-engineering', 'what can we delete', 'is this over-engineered', 'find bloat', 'audit for bloat', 'ponytail debt', 'list the shortcuts', '/ponytail-review'. One-shot report; applies nothing."
source: https://github.com/DietrichGebert/ponytail
---

# Ponytail Review

## When to Use

One-shot review focused exclusively on over-engineering. Finds what to delete: reinvented standard library, unneeded dependencies, speculative abstractions, dead flexibility. The diff's best outcome is getting shorter.

Three scopes, picked by argument:

| Scope | Trigger | What is scanned |
| :--- | :--- | :--- |
| **diff** (default) | `/ponytail-review` | The current working diff (or the PR/branch diff the user points at) |
| **repo** | `/ponytail-review repo` (or "audit") | The whole tree — ranked list, biggest cut first |
| **debt** | `/ponytail-review debt` | Every `ponytail:` comment, harvested into a ledger |

Do **not** use for correctness bugs, security holes, or performance — route those to `@code-review`, `@code-security-review`, or `@code-optimization`. This lens only hunts complexity.

## Core Concepts

One line per finding: location, what to cut, what replaces it. Findings are statements, not questions — never "have you considered whether this class might be more complex than necessary?".

### Tags

- `delete:` dead code, unused flexibility, speculative feature. Replacement: nothing.
- `stdlib:` hand-rolled thing the standard library ships. Name the function.
- `native:` dependency or code doing what the platform already does. Name the feature.
- `yagni:` abstraction with one implementation, config nobody sets, layer with one caller.
- `shrink:` same logic, fewer lines. Show the shorter form.

## Detailed Topics

### Diff scope (default)

Format: `L<line>: <tag> <what>. <replacement>.` — or `<file>:L<line>: ...` for multi-file diffs.

End with the only metric that matters: `net: -<N> lines possible.`

Nothing to cut: `Lean already. Ship.` — and stop.

### Repo scope (`repo` / "audit")

Same tags, whole tree, ranked biggest cut first: `<tag> <what to cut>. <replacement>. [path]`.

Hunt list: deps the stdlib or platform already ships, single-implementation interfaces, factories with one product, wrappers that only delegate, files exporting one thing, dead flags and config, hand-rolled stdlib.

End with `net: -<N> lines, -<M> deps possible.`

### Debt scope (`debt`)

Every deliberate ponytail shortcut is marked with a `ponytail:` comment naming its ceiling and upgrade path. This scope collects them into one ledger so a deferral can't quietly become permanent.

Scan (skip `node_modules`, `.git`, build output):

```bash
grep -rnE '(#|//) ?ponytail:' .
```

One row per marker, grouped by file: `<file>:<line>, <what was simplified>. ceiling: <the limit named>. upgrade: <the trigger to revisit>.`

Flag the rot risk: any `ponytail:` comment that names no upgrade path gets a `no-trigger` tag — those are the ones that silently rot.

End with `<N> markers, <M> with no trigger.` Nothing found: `No ponytail: debt. Clean ledger.`

## Examples

❌ "This EmailValidator class might be more complex than necessary, have you considered whether all these validation rules are needed at this stage?"

✅ `L12-38: stdlib: 27-line validator class. "@" in email, 1 line, real validation is the confirmation mail.`

✅ `L4: native: moment.js imported for one format call. Intl.DateTimeFormat, 0 deps.`

✅ `repo.py:L88: yagni: AbstractRepository with one implementation. Inline it until a second one exists.`

✅ `L52-71: delete: retry wrapper around an idempotent local call. Nothing replaces it.`

✅ `L30-44: shrink: manual loop builds dict. dict(zip(keys, values)), 1 line.`

Debt row:

✅ `payments/lock.py:17, global lock on charge path. ceiling: single-flight throughput. upgrade: per-account locks if throughput matters.`

## Boundaries

- **Scope: over-engineering and complexity only.** Correctness, security, and performance are explicitly out of scope — route them to a normal review pass.
- **A single smoke test or `assert`-based self-check is the ponytail minimum, not bloat** — never flag it for deletion.
- **Lists findings, applies nothing.** One-shot: no flag files, no persistent mode. To persist the debt ledger, ask first, then write it to `PONYTAIL-DEBT.md`.
- **Reverting.** "stop ponytail-review" or "normal mode" returns to verbose review style.

## Constraints

- **Never** flag validation, error handling, security measures, accessibility, or the minimum runnable check as over-engineering.
- **Never** apply the cuts — report only.
- **Must** end with the score line (`net:` / marker count) or `Lean already. Ship.`
- **Must** keep one line per finding — location, cut, replacement.

## Example invocations

- "review this for over-engineering"
- "what can we delete?"
- "find bloat in this repo"
- "/ponytail-review"
- "/ponytail-review repo"
- "/ponytail-review debt"
- "what did ponytail defer?"

## Attribution

Based on [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail) (MIT license). Consolidates upstream's `ponytail-review` (diff), `ponytail-audit` (repo), and `ponytail-debt` (ledger) skills into a single one-shot skill with a scope argument, following this repository's consolidation convention.
