#!/usr/bin/env bash
# Phase 4 — Rate limiting probes (HTTP only; for k6 load see 05-burst.k6.js).
# Tests: basic burst hits 429, X-Forwarded-For rotation bypass, login brute-force protection.
#
# Reads:
#   TARGET
#   RATE_PATH   (default /api/data)
#   RATE_LIMIT  (default 100)             — expected req/min limit on RATE_PATH
#   LOGIN_PATH  (default /auth/login)
#   LOGIN_FIELD_USER (default email)
#   LOGIN_FIELD_PASS (default password)
#   TOKEN (optional)
# Writes: out/findings.jsonl

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_env TARGET

RATE_PATH="${RATE_PATH:-/api/data}"
RATE_LIMIT="${RATE_LIMIT:-100}"
LOGIN_PATH="${LOGIN_PATH:-/auth/login}"
LOGIN_FIELD_USER="${LOGIN_FIELD_USER:-email}"
LOGIN_FIELD_PASS="${LOGIN_FIELD_PASS:-password}"

AUTH_HEADERS=()
if [ -n "${TOKEN:-}" ]; then
  AUTH_HEADERS=(-H "Authorization: Bearer $TOKEN")
fi

# Cap at 200 requests so probes finish in reasonable time even when limits are high
BURST_TOTAL=$((RATE_LIMIT + 5))
if [ "$BURST_TOTAL" -gt 200 ]; then BURST_TOTAL=200; fi

# ---------------------------------------------------------------------------
# Check 1 — Basic burst should yield at least one 429
# ---------------------------------------------------------------------------
log_info "Burst test: $BURST_TOTAL requests to $RATE_PATH..."
got_429=0
got_200=0
last_status=""
for i in $(seq 1 "$BURST_TOTAL"); do
  result=$(http_request GET "$RATE_PATH" "${AUTH_HEADERS[@]}" --max-time 5 || true)
  last_status="${result%% *}"
  case "$last_status" in
    429) got_429=$((got_429 + 1)) ;;
    200) got_200=$((got_200 + 1)) ;;
  esac
done

if [ "$got_429" = "0" ] && [ "$got_200" -gt "$RATE_LIMIT" ]; then
  evidence=$(build_evidence \
    "burst_total=$BURST_TOTAL" \
    "got_200=$got_200" \
    "got_429=$got_429" \
    "expected_limit=$RATE_LIMIT" \
    "path=$RATE_PATH")
  emit_finding \
    "RATE-001" "high" "API4:2023 Unrestricted Resource Consumption" \
    "GET $RATE_PATH" \
    "Sent $BURST_TOTAL requests, received $got_200 successful responses and zero 429s — rate limiting absent or misconfigured." \
    "Add a rate-limit middleware (sliding window for auth, token bucket for general). Recommended thresholds: ≤100/min for general API, ≤5/15min for auth." \
    "$evidence"
fi

# ---------------------------------------------------------------------------
# Check 2 — X-Forwarded-For rotation should NOT reset the limit
# ---------------------------------------------------------------------------
log_info "X-Forwarded-For bypass test on $RATE_PATH..."
spoofed_429=0
for i in $(seq 1 50); do
  result=$(http_request GET "$RATE_PATH" \
    "${AUTH_HEADERS[@]}" \
    -H "X-Forwarded-For: 10.99.0.$((i % 250 + 1))" \
    --max-time 5 || true)
  last_status="${result%% *}"
  if [ "$last_status" = "429" ]; then
    spoofed_429=$((spoofed_429 + 1))
  fi
done

# If the previous burst reached 429 but spoofed IPs still hit 200 only, that proves bypass
if [ "$got_429" -gt 0 ] && [ "$spoofed_429" = "0" ]; then
  evidence=$(build_evidence \
    "spoofed_requests=50" \
    "spoofed_429s=$spoofed_429" \
    "previous_burst_429s=$got_429" \
    "path=$RATE_PATH")
  emit_finding \
    "RATE-002" "high" "API4:2023 + API8:2023 Misconfiguration" \
    "GET $RATE_PATH (X-Forwarded-For rotation)" \
    "Rate limit can be bypassed by rotating the X-Forwarded-For header — server is using forwarded IP without trust validation." \
    "Trust X-Forwarded-For only when behind a known reverse proxy. Use the real connection remote IP, or validate the chain against a trusted proxy list." \
    "$evidence"
fi

# ---------------------------------------------------------------------------
# Check 3 — Auth endpoint brute-force protection
# ---------------------------------------------------------------------------
log_info "Brute-force probe on $LOGIN_PATH (10 wrong passwords)..."
brute_429=0
for i in $(seq 1 10); do
  payload=$(python3 -c "
import json,sys
print(json.dumps({sys.argv[1]: 'sec-probe@example.com', sys.argv[2]: f'wrong_pw_{sys.argv[3]}'}))
" "$LOGIN_FIELD_USER" "$LOGIN_FIELD_PASS" "$i")
  result=$(http_request POST "$LOGIN_PATH" \
    -H "Content-Type: application/json" \
    --data "$payload" \
    --max-time 5 || true)
  last_status="${result%% *}"
  if [ "$last_status" = "429" ]; then
    brute_429=$((brute_429 + 1))
  fi
done

if [ "$brute_429" = "0" ]; then
  evidence=$(build_evidence \
    "attempts=10" \
    "got_429=$brute_429" \
    "path=$LOGIN_PATH")
  emit_finding \
    "RATE-003" "high" "API4:2023 + API2:2023 Broken Auth" \
    "POST $LOGIN_PATH" \
    "10 failed login attempts produced zero 429s — endpoint lacks brute-force protection. Credential stuffing and password spraying are not mitigated." \
    "Apply strict per-account and per-IP rate limits on auth endpoints (e.g. 5 attempts per 15 minutes). Combine with account lockout, MFA, or CAPTCHA after threshold." \
    "$evidence"
fi

log_ok "Rate limit probes complete."
