#!/usr/bin/env bash
# Phase 2 — BOLA / IDOR / mass assignment / BFLA probes.
# Reads:
#   TARGET, TOKEN_USER_A, TOKEN_USER_B, USER_A_RESOURCE_ID
#   RESOURCE_PATH (default /api/orders/{id})
#   ENUM_PATH     (default /api/users/{id})    — endpoint to probe with sequential IDs
#   ENUM_RANGE    (default 1-10)               — IDs to enumerate
#   ADMIN_PATH    (default /api/admin/users)   — admin endpoint to probe with regular user
#   PROFILE_PATH  (default /api/users/profile) — endpoint for mass-assignment test
# Writes: out/findings.jsonl

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_env TARGET TOKEN_USER_A TOKEN_USER_B

RESOURCE_PATH="${RESOURCE_PATH:-/api/orders/{id}}"
ENUM_PATH="${ENUM_PATH:-/api/users/{id}}"
ENUM_RANGE="${ENUM_RANGE:-1-10}"
ADMIN_PATH="${ADMIN_PATH:-/api/admin/users}"
PROFILE_PATH="${PROFILE_PATH:-/api/users/profile}"

# ---------------------------------------------------------------------------
# Check 1 — Cross-user access (already checked in 01-auth, repeated here for completeness
#           with explicit USER_A_RESOURCE_ID requirement)
# ---------------------------------------------------------------------------
if [ -n "${USER_A_RESOURCE_ID:-}" ]; then
  resource_path="${RESOURCE_PATH//\{id\}/$USER_A_RESOURCE_ID}"
  log_info "Cross-user access on $resource_path with user_b token..."
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
      "BOLA-001" "critical" "API1:2023 BOLA" \
      "GET $resource_path" \
      "User B reads user A's resource — handler does not verify resource ownership before returning." \
      "Add: if resource.owner_id != current_user.id: return 404. Apply consistently across all owner-bound endpoints." \
      "$evidence"
  fi
fi

# ---------------------------------------------------------------------------
# Check 2 — Sequential ID enumeration with user_b's token
# ---------------------------------------------------------------------------
log_info "Enumerating $ENUM_PATH IDs $ENUM_RANGE with user_b token..."
range_start="${ENUM_RANGE%%-*}"
range_end="${ENUM_RANGE##*-}"
hits=0
hit_ids=""
for id in $(seq "$range_start" "$range_end"); do
  enum_path="${ENUM_PATH//\{id\}/$id}"
  result=$(http_request GET "$enum_path" \
    -H "Authorization: Bearer $TOKEN_USER_B" \
    --max-time 5 || true)
  status="${result%% *}"
  if [ "$status" = "200" ]; then
    hits=$((hits + 1))
    hit_ids="$hit_ids $id"
  fi
done

# Heuristic: if more than 1 ID returned 200 with user_b's token, it's likely the user
# can read other users' resources. (If only the user's own ID matches, hits == 1.)
if [ "$hits" -gt 1 ]; then
  evidence=$(build_evidence \
    "endpoint=$ENUM_PATH" \
    "ids_with_200=$hit_ids" \
    "total_hits=$hits" \
    "range=$ENUM_RANGE")
  emit_finding \
    "BOLA-002" "high" "API1:2023 BOLA" \
    "GET $ENUM_PATH (sequential enumeration)" \
    "User B can read $hits resources at sequential IDs ($hit_ids) — endpoint is enumerable and lacks per-ID authorization." \
    "Validate ownership/visibility on every fetch. Use UUIDs instead of sequential IDs to make enumeration impractical (defence in depth, not a fix)." \
    "$evidence"
fi

# ---------------------------------------------------------------------------
# Check 3 — Admin endpoint accessible with regular user token (BFLA)
# ---------------------------------------------------------------------------
log_info "Probing $ADMIN_PATH with regular user token (BFLA test)..."
result=$(http_request GET "$ADMIN_PATH" \
  -H "Authorization: Bearer $TOKEN_USER_A" \
  --max-time 10 || true)
status="${result%% *}"
if [ "$status" = "200" ]; then
  body_excerpt=$(head -c 200 "$RESP_BODY" 2>/dev/null | tr -d '\000-\031')
  evidence=$(build_evidence \
    "status=$status" \
    "path=$ADMIN_PATH" \
    "body_excerpt=$body_excerpt")
  emit_finding \
    "BFLA-001" "critical" "API5:2023 BFLA" \
    "GET $ADMIN_PATH" \
    "Regular user can call admin endpoint — function-level authorization is missing." \
    "Apply role-based authorization middleware that rejects non-admin tokens at the route group level. Do not rely on UI to hide admin features." \
    "$evidence"
fi

# ---------------------------------------------------------------------------
# Check 4 — Mass assignment (try to inject role/admin/credits/is_verified)
# ---------------------------------------------------------------------------
log_info "Mass-assignment probe on $PROFILE_PATH..."
payload='{"name":"sec-probe","role":"admin","roles":["admin"],"is_admin":true,"is_verified":true,"credits":99999,"balance":99999}'
result=$(http_request PATCH "$PROFILE_PATH" \
  -H "Authorization: Bearer $TOKEN_USER_A" \
  -H "Content-Type: application/json" \
  --data "$payload" \
  --max-time 10 || true)
status="${result%% *}"

# Method may not be supported — try POST as fallback
if [ "$status" = "405" ] || [ "$status" = "404" ]; then
  result=$(http_request POST "$PROFILE_PATH" \
    -H "Authorization: Bearer $TOKEN_USER_A" \
    -H "Content-Type: application/json" \
    --data "$payload" \
    --max-time 10 || true)
  status="${result%% *}"
fi

if [ "$status" = "200" ] || [ "$status" = "201" ]; then
  body=$(head -c 1000 "$RESP_BODY" 2>/dev/null || true)
  if echo "$body" | grep -qiE '"role"\s*:\s*"admin"|"is_admin"\s*:\s*true|"credits"\s*:\s*99999|"balance"\s*:\s*99999'; then
    body_excerpt=$(printf '%s' "$body" | head -c 300 | tr -d '\000-\031')
    evidence=$(build_evidence \
      "status=$status" \
      "path=$PROFILE_PATH" \
      "payload=$payload" \
      "body_excerpt=$body_excerpt")
    emit_finding \
      "BOPLA-001" "critical" "API3:2023 Broken Object Property Level Authorization" \
      "POST/PATCH $PROFILE_PATH" \
      "Server accepted unexpected fields (role/is_admin/credits) in profile update — mass-assignment vulnerability." \
      "Define explicit DTOs/schemas that allow only the fields the user may update. Use Pydantic with model_config strict=True / TypeBox additionalProperties:false / explicit validator structs." \
      "$evidence"
  fi
fi

log_ok "BOLA / BFLA / mass-assignment probes complete."
