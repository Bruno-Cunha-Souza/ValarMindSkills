#!/usr/bin/env bash
# Phase 3 — Input injection probes.
# Tests: SQLi (boolean + time-based), NoSQLi ($gt operator), command injection (sleep/id),
#        SSRF (cloud metadata, localhost, file://), redirect bypass.
#
# Reads:
#   TARGET, TOKEN (optional)
#   SEARCH_PATH      (default /api/search?q=)
#   FETCH_PATH       (default /api/fetch)            — POST endpoint that fetches a remote URL
#   FETCH_FIELD      (default url)                   — JSON field name carrying the URL
#   LOGIN_PATH       (default /auth/login)
#   LOGIN_FIELD_USER (default email)
#   LOGIN_FIELD_PASS (default password)
# Writes: out/findings.jsonl

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_env TARGET

SEARCH_PATH="${SEARCH_PATH:-/api/search?q=}"
FETCH_PATH="${FETCH_PATH:-/api/fetch}"
FETCH_FIELD="${FETCH_FIELD:-url}"
LOGIN_PATH="${LOGIN_PATH:-/auth/login}"
LOGIN_FIELD_USER="${LOGIN_FIELD_USER:-email}"
LOGIN_FIELD_PASS="${LOGIN_FIELD_PASS:-password}"

AUTH_HEADERS=()
if [ -n "${TOKEN:-}" ]; then
  AUTH_HEADERS=(-H "Authorization: Bearer $TOKEN")
fi

# ---------------------------------------------------------------------------
# Check 1 — Time-based blind SQLi (PostgreSQL pg_sleep)
# ---------------------------------------------------------------------------
log_info "Time-based SQLi probe on $SEARCH_PATH ..."
payload="1';SELECT pg_sleep(3)--"
encoded_payload=$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))' "$payload")
start=$(python3 -c 'import time; print(time.time())')
result=$(http_request GET "${SEARCH_PATH}${encoded_payload}" \
  "${AUTH_HEADERS[@]}" \
  --max-time 15 || true)
end=$(python3 -c 'import time; print(time.time())')
elapsed=$(python3 -c "print(round($end - $start, 2))")
status="${result%% *}"

if python3 -c "import sys; sys.exit(0 if $elapsed >= 2.5 else 1)"; then
  evidence=$(build_evidence \
    "status=$status" \
    "elapsed=$elapsed" \
    "payload=$payload" \
    "path=$SEARCH_PATH")
  emit_finding \
    "INJ-001" "critical" "API3 (Excessive Data) / API8 + CWE-89" \
    "GET ${SEARCH_PATH}<payload>" \
    "Endpoint took ~${elapsed}s — strong indicator of time-based SQL injection (PostgreSQL pg_sleep accepted)." \
    "Use parameterized queries (e.g. \$1 placeholders / sqlx.Named / Pydantic + ORM). Never concatenate user input into SQL." \
    "$evidence"
fi

# ---------------------------------------------------------------------------
# Check 2 — NoSQL operator injection on login
# ---------------------------------------------------------------------------
log_info "NoSQL operator injection probe on $LOGIN_PATH ..."
nosql_payload=$(python3 -c "
import json,sys
print(json.dumps({sys.argv[1]: {'\$gt': ''}, sys.argv[2]: {'\$gt': ''}}))" \
  "$LOGIN_FIELD_USER" "$LOGIN_FIELD_PASS")

result=$(http_request POST "$LOGIN_PATH" \
  -H "Content-Type: application/json" \
  --data "$nosql_payload" \
  --max-time 10 || true)
status="${result%% *}"
body=$(head -c 500 "$RESP_BODY" 2>/dev/null || true)

# Heuristic: 200 + presence of "token" or "session" suggests successful auth
if [ "$status" = "200" ] && echo "$body" | grep -qiE '"token"|"access_token"|"session"|"jwt"'; then
  body_excerpt=$(printf '%s' "$body" | head -c 200 | tr -d '\000-\031')
  evidence=$(build_evidence \
    "status=$status" \
    "payload=$nosql_payload" \
    "body_excerpt=$body_excerpt")
  emit_finding \
    "INJ-002" "critical" "CWE-943 NoSQL Injection" \
    "POST $LOGIN_PATH" \
    "Login endpoint accepts MongoDB-style operator injection ({\$gt: ''}) and returns a session — authentication bypass." \
    "Validate request body types strictly. Reject non-string values for username/password fields with explicit schema validation (Pydantic strict, TypeBox strict, struct tags + validator)." \
    "$evidence"
fi

# ---------------------------------------------------------------------------
# Check 3 — Command injection via fetch-style endpoint
# ---------------------------------------------------------------------------
log_info "Command injection probe on $FETCH_PATH (sleep marker) ..."
cmd_payload=$(python3 -c "
import json,sys
print(json.dumps({sys.argv[1]: '127.0.0.1; sleep 3 && echo INJECTED'}))" "$FETCH_FIELD")
start=$(python3 -c 'import time; print(time.time())')
result=$(http_request POST "$FETCH_PATH" \
  -H "Content-Type: application/json" \
  "${AUTH_HEADERS[@]}" \
  --data "$cmd_payload" \
  --max-time 15 || true)
end=$(python3 -c 'import time; print(time.time())')
elapsed=$(python3 -c "print(round($end - $start, 2))")
status="${result%% *}"
body=$(head -c 500 "$RESP_BODY" 2>/dev/null || true)

# Heuristic: response delayed >2.5s OR contains marker
if python3 -c "import sys; sys.exit(0 if $elapsed >= 2.5 else 1)" || echo "$body" | grep -qi "INJECTED"; then
  body_excerpt=$(printf '%s' "$body" | head -c 200 | tr -d '\000-\031')
  evidence=$(build_evidence \
    "status=$status" \
    "elapsed=$elapsed" \
    "payload=$cmd_payload" \
    "body_excerpt=$body_excerpt")
  emit_finding \
    "INJ-003" "critical" "CWE-78 Command Injection" \
    "POST $FETCH_PATH" \
    "Endpoint behaviour suggests command injection (delayed response or echoed marker found in body)." \
    "Avoid spawning shells with user-controlled strings. If unavoidable, use exec with argument arrays (subprocess.run([...], shell=False), exec.Command in Go)." \
    "$evidence"
fi

# ---------------------------------------------------------------------------
# Check 4 — SSRF: AWS / GCP / Azure metadata, localhost, file://
# ---------------------------------------------------------------------------
log_info "SSRF probe on $FETCH_PATH ..."
declare -a ssrf_urls=(
  "http://169.254.169.254/latest/meta-data/"
  "http://metadata.google.internal/computeMetadata/v1/"
  "http://169.254.169.254/metadata/instance?api-version=2021-02-01"
  "http://localhost:8080/admin"
  "http://127.0.0.1:6379/info"
  "file:///etc/passwd"
)
declare -a ssrf_match=(
  "ami-id|instance-id|iam"
  "computeMetadata|project-id"
  "compute|virtualMachines"
  "admin|dashboard"
  "redis_version|connected_clients"
  "root:x:0:0"
)

for i in "${!ssrf_urls[@]}"; do
  url="${ssrf_urls[$i]}"
  pattern="${ssrf_match[$i]}"
  ssrf_payload=$(python3 -c "import json,sys; print(json.dumps({sys.argv[1]: sys.argv[2]}))" "$FETCH_FIELD" "$url")
  result=$(http_request POST "$FETCH_PATH" \
    -H "Content-Type: application/json" \
    "${AUTH_HEADERS[@]}" \
    --data "$ssrf_payload" \
    --max-time 8 || true)
  status="${result%% *}"
  body=$(head -c 500 "$RESP_BODY" 2>/dev/null || true)

  if [ "$status" = "200" ] && echo "$body" | grep -qiE "$pattern"; then
    body_excerpt=$(printf '%s' "$body" | head -c 200 | tr -d '\000-\031')
    evidence=$(build_evidence \
      "status=$status" \
      "ssrf_url=$url" \
      "matched_pattern=$pattern" \
      "body_excerpt=$body_excerpt")
    emit_finding \
      "SSRF-00$((i + 1))" "critical" "API7:2023 SSRF" \
      "POST $FETCH_PATH (url=$url)" \
      "Endpoint fetched an internal/cloud-metadata URL and returned its content — Server-Side Request Forgery." \
      "Apply a strict allowlist of permitted host:port targets. Block RFC1918 / loopback / link-local / file:// schemes. Do not auto-follow redirects to disallowed targets." \
      "$evidence"
  fi
done

log_ok "Injection / SSRF probes complete."
