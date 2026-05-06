#!/usr/bin/env bash
# Shared helpers for code-security-review probe scripts.
# Source this file at the top of each phase script: source "$(dirname "$0")/lib/common.sh"

set -euo pipefail

# --- Output directory ---
OUT_DIR="${OUT_DIR:-./out}"
mkdir -p "$OUT_DIR"
FINDINGS_FILE="${FINDINGS_FILE:-$OUT_DIR/findings.jsonl}"

# --- Colors (auto-disabled if not a TTY) ---
if [ -t 1 ]; then
  C_RED=$'\033[31m'; C_YELLOW=$'\033[33m'; C_GREEN=$'\033[32m'
  C_BLUE=$'\033[34m'; C_GRAY=$'\033[90m'; C_RESET=$'\033[0m'
else
  C_RED=""; C_YELLOW=""; C_GREEN=""; C_BLUE=""; C_GRAY=""; C_RESET=""
fi

# --- Logging ---
log_info()  { printf '%b[INFO]%b  %s\n' "$C_BLUE"   "$C_RESET" "$*" >&2; }
log_warn()  { printf '%b[WARN]%b  %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
log_error() { printf '%b[ERR]%b   %s\n' "$C_RED"    "$C_RESET" "$*" >&2; }
log_ok()    { printf '%b[OK]%b    %s\n' "$C_GREEN"  "$C_RESET" "$*" >&2; }
log_dim()   { printf '%b%s%b\n'         "$C_GRAY"   "$*"       "$C_RESET" >&2; }

# --- Required-env enforcement ---
require_env() {
  local var
  for var in "$@"; do
    if [ -z "${!var:-}" ]; then
      log_error "Required environment variable not set: $var"
      log_dim   "See ./README.md for the full env var list."
      exit 1
    fi
  done
}

# --- ISO-8601 timestamp (UTC) ---
now_iso() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

# --- HTTP wrapper ---
# http_request METHOD PATH [extra_curl_args...]
# Echoes a single line: <status_code> <body_size_bytes> <elapsed_seconds>
# Body and headers are saved to $RESP_BODY / $RESP_HEADERS for the caller.
RESP_BODY="$OUT_DIR/.last_body"
RESP_HEADERS="$OUT_DIR/.last_headers"

http_request() {
  local method="$1"; shift
  local path="$1"; shift
  local url

  if [[ "$path" =~ ^https?:// ]]; then
    url="$path"
  else
    url="${TARGET:?TARGET env var is not set}${path}"
  fi

  # -s silent, -S show errors, -k allow self-signed (staging)
  # -o body file, -D headers file, -w status+size+time
  curl -sSk \
    -X "$method" \
    -o "$RESP_BODY" \
    -D "$RESP_HEADERS" \
    -w '%{http_code} %{size_download} %{time_total}\n' \
    "$@" \
    "$url"
}

# --- JSON-safe escape (reads stdin → writes JSON-quoted string to stdout) ---
json_string() {
  python3 -c 'import json,sys; sys.stdout.write(json.dumps(sys.stdin.read()))'
}

# --- Append a finding to findings.jsonl ---
# emit_finding ID SEVERITY OWASP ENDPOINT IMPACT REMEDIATION [evidence_json]
#
# Variables are passed via environment (not heredoc substitution) so quotes / newlines
# in any field stay safe. evidence_json (optional) must be a valid JSON object string;
# defaults to {}.
emit_finding() {
  local phase
  phase="$(basename "$0")"
  phase="${phase%.sh}"
  phase="${phase%.py}"

  F_ID="$1" \
  F_SEVERITY="$2" \
  F_OWASP="$3" \
  F_ENDPOINT="$4" \
  F_IMPACT="$5" \
  F_REMEDIATION="$6" \
  F_EVIDENCE="${7:-{\}}" \
  F_PHASE="$phase" \
  F_TIMESTAMP="$(now_iso)" \
  python3 - >> "$FINDINGS_FILE" <<'PY'
import json, os, sys
try:
    evidence = json.loads(os.environ["F_EVIDENCE"])
    if not isinstance(evidence, dict):
        evidence = {"raw": evidence}
except json.JSONDecodeError:
    evidence = {"raw": os.environ["F_EVIDENCE"]}

record = {
    "id":          os.environ["F_ID"],
    "phase":       os.environ["F_PHASE"],
    "severity":    os.environ["F_SEVERITY"],
    "owasp":       os.environ["F_OWASP"],
    "endpoint":    os.environ["F_ENDPOINT"],
    "evidence":    evidence,
    "impact":      os.environ["F_IMPACT"],
    "remediation": os.environ["F_REMEDIATION"],
    "timestamp":   os.environ["F_TIMESTAMP"],
}
sys.stdout.write(json.dumps(record, separators=(",", ":")) + "\n")
PY

  local sev_upper
  sev_upper="$(printf '%s' "$2" | tr '[:lower:]' '[:upper:]')"
  case "$2" in
    critical|high) log_error "[$1] $sev_upper — $4" ;;
    medium|low)    log_warn  "[$1] $sev_upper — $4" ;;
    info)          log_info  "[$1] $sev_upper — $4" ;;
    *)             log_warn  "[$1] $sev_upper — $4" ;;
  esac
}

# --- Build a JSON evidence object from key=value pairs ---
# Usage: evidence=$(build_evidence "status=200" "header=Bearer foo")
build_evidence() {
  python3 - "$@" <<'PY'
import json, sys
out = {}
for arg in sys.argv[1:]:
    if "=" not in arg:
        continue
    k, v = arg.split("=", 1)
    out[k] = v
sys.stdout.write(json.dumps(out, separators=(",", ":")))
PY
}

# --- Sanity guard: target reachable? ---
ensure_target_reachable() {
  log_info "Probing $TARGET ..."
  local code
  if ! code=$(curl -sSk -o /dev/null -w '%{http_code}' --max-time 10 "$TARGET" 2>/dev/null); then
    log_error "Target $TARGET is unreachable."
    exit 1
  fi
  if [ "$code" = "000" ]; then
    log_error "Target $TARGET returned no response (DNS / TLS / network failure)."
    exit 1
  fi
  log_ok "Target reachable (initial probe returned HTTP $code)."
}

# Init findings file if absent (so jq -s works even with zero findings)
[ -f "$FINDINGS_FILE" ] || : > "$FINDINGS_FILE"
