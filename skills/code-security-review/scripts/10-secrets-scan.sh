#!/usr/bin/env bash
# Phase 9 — Secrets scan (static, no live target).
# Prefers gitleaks, then trufflehog (verified-only), then a regex fallback over tracked files.
#
# Reads:
#   PROJECT_ROOT (default $PWD)   — repo root to scan
# Writes: out/findings.jsonl
#
# No TARGET and no authorization gate — reads files only.
# Matched values are ALWAYS redacted (first 4 + last 4 chars) before being written.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

PROJECT_ROOT="${PROJECT_ROOT:-$PWD}"
log_info "Secrets scan root: $PROJECT_ROOT"

# Redact a secret to first4…last4 (keeps it useless but greppable in context).
redact() {
  local s="$1" n
  n=${#s}
  if [ "$n" -le 8 ]; then printf '****'; else printf '%s…%s' "${s:0:4}" "${s: -4}"; fi
}

# ---------------------------------------------------------------------------
# Preferred: gitleaks (fast pattern scan over tree + history).
# ---------------------------------------------------------------------------
if command -v gitleaks >/dev/null 2>&1; then
  log_info "Running gitleaks..."
  report="$OUT_DIR/.gitleaks.json"
  if gitleaks detect --source "$PROJECT_ROOT" --no-banner \
       --report-format json --report-path "$report" >/dev/null 2>&1; then
    log_ok "gitleaks found no secrets."
  else
    n=0
    if [ -f "$report" ] && command -v python3 >/dev/null 2>&1; then
      n=$(python3 -c 'import json,sys;
try:
    d=json.load(open(sys.argv[1]));print(len(d) if isinstance(d,list) else 0)
except Exception:
    print(0)' "$report" 2>/dev/null || echo 0)
    fi
    emit_finding \
      "SECRETS-GL-001" "high" "A07:2025 Authentication Failures / CWE-798" \
      "$PROJECT_ROOT (gitleaks)" \
      "gitleaks detected $n potential committed secret(s). A leaked credential in git history stays exploitable until rotated, even if later removed." \
      "Rotate every exposed credential first, then purge it from history. Add a gitleaks pre-commit hook." \
      "$(build_evidence "tool=gitleaks" "count=$n" "report=$report")"
  fi
  log_ok "Secrets scan complete."
  exit 0
fi

# ---------------------------------------------------------------------------
# Second choice: trufflehog (verifies whether the credential is still live).
# ---------------------------------------------------------------------------
if command -v trufflehog >/dev/null 2>&1; then
  log_info "Running trufflehog (verified only)..."
  if out=$(trufflehog filesystem "$PROJECT_ROOT" --only-verified --json 2>/dev/null); then
    if [ -n "$out" ]; then
      n=$(printf '%s\n' "$out" | grep -c . || echo 0)
      emit_finding \
        "SECRETS-TH-001" "critical" "A07:2025 Authentication Failures / CWE-798" \
        "$PROJECT_ROOT (trufflehog)" \
        "trufflehog confirmed $n LIVE credential(s) — verified as still active against their provider. This is confirmed, exploitable exposure." \
        "Rotate immediately, then purge from history and audit for misuse." \
        "$(build_evidence "tool=trufflehog" "verified_count=$n")"
    else
      log_ok "trufflehog found no verified secrets."
    fi
  fi
  log_ok "Secrets scan complete."
  exit 0
fi

# ---------------------------------------------------------------------------
# Fallback: regex over tracked files only (never scans out/ or untracked junk).
# ---------------------------------------------------------------------------
log_warn "Neither gitleaks nor trufflehog installed — using regex fallback. (brew install gitleaks)"

if ! command -v git >/dev/null 2>&1 || ! git -C "$PROJECT_ROOT" rev-parse >/dev/null 2>&1; then
  log_warn "Not a git repo — regex fallback needs 'git ls-files'. Skipping."
  log_ok "Secrets scan complete."
  exit 0
fi

# Patterns: AWS key, GitHub token, Slack token, PEM private key, generic assignment.
declare -a PATTERNS=(
  'AKIA[0-9A-Z]{16}'
  'gh[pousr]_[A-Za-z0-9]{36}'
  'xox[baprs]-[A-Za-z0-9-]{10,}'
  '-----BEGIN [A-Z ]*PRIVATE KEY-----'
  '(api[_-]?key|secret|token|passwd|password)["'"'"' ]*[:=]["'"'"' ]*[A-Za-z0-9_\-]{20,}'
)

hits=0
sample=""
while IFS= read -r file; do
  [ -f "$PROJECT_ROOT/$file" ] || continue
  case "$file" in out/*|*.lock|*.min.js) continue ;; esac
  for pat in "${PATTERNS[@]}"; do
    while IFS= read -r m; do
      [ -n "$m" ] || continue
      hits=$((hits + 1))
      val="$(printf '%s' "$m" | grep -oiE "$pat" | head -n1)"
      [ -n "$sample" ] && sample="$sample; "
      sample="$sample$file:$(redact "$val")"
    done < <(grep -aoiE "$pat" "$PROJECT_ROOT/$file" 2>/dev/null | head -n 3)
  done
done < <(git -C "$PROJECT_ROOT" ls-files 2>/dev/null)

if [ "$hits" -gt 0 ]; then
  excerpt=$(printf '%s' "$sample" | head -c 600 | tr -d '\000-\031')
  emit_finding \
    "SECRETS-RX-001" "high" "A07:2025 Authentication Failures / CWE-798" \
    "$PROJECT_ROOT (regex fallback)" \
    "$hits high-entropy/secret-shaped string(s) found in tracked files. Heuristic — verify each (some may be examples/placeholders). Values are redacted in evidence." \
    "Confirm each match; rotate any real credential and move it to a secret store. Install gitleaks/trufflehog for higher-fidelity scanning." \
    "$(build_evidence "tool=regex" "hits=$hits" "sample=$excerpt")"
else
  log_ok "Regex fallback found no secret-shaped strings."
fi

log_ok "Secrets scan complete."
