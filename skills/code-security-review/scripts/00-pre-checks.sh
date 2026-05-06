#!/usr/bin/env bash
# Phase 0 — Pre-test checks.
# Confirms the target is reachable and probes a few common production-misconfiguration
# flags (FastAPI docs exposure, debug-mode hints in headers, version disclosure).
# Reads:  TARGET
# Writes: out/findings.jsonl

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_env TARGET
ensure_target_reachable

# ---------------------------------------------------------------------------
# Check 1 — FastAPI / OpenAPI doc exposure
# ---------------------------------------------------------------------------
log_info "Checking exposed documentation paths..."
for path in /docs /redoc /openapi.json /swagger.json /api-docs; do
  result=$(http_request GET "$path" --max-time 10 || true)
  status="${result%% *}"
  if [ "$status" = "200" ]; then
    body_excerpt=$(head -c 200 "$RESP_BODY" 2>/dev/null | tr -d '\000-\031')
    evidence=$(build_evidence \
      "status=$status" \
      "path=$path" \
      "body_excerpt=$body_excerpt")
    emit_finding \
      "PRE-001" "medium" "API8:2023 Security Misconfiguration" \
      "GET $path" \
      "API documentation is exposed in production. Reveals endpoints, request schemas, and may aid further attacks." \
      "Disable docs in production: FastAPI(docs_url=None, redoc_url=None, openapi_url=None). Apply equivalent in other frameworks." \
      "$evidence"
  fi
done

# ---------------------------------------------------------------------------
# Check 2 — Server / X-Powered-By version disclosure
# ---------------------------------------------------------------------------
log_info "Checking for version-disclosing response headers..."
http_request GET "/" --max-time 10 >/dev/null || true

while IFS= read -r line; do
  case "${line,,}" in
    server:*|x-powered-by:*|x-aspnet-version:*|x-runtime:*|x-rack-cache:*)
      header_value="${line#*:}"
      header_value="${header_value## }"
      header_value="${header_value%$'\r'}"
      # only flag when there is a version-like substring (digit + dot)
      if [[ "$header_value" =~ [0-9]+\.[0-9]+ ]]; then
        evidence=$(build_evidence \
          "header=${line%%:*}" \
          "value=$header_value")
        emit_finding \
          "PRE-002" "low" "API8:2023 Security Misconfiguration" \
          "GET /" \
          "Server response reveals technology and version information ($header_value), aiding targeted exploitation." \
          "Strip or rewrite identifying headers at the reverse proxy / framework level." \
          "$evidence"
      fi
      ;;
  esac
done < "$RESP_HEADERS"

# ---------------------------------------------------------------------------
# Check 3 — Debug error verbosity (force a 404 with garbage path)
# ---------------------------------------------------------------------------
log_info "Probing error response verbosity..."
result=$(http_request GET "/__nonexistent_$$_$(date +%s)" --max-time 10 || true)
status="${result%% *}"
if [ -s "$RESP_BODY" ]; then
  body=$(head -c 1000 "$RESP_BODY")
  if echo "$body" | grep -qiE 'traceback|stack trace|at [a-zA-Z0-9_\.]+\.[a-zA-Z0-9_]+\(|file ".*\.py"|panic:|goroutine [0-9]+|nodejs|node_modules|/Users/|/home/'; then
    excerpt=$(printf '%s' "$body" | head -c 300 | tr -d '\000-\031')
    evidence=$(build_evidence \
      "status=$status" \
      "body_excerpt=$excerpt")
    emit_finding \
      "PRE-003" "medium" "API8:2023 Security Misconfiguration" \
      "GET /<nonexistent>" \
      "Error response leaks stack trace, file paths, or framework internals — aids fingerprinting and exploitation." \
      "Install a global error handler that returns a generic message in production. Log details server-side only." \
      "$evidence"
  fi
fi

log_ok "Pre-checks complete."
