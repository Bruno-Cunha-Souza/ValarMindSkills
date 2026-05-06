# Active Probe Scripts

Executable companions to `references/TESTING_PHASES.md`. Each script automates one phase of active security testing and emits findings as JSON-Lines (one finding per line) to `findings.jsonl`.

> **AUTHORIZATION REQUIRED.** Run only against systems you own or for which you have explicit written authorization (pentest agreement, bug bounty scope). Unauthorized testing is a crime in most jurisdictions. The orchestrator (`run-all.sh`) refuses to run unless `I_HAVE_AUTHORIZATION=1` is set.

## Quickstart

```bash
cd skills/code-security-review/scripts/

# Set required environment variables
export TARGET="https://api.staging.example.com"
export TOKEN_USER_A="eyJhbGciOi..."        # auth token for user A
export TOKEN_USER_B="eyJhbGciOi..."        # auth token for user B (BOLA tests)
export USER_A_RESOURCE_ID="42"             # a resource ID owned by user A
export ORIGIN_ALLOWED="https://app.example.com"
export I_HAVE_AUTHORIZATION=1

# Run all phases
./run-all.sh

# Or run a single phase
./01-auth-probes.sh
./04-injection-probes.sh
```

Findings end up in `./out/findings.jsonl` and a human-readable summary in `./out/report.md`.

## Environment Variables

| Variable | Required by | Default | Description |
| --- | --- | --- | --- |
| `TARGET` | all | — | Base URL of the API under test (no trailing slash) |
| `I_HAVE_AUTHORIZATION` | run-all | — | Must be `1` to proceed |
| `TOKEN_USER_A` | 03-bola | — | Bearer token for user A |
| `TOKEN_USER_B` | 03-bola | — | Bearer token for user B |
| `USER_A_RESOURCE_ID` | 03-bola | — | Resource ID owned by user A (e.g. order ID) |
| `ADMIN_PATH` | 03-bola | `/api/admin/users` | Admin endpoint to probe with regular token |
| `LOGIN_PATH` | 05-rate | `/auth/login` | Auth endpoint to probe for brute force protection |
| `RATE_LIMIT` | 05-rate | `100` | Expected requests/min limit on `/api/data` |
| `RATE_PATH` | 05-rate | `/api/data` | Endpoint to probe for general rate limit |
| `LOGIN_FIELD_USER` | 05-rate | `email` | Login request field name for username |
| `LOGIN_FIELD_PASS` | 05-rate | `password` | Login request field name for password |
| `ORIGIN_ALLOWED` | 08-cors | — | Origin that *should* be allowed (for sanity check) |
| `GRAPHQL_PATH` | 06-info | `/graphql` | GraphQL endpoint (if applicable) |
| `OUT_DIR` | all | `./out` | Output directory |
| `JWT_SAMPLE` | 02-jwt | — | A valid JWT to manipulate for alg confusion / claim tampering |

## Scripts

| File | Phase | Tools required |
| --- | --- | --- |
| `00-pre-checks.sh` | Framework / debug-mode flags, doc exposure | curl, jq |
| `01-auth-probes.sh` | Phase 1.1 Basic token tests | curl, jq |
| `02-jwt-attacks.py` | Phase 1.2/1.3 alg confusion + claim tamper | python3, PyJWT |
| `03-bola-probes.sh` | Phase 2 Cross-user, ID enum, admin BFLA, mass assignment | curl, jq |
| `04-injection-probes.sh` | Phase 3 SQLi, NoSQLi, command, SSRF | curl, jq |
| `05-rate-limit.sh` | Phase 4 Burst + IP spoofing bypass | curl, jq |
| `05-burst.k6.js` | Phase 4.4 k6 burst load (separate run) | k6 |
| `06-info-disclosure.sh` | Phase 5 Headers, /docs, GraphQL introspect, timing | curl, jq |
| `07-supply-chain.sh` | Phase 6 pip-audit / govulncheck / bun audit | per-stack |
| `08-cors-headers.sh` | Phase 7 Origin reflection, sec headers | curl, jq |
| `run-all.sh` | Orchestrator (00→08, except 05-burst.k6.js) | bash |
| `lib/common.sh` | Shared helpers | — |
| `lib/report.py` | Aggregates `findings.jsonl` → `report.md` | python3 |

## Finding Format

Each script appends one JSON-Lines record per finding:

```json
{
  "id": "AUTH-001",
  "phase": "01-auth-probes",
  "severity": "high",
  "owasp": "API2:2023",
  "endpoint": "POST /api/protected",
  "evidence": {"status": 200, "request_headers": {}, "response_excerpt": "..."},
  "impact": "Endpoint accepts requests without authentication.",
  "remediation": "Apply auth middleware to all non-public routes.",
  "timestamp": "2026-05-06T12:34:56Z"
}
```

`severity` ∈ {`critical`, `high`, `medium`, `low`, `info`}. CVSS bands match `references/REPORT_TEMPLATE.md`.

## Aggregating Findings

After running scripts, generate the human-readable report:

```bash
python3 lib/report.py out/findings.jsonl > out/report.md
```

The report groups findings by severity and includes counts.

## Exit Codes

- `0` — script ran cleanly, regardless of findings
- `1` — invalid configuration (missing required env var, target unreachable)
- `2` — authorization not confirmed (only `run-all.sh`)

Findings themselves never cause non-zero exit (they are output, not errors). CI gating should `jq` the JSONL to count findings by severity.

## CI Integration Example

```yaml
# .github/workflows/security-probes.yml
- run: ./skills/code-security-review/scripts/run-all.sh
  env:
    TARGET: ${{ secrets.STAGING_URL }}
    TOKEN_USER_A: ${{ secrets.STAGING_TOKEN_A }}
    TOKEN_USER_B: ${{ secrets.STAGING_TOKEN_B }}
    USER_A_RESOURCE_ID: ${{ secrets.STAGING_USER_A_RESOURCE }}
    ORIGIN_ALLOWED: ${{ secrets.STAGING_ALLOWED_ORIGIN }}
    I_HAVE_AUTHORIZATION: 1
- run: |
    CRIT=$(jq -s '[.[] | select(.severity=="critical")] | length' out/findings.jsonl)
    HIGH=$(jq -s '[.[] | select(.severity=="high")] | length' out/findings.jsonl)
    if [ "$CRIT" -gt 0 ] || [ "$HIGH" -gt 0 ]; then
      echo "Critical/High findings present: $CRIT critical, $HIGH high"
      exit 1
    fi
```

## Limitations

- Scripts are **black-box probes**. They detect vulnerabilities visible from outside the API. White-box code review must come from `references/DESIGN_CONTROLS.md` + framework-specific skills (`@golang-api-security`, `@nextjs-security-pro`).
- `02-jwt-attacks.py` requires a sample JWT; it cannot fabricate one for an unknown signing scheme.
- Rate limit probes can be detected by the target. Run during low-traffic windows or coordinate with ops.
- `05-burst.k6.js` is **not invoked by run-all.sh** — burst load can disrupt staging environments. Run manually: `k6 run 05-burst.k6.js -e TARGET=$TARGET`.
