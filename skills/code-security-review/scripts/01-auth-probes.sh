#!/usr/bin/env bash
# Phase 1 — Authentication probes.
# Checks: missing token returns 401, invalid token returns 401, expired token returns 401,
# valid token from another user returns 403 on owner-bound resource.
#
# Reads:  TARGET, PROTECTED_PATH (default /api/me), TOKEN_USER_A, TOKEN_USER_B
#         EXPIRED_TOKEN (optional), USER_A_RESOURCE_ID, RESOURCE_PATH (default /api/orders/{id})
# Writes: out/findings.jsonl

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_env TARGET

PROTECTED_PATH="${PROTECTED_PATH:-/api/me}"
RESOURCE_PATH="${RESOURCE_PATH:-/api/orders/{id}}"

# ---------------------------------------------------------------------------
# Check 1 — No token must return 401 on a protected endpoint
# ---------------------------------------------------------------------------
log_info "Probing $PROTECTED_PATH without auth header..."
result=$(http_request GET "$PROTECTED_PATH" --max-time 10 || true)
status="${result%% *}"

if [ "$status" = "200" ]; then
  evidence=$(build_evidence "status=$status" "path=$PROTECTED_PATH")
  emit_finding \
    "AUTH-001" "critical" "API2:2023 Broken Authentication" \
    "GET $PROTECTED_PATH" \
    "Endpoint marked as protected returns 200 OK without any authentication header — full auth bypass." \
    "Apply an authentication middleware/dependency to this route. Reject requests with no Authorization header at the framework layer." \
    "$evidence"
elif [ "$status" != "401" ] && [ "$status" != "403" ]; then
  evidence=$(build_evidence "status=$status" "expected=401")
  emit_finding \
    "AUTH-002" "medium" "API2:2023 Broken Authentication" \
    "GET $PROTECTED_PATH" \
    "Missing-token request returned $status instead of 401 — non-standard auth handling may hide other issues." \
    "Ensure all auth failures map to 401 with WWW-Authenticate: Bearer header." \
    "$evidence"
fi

# ---------------------------------------------------------------------------
# Check 2 — Garbage token must return 401 (not 500, not 200)
# ---------------------------------------------------------------------------
log_info "Probing $PROTECTED_PATH with garbage Bearer token..."
result=$(http_request GET "$PROTECTED_PATH" \
  -H "Authorization: Bearer not_a_real_token_$(date +%s)" \
  --max-time 10 || true)
status="${result%% *}"

if [ "$status" = "200" ]; then
  evidence=$(build_evidence "status=$status" "path=$PROTECTED_PATH")
  emit_finding \
    "AUTH-003" "critical" "API2:2023 Broken Authentication" \
    "GET $PROTECTED_PATH" \
    "Endpoint accepts an invalid Bearer token — auth verification is broken or absent." \
    "Verify token signature and audience/issuer claims. Reject malformed tokens before any handler runs." \
    "$evidence"
elif [ "$status" = "500" ]; then
  evidence=$(build_evidence "status=$status" "path=$PROTECTED_PATH")
  emit_finding \
    "AUTH-004" "medium" "API8:2023 Security Misconfiguration" \
    "GET $PROTECTED_PATH" \
    "Garbage token causes a 500 Internal Server Error — unhandled exception in auth path may leak diagnostics." \
    "Catch JWT decode errors and return a clean 401. Avoid letting parse failures bubble to the server's default error handler." \
    "$evidence"
fi

# ---------------------------------------------------------------------------
# Check 3 — Expired token must return 401 (informational; only if EXPIRED_TOKEN is provided)
# ---------------------------------------------------------------------------
if [ -n "${EXPIRED_TOKEN:-}" ]; then
  log_info "Probing $PROTECTED_PATH with EXPIRED_TOKEN..."
  result=$(http_request GET "$PROTECTED_PATH" \
    -H "Authorization: Bearer $EXPIRED_TOKEN" \
    --max-time 10 || true)
  status="${result%% *}"
  if [ "$status" = "200" ]; then
    evidence=$(build_evidence "status=$status" "path=$PROTECTED_PATH")
    emit_finding \
      "AUTH-005" "critical" "API2:2023 Broken Authentication" \
      "GET $PROTECTED_PATH" \
      "Expired JWT is accepted — token TTL is not validated." \
      "Validate exp claim in every request. Most JWT libraries do this automatically when leeway is set; ensure it is not disabled." \
      "$evidence"
  fi
fi

# ---------------------------------------------------------------------------
# Check 4 — Cross-user access on owner-bound resource (only if both tokens + RESOURCE_ID are set)
# ---------------------------------------------------------------------------
if [ -n "${TOKEN_USER_A:-}" ] && [ -n "${TOKEN_USER_B:-}" ] && [ -n "${USER_A_RESOURCE_ID:-}" ]; then
  resource_path="${RESOURCE_PATH//\{id\}/$USER_A_RESOURCE_ID}"
  log_info "Probing $resource_path with user_b's token (BOLA pre-check)..."
  result=$(http_request GET "$resource_path" \
    -H "Authorization: Bearer $TOKEN_USER_B" \
    --max-time 10 || true)
  status="${result%% *}"
  if [ "$status" = "200" ]; then
    body_excerpt=$(head -c 200 "$RESP_BODY" 2>/dev/null | tr -d '\000-\031')
    evidence=$(build_evidence \
      "status=$status" \
      "path=$resource_path" \
      "body_excerpt=$body_excerpt")
    emit_finding \
      "AUTH-006" "critical" "API1:2023 BOLA" \
      "GET $resource_path" \
      "User B's token can read user A's resource — authorization bypass on owner-bound object." \
      "Verify resource.owner_id == current_user.id in the handler before returning the resource. Return 404 (not 403) to prevent enumeration." \
      "$evidence"
  fi
fi

log_ok "Auth probes complete."
