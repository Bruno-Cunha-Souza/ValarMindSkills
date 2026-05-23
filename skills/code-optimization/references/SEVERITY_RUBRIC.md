> Reference companion for the [code-optimization](../SKILL.md) skill.

# Severity Rubric — Tri-axis (Impact × Risk × Effort)

Every finding from `@code-optimization` is graded on three independent axes. The matrix is the deliverable's value-add: it lets the user prioritize without re-reading the report.

## 1. Impact

| Level | Definition | Quantitative anchor (cite when known) |
| --- | --- | --- |
| **Critical** | Production-blocking. Outage, data loss, or cost runaway if shipped. | p99 latency > 10x SLO, OOM in steady state, > 100% infra cost overrun |
| **High** | Materially degrades the user experience or burns money. Should be fixed before next release. | p99 latency > 2x SLO, > 30% extra CPU, > 100MB/req allocations, > 20% cost increase |
| **Medium** | Latent inefficiency. Visible under load but not in normal traffic. | 5–20% slower than baseline, allocations measurable but not page-flooding |
| **Low** | Minor inefficiency, polish-class. Below noise floor of real benchmarks. | < 5% delta, single-digit-MB allocs, micro-optimization |

**Rules:**
- Impact claims need an evidence anchor: a profile slice, a doc citation, or an arithmetic argument quoted in the finding.
- "It might be slow" is not Impact High. Demote to Low + Confidence Low or drop.
- A finding that doubles as a security DoS (unbounded query, ReDoS, decompression bomb) is Impact High **and** must cross-link to `@code-security-review`.

## 2. Risk (adoption risk of the suggested fix)

Same semantics as `@code-review`:

| Tag | Definition |
| --- | --- |
| **SAFE** | Isolated change. No behavior change, no public API impact. Examples: add `selectinload`, swap `json` for `orjson`, add `sync.Pool` to a tight allocator. |
| **REVIEW** | Touches shared utility, middleware, request boundary, or implicit contract. Examples: change a serializer used by many handlers, add a cache layer, swap event loop policy. |
| **BREAKING** | Changes a signature, response shape, public schema, or observable behavior. Examples: paginate an endpoint that previously returned all rows, change response field types, replace ORM model field. |

**Rules:**
- The tag describes the **fix risk**, not the bug risk.
- If a finding is High Impact but BREAKING, the report still ranks it high — but the recommendation states the migration path (deprecation window, dual-write, feature flag).
- SAFE fixes go in **Quick Wins** when paired with Effort=S.

## 3. Effort

| Level | Definition | Anchor |
| --- | --- | --- |
| **S** (Small) | < 1 hour total: code change + test + review. Mechanical, low-thinking. | 1–20 lines, 0–1 test added, no design discussion |
| **M** (Medium) | 1–8 hours. Some design thinking, multiple files. | 20–200 lines, 2–5 tests, may touch a module boundary |
| **L** (Large) | > 1 day. Cross-cutting refactor or architectural change. | > 200 lines, multiple modules, may need migration, requires design review |

**Rules:**
- Effort is a calibrator, not a hard estimate. The point is comparative ranking, not project planning.
- A finding rated Effort=L should include an alternative Effort=S workaround when one exists ("partial mitigation: cap result set at 1000").

## 4. Priority quadrants

The report sorts findings into four quadrants:

```text
                  Effort
                S            M            L
        ┌─────────────┬─────────────┬─────────────┐
   Crit │ QUICK WIN   │ STRATEGIC   │ STRATEGIC   │
   High │ QUICK WIN   │ STRATEGIC   │ STRATEGIC   │
        ├─────────────┼─────────────┼─────────────┤
   Med  │ POLISH      │ POLISH      │ DEFER       │
   Low  │ POLISH      │ DEFER       │ DROP        │
        └─────────────┴─────────────┴─────────────┘
Impact
```

| Quadrant | Definition | Report behavior |
| --- | --- | --- |
| **QUICK WIN** | High/Critical impact + Small effort | Top of report. Address before next release. |
| **STRATEGIC** | High/Critical impact + Medium/Large effort | Schedule explicitly. Worth a design ticket. |
| **POLISH** | Medium/Low impact + Small effort | Tackle opportunistically while in the file. |
| **DEFER** | Medium impact + Large effort | Bottom of report. Re-evaluate if Impact escalates. |
| **DROP** | Low impact + Large effort | Not in report. Mentioned in `summary.dropped:` count only. |

## 5. Confidence (orthogonal)

Separate from the tri-axis grade — it gates whether Phase 4 validation must run.

| Confidence | Meaning |
| --- | --- |
| **High** | Evidence is exhaustive (profile, doc citation, or trivial mechanical fact) — no further validation needed. |
| **Medium** | Pattern matches; intent could justify it. Validation strengthens the case but is optional. |
| **Low** | Reviewer needs a second opinion. **Mandatory escalation** when `Confidence=Low AND Impact >= High` — phrase finding as `needs human review before action`. |

Phase 4 (external validation) is triggered exactly when `Impact >= High AND Confidence < High`.

## 6. Calibration anti-patterns

Watch for these in self-review before emitting the report:

- **Impact inflation.** "This could become slow under load" without a load test or doc citation. Demote to Medium or drop.
- **Effort optimism.** Estimating S when the fix touches a serializer used by 80 endpoints. Promote to M or L.
- **SAFE inflation.** Tagging SAFE on a change to a shared util. Promote to REVIEW.
- **Tri-axis correlation creep.** Letting Effort drive Impact (a hard fix is not automatically Critical, and vice-versa). Grade each axis independently.

## 7. Examples

| Finding | Impact | Risk | Effort | Quadrant |
| --- | --- | --- | --- | --- |
| Add `selectinload` to fix N+1 in `users` endpoint (50ms → 5ms p99) | High | SAFE | S | QUICK WIN |
| Replace `json` with `orjson` in FastAPI response (15% CPU drop) | High | REVIEW | S | QUICK WIN |
| Swap `Arc<Mutex<HashMap>>` for `DashMap` in hot path | High | REVIEW | M | STRATEGIC |
| Paginate `GET /orders` (currently returns all rows) | Critical | BREAKING | M | STRATEGIC |
| Replace `string +` concat in tight loop with `strings.Builder` | Medium | SAFE | S | POLISH |
| Migrate from Node `http` to Bun `Bun.serve` | High | BREAKING | L | STRATEGIC |
| Add `__slots__` to a request DTO with 200 instances/sec | Low | SAFE | S | POLISH |
| Rewrite ORM layer to async SQLAlchemy 2.0 | Medium | BREAKING | L | DEFER |
