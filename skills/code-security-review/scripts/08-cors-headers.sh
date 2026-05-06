#!/usr/bin/env bash
# Phase 7 — CORS & security headers.
# Tests: arbitrary-Origin reflection, wildcard + credentials misconfiguration,
#        presence of HSTS/X-Content-Type-Options/X-Frame-Options/CSP/Referrer-Policy.
#
# Reads:
#   TARGET
#   ORIGIN_ALLOWED (optional) — origin that *should* be reflected (for sanity check)
#   PROBE_PATH     (default /)
# Writes: out/findings.jsonl

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_env TARGET
PROBE_PATH="${PROBE_PATH:-/}"
EVIL_ORIGIN="https://evil.example.com"

# ---------------------------------------------------------------------------
# Helper — extract a header value (case-insensitive) from $RESP_HEADERS
# ---------------------------------------------------------------------------
header_value() {
  local name="$1"
  awk -v IGNORECASE=1 -v h="^${name}:" '
    $0 ~ h {
      sub(/^[^:]+:[[:space:]]*/, "", $0)
      sub(/\r$/, "", $0)
      print
      exit
    }
  ' "$RESP_HEADERS"
}

# ---------------------------------------------------------------------------
# Check 1 — Arbitrary Origin reflection
# ---------------------------------------------------------------------------
log_info "CORS reflection probe with Origin: $EVIL_ORIGIN ..."
http_request GET "$PROBE_PATH" \
  -H "Origin: $EVIL_ORIGIN" \
  --max-time 10 >/dev/null || true

allow_origin=$(header_value "access-control-allow-origin")
allow_credentials=$(header_value "access-control-allow-credentials")

if [ "$allow_origin" = "$EVIL_ORIGIN" ]; then
  evidence=$(build_evidence \
    "sent_origin=$EVIL_ORIGIN" \
    "access_control_allow_origin=$allow_origin" \
    "access_control_allow_credentials=$allow_credentials" \
    "path=$PROBE_PATH")
  if [ "${allow_credentials,,}" = "true" ]; then
    sev="critical"
    impact="Server reflects arbitrary Origin AND allows credentials — any malicious site can read authenticated responses cross-origin."
  else
    sev="high"
    impact="Server reflects arbitrary Origin in Access-Control-Allow-Origin — defeats the CORS-based isolation model."
  fi
  emit_finding \
    "CORS-001" "$sev" "API8:2023 Security Misconfiguration" \
    "GET $PROBE_PATH (Origin: $EVIL_ORIGIN)" \
    "$impact" \
    "Validate Origin against an explicit allowlist; never reflect untrusted values. If credentials must be allowed, the allowlist must be strict (no wildcard, no regex with .*)." \
    "$evidence"
fi

# ---------------------------------------------------------------------------
# Check 2 — Wildcard + credentials combination
# ---------------------------------------------------------------------------
http_request GET "$PROBE_PATH" \
  -H "Origin: $EVIL_ORIGIN" \
  --max-time 10 >/dev/null || true

allow_origin=$(header_value "access-control-allow-origin")
allow_credentials=$(header_value "access-control-allow-credentials")

if [ "$allow_origin" = "*" ] && [ "${allow_credentials,,}" = "true" ]; then
  evidence=$(build_evidence \
    "access_control_allow_origin=*" \
    "access_control_allow_credentials=true" \
    "path=$PROBE_PATH")
  emit_finding \
    "CORS-002" "critical" "API8:2023 + CVE-2025-34291 class" \
    "GET $PROBE_PATH" \
    "Server returns Access-Control-Allow-Origin: * AND Access-Control-Allow-Credentials: true — combination is forbidden by the CORS spec but is honored by some HTTP clients (curl, httpx), enabling SSRF and data exfiltration vectors." \
    "Use an explicit allowlist when credentials=true. Never combine wildcard origins with credentials." \
    "$evidence"
fi

# ---------------------------------------------------------------------------
# Check 3 — Required security headers
# ---------------------------------------------------------------------------
log_info "Security headers checklist on $PROBE_PATH..."
http_request GET "$PROBE_PATH" --max-time 10 >/dev/null || true

declare -a required_headers=(
  "strict-transport-security|HSTS|max-age|HSTS-001"
  "x-content-type-options|nosniff|nosniff|HEADER-001"
  "x-frame-options|DENY or SAMEORIGIN|DENY,SAMEORIGIN|HEADER-002"
  "content-security-policy|CSP|default-src|HEADER-003"
  "referrer-policy|Referrer-Policy|origin,no-referrer,strict-origin|HEADER-004"
)

for entry in "${required_headers[@]}"; do
  IFS='|' read -r name pretty expected_pat finding_id <<< "$entry"
  value=$(header_value "$name")
  if [ -z "$value" ]; then
    evidence=$(build_evidence "header=$name" "found=" "expected=$pretty" "path=$PROBE_PATH")
    emit_finding \
      "$finding_id" "low" "API8:2023 Security Misconfiguration" \
      "GET $PROBE_PATH" \
      "Required security header '$name' is missing. Browser-side defenses ($pretty) are not active." \
      "Set this header at the framework or reverse-proxy level." \
      "$evidence"
  else
    # Soft sanity: check that the value contains an expected substring
    matched=0
    IFS=',' read -ra patterns <<< "$expected_pat"
    for pat in "${patterns[@]}"; do
      if echo "$value" | grep -qiE "$pat"; then
        matched=1
        break
      fi
    done
    if [ "$matched" = "0" ]; then
      evidence=$(build_evidence "header=$name" "found=$value" "expected_contains=$expected_pat" "path=$PROBE_PATH")
      emit_finding \
        "${finding_id}-WEAK" "info" "API8:2023 Security Misconfiguration" \
        "GET $PROBE_PATH" \
        "Header '$name' is set ('$value') but value does not match expected pattern ($expected_pat) — review configuration." \
        "Confirm the header value matches OWASP / your security policy." \
        "$evidence"
    fi
  fi
done

log_ok "CORS / headers probes complete."
