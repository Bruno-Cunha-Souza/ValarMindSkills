# Report Template

Standardized format for documenting findings from the testing workflow in `TESTING_PHASES.md`.

## Test Report Template

For each finding, document:

| Field | Content |
| --- | --- |
| **Vulnerability ID** | VULN-001 (sequential) |
| **Severity** | Critical / High / Medium / Low / Informational |
| **OWASP Category** | e.g., API1:2023 BOLA, API4:2023 Unrestricted Resource Consumption |
| **Affected Endpoint** | `POST /api/auth/login` |
| **HTTP Method** | POST |
| **Evidence** | Request + Response (sanitize sensitive data) |
| **Impact** | What an attacker can achieve |
| **Remediation** | Specific fix for the framework in use |
| **References** | CVE, CWE, OWASP link |

## Severity Reference

| Severity | CVSS Range | Example |
| --- | --- | --- |
| **Critical** | 9.0–10.0 | BOLA returning any user's data, auth bypass |
| **High** | 7.0–8.9 | SQLi, SSRF reaching internal services, missing auth on endpoints |
| **Medium** | 4.0–6.9 | Missing rate limiting, CORS misconfiguration, sensitive fields in response |
| **Low** | 1.0–3.9 | Version disclosure, missing security headers |
| **Informational** | N/A | Docs exposed in staging, debug logs |

## Example Finding

```markdown
### VULN-007 — BOLA on `/api/orders/{id}`

| Field | Value |
| --- | --- |
| Severity | **Critical** (CVSS 9.1) |
| OWASP Category | API1:2023 Broken Object Level Authorization |
| Endpoint | `GET /api/orders/{id}` |
| Method | GET |

**Evidence:**

```http
GET /api/orders/847 HTTP/1.1
Host: target.example.com
Authorization: Bearer <user_b_token>

HTTP/1.1 200 OK
Content-Type: application/json

{"id": 847, "customer_id": "user_a", "total": 1299.00, "items": [...]}
```

**Impact:** `user_b` can enumerate sequential order IDs and retrieve any user's order history, including PII and payment totals.

**Remediation:** In the order handler, verify `order.customer_id == current_user.id` before returning the resource. Return `404 Not Found` (not `403`) to prevent enumeration.

**References:**
- OWASP API Security Top 10 (2023) — API1
- CWE-639: Authorization Bypass Through User-Controlled Key
```

## Reporting Tips

- **Sanitize evidence** — redact tokens, real PII, internal hostnames before sharing reports outside the security team.
- **Reproduce before filing** — flaky findings erode trust. Capture the exact request/response on a clean session.
- **Pair with remediation** — every finding should ship with a concrete fix referenced from `DESIGN_CONTROLS.md` (or framework docs).
- **Track severity drift** — if remediation introduces a downgrade (e.g., from Critical to Medium), document the residual risk explicitly.
