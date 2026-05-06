#!/usr/bin/env bash
# Phase 5 — Information disclosure probes.
# Tests: malformed JSON does not leak stack traces, GraphQL introspection disabled in prod,
#        timing oracle on resource fetch (own vs. nonexistent), version headers (covered in 00).
#
# Reads:
#   TARGET, TOKEN (optional)
#   GRAPHQL_PATH         (default /graphql)
#   POST_TARGET_PATH     (default /api/users)
#   OWN_RESOURCE_PATH    (default /api/users/me)
#   NONEXISTENT_PATH     (default /api/users/nonexistent_$random)
# Writes: out/findings.jsonl

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_env TARGET

GRAPHQL_PATH="${GRAPHQL_PATH:-/graphql}"
POST_TARGET_PATH="${POST_TARGET_PATH:-/api/users}"
OWN_RESOURCE_PATH="${OWN_RESOURCE_PATH:-/api/users/me}"
NONEXISTENT_PATH="${NONEXISTENT_PATH:-/api/users/_nonexistent_$$_$(date +%s)}"

AUTH_HEADERS=()
if [ -n "${TOKEN:-}" ]; then
  AUTH_HEADERS=(-H "Authorization: Bearer $TOKEN")
fi

# ---------------------------------------------------------------------------
# Check 1 — Malformed JSON should not leak stack traces
# ---------------------------------------------------------------------------
log_info "Probing malformed-JSON handling on $POST_TARGET_PATH..."
result=$(http_request POST "$POST_TARGET_PATH" \
  -H "Content-Type: application/json" \
  "${AUTH_HEADERS[@]}" \
  --data '{"broken json' \
  --max-time 10 || true)
status="${result%% *}"
body=$(head -c 1000 "$RESP_BODY" 2>/dev/null || true)

if echo "$body" | grep -qiE 'traceback|stack trace|at [a-zA-Z0-9_\.]+\.[a-zA-Z0-9_]+\(|file ".*\.py"|panic:|goroutine [0-9]+|node_modules|/Users/|/home/|/var/www'; then
  body_excerpt=$(printf '%s' "$body" | head -c 300 | tr -d '\000-\031')
  evidence=$(build_evidence \
    "status=$status" \
    "path=$POST_TARGET_PATH" \
    "body_excerpt=$body_excerpt")
  emit_finding \
    "INFO-001" "medium" "API8:2023 Security Misconfiguration" \
    "POST $POST_TARGET_PATH (malformed body)" \
    "Server returns stack traces, file paths, or framework internals when given malformed JSON." \
    "Install a global error handler that returns a generic 400 response. Log full details server-side only." \
    "$evidence"
fi

# ---------------------------------------------------------------------------
# Check 2 — GraphQL introspection in production
# ---------------------------------------------------------------------------
log_info "Probing GraphQL introspection on $GRAPHQL_PATH..."
introspection_query='{"query":"{ __schema { types { name } } }"}'
result=$(http_request POST "$GRAPHQL_PATH" \
  -H "Content-Type: application/json" \
  "${AUTH_HEADERS[@]}" \
  --data "$introspection_query" \
  --max-time 10 || true)
status="${result%% *}"
body=$(head -c 1000 "$RESP_BODY" 2>/dev/null || true)

if [ "$status" = "200" ] && echo "$body" | grep -q '"__schema"'; then
  type_count=$(echo "$body" | grep -o '"name"' | wc -l | tr -d ' ')
  evidence=$(build_evidence \
    "status=$status" \
    "path=$GRAPHQL_PATH" \
    "schema_types_seen=$type_count")
  emit_finding \
    "INFO-002" "medium" "API9:2023 Improper Inventory Management" \
    "POST $GRAPHQL_PATH" \
    "GraphQL introspection is enabled in production — full schema (types, queries, mutations) is exposed." \
    "Disable introspection in production GraphQL server config. Rely on API documentation tooling for staging only." \
    "$evidence"
elif [ "$status" = "404" ] || [ "$status" = "405" ]; then
  log_dim "GraphQL endpoint not present (HTTP $status) — skipping introspection check."
fi

# ---------------------------------------------------------------------------
# Check 3 — Timing oracle: resource I own vs. nonexistent
# ---------------------------------------------------------------------------
if [ -n "${TOKEN:-}" ]; then
  log_info "Timing oracle probe (own vs. nonexistent)..."
  measure_timing() {
    local path="$1"
    local total=0
    local samples=5
    for _ in $(seq 1 $samples); do
      local start end
      start=$(python3 -c 'import time; print(time.time())')
      http_request GET "$path" "${AUTH_HEADERS[@]}" --max-time 5 >/dev/null || true
      end=$(python3 -c 'import time; print(time.time())')
      total=$(python3 -c "print($total + ($end - $start))")
    done
    python3 -c "print(round($total / $samples, 4))"
  }

  t_own=$(measure_timing "$OWN_RESOURCE_PATH")
  t_none=$(measure_timing "$NONEXISTENT_PATH")
  log_dim "  own=${t_own}s nonexistent=${t_none}s"
  diff=$(python3 -c "print(round(abs($t_own - $t_none), 4))")
  # >100ms diff is suggestive of a timing oracle
  if python3 -c "import sys; sys.exit(0 if $diff > 0.1 else 1)"; then
    evidence=$(build_evidence \
      "own_avg_seconds=$t_own" \
      "nonexistent_avg_seconds=$t_none" \
      "delta_seconds=$diff" \
      "samples=5")
    emit_finding \
      "INFO-003" "low" "API3:2023 Excessive Information" \
      "GET $OWN_RESOURCE_PATH vs. GET $NONEXISTENT_PATH" \
      "Response time differs by ${diff}s between an existing and a nonexistent resource — timing oracle may allow attackers to enumerate resource IDs." \
      "Equalize response time for the existence/non-existence cases. Use constant-time comparison and fixed-cost lookups when feasible." \
      "$evidence"
  fi
fi

log_ok "Information disclosure probes complete."
