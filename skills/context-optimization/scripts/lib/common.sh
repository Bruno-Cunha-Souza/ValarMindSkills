#!/usr/bin/env bash
# Shared helpers for context-optimization audit scripts.
# Source this file at the top of each phase script:
#   source "$(dirname "$0")/lib/common.sh"
#
# Port of code-security-review/scripts/lib/common.sh, with HTTP/target helpers
# removed (this skill audits local context, not remote endpoints).

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

# --- Append a finding to findings.jsonl ---
# emit_finding ID SEVERITY CATEGORY TARGET IMPACT REMEDIATION [evidence_json]
#
# Variables are passed via environment (not heredoc substitution) so quotes / newlines
# in any field stay safe. evidence_json (optional) must be a valid JSON object string;
# defaults to {}.
#
# CATEGORY: one of cost | cache | quality | bloat | architecture
# TARGET:   the file path or category being audited (analogous to "endpoint" in security review)
emit_finding() {
  local phase
  phase="$(basename "$0")"
  phase="${phase%.sh}"
  phase="${phase%.py}"

  F_ID="$1" \
  F_SEVERITY="$2" \
  F_CATEGORY="$3" \
  F_TARGET="$4" \
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
    "category":    os.environ["F_CATEGORY"],
    "target":      os.environ["F_TARGET"],
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
# Usage: evidence=$(build_evidence "size_bytes=12345" "lines=200")
build_evidence() {
  python3 - "$@" <<'PY'
import json, sys
out = {}
for arg in sys.argv[1:]:
    if "=" not in arg:
        continue
    k, v = arg.split("=", 1)
    # Try numeric coercion for cleaner JSON (helps downstream report rendering)
    try:
        out[k] = int(v)
    except ValueError:
        try:
            out[k] = float(v)
        except ValueError:
            out[k] = v
sys.stdout.write(json.dumps(out, separators=(",", ":")))
PY
}

# --- Sanity guard: project root readable? ---
ensure_project_root_readable() {
  if [ ! -d "$PROJECT_ROOT" ]; then
    log_error "PROJECT_ROOT not a directory: $PROJECT_ROOT"
    exit 1
  fi
  if [ ! -r "$PROJECT_ROOT" ]; then
    log_error "PROJECT_ROOT not readable: $PROJECT_ROOT"
    exit 1
  fi
  log_ok "Project root readable: $PROJECT_ROOT"
}

# Init findings file if absent (so jq -s works even with zero findings)
[ -f "$FINDINGS_FILE" ] || : > "$FINDINGS_FILE"
