#!/usr/bin/env bash
# Phase 6 — Supply chain audit.
# Auto-detects stack from PROJECT_ROOT and runs the appropriate scanner.
#
# Reads:
#   PROJECT_ROOT (default $PWD)   — directory containing requirements.txt / go.mod / package.json / Cargo.toml
# Writes: out/findings.jsonl
#
# Tools probed (each is optional — finding emitted only when tool is present AND vulns are reported):
#   pip-audit       — Python
#   govulncheck     — Go
#   bun audit       — Bun / Node
#   npm audit       — Node fallback
#   cargo audit     — Rust
#   osv-scanner     — universal cross-stack

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

PROJECT_ROOT="${PROJECT_ROOT:-$PWD}"
log_info "Project root: $PROJECT_ROOT"

emit_supply_chain() {
  local id="$1" tool="$2" stack="$3" raw_excerpt="$4"
  local excerpt
  excerpt="$(printf '%s' "$raw_excerpt" | head -c 600 | tr -d '\000-\031')"
  local evidence
  evidence="$(build_evidence "tool=$tool" "stack=$stack" "output_excerpt=$excerpt")"
  emit_finding \
    "$id" "high" "A06:2021 Vulnerable Components" \
    "$stack project at $PROJECT_ROOT" \
    "$tool reported vulnerable dependencies in the project. Severity should be assessed per-CVE; treating as High by default." \
    "Upgrade affected packages. In CI, fail the build on vuln-bearing dependencies. Pin versions and use lockfile-with-hashes (pip-audit --require-hashes, bun --frozen-lockfile, go.sum)." \
    "$evidence"
}

ran_any=0

# ---------------------------------------------------------------------------
# Python
# ---------------------------------------------------------------------------
if [ -f "$PROJECT_ROOT/requirements.txt" ] || [ -f "$PROJECT_ROOT/pyproject.toml" ] || [ -f "$PROJECT_ROOT/Pipfile" ]; then
  if command -v pip-audit >/dev/null 2>&1; then
    log_info "Running pip-audit..."
    ran_any=1
    if ! out=$(cd "$PROJECT_ROOT" && pip-audit 2>&1); then
      if echo "$out" | grep -qiE 'found [0-9]+ known vulnerabilit|vulnerability'; then
        emit_supply_chain "SUPPLY-PY-001" "pip-audit" "Python" "$out"
      else
        log_warn "pip-audit exited with errors but no vuln pattern found:"
        log_dim "$(printf '%s' "$out" | head -c 400)"
      fi
    fi
  else
    log_warn "Python project detected but pip-audit not installed — skipping. (pip install pip-audit)"
  fi
fi

# ---------------------------------------------------------------------------
# Go
# ---------------------------------------------------------------------------
if [ -f "$PROJECT_ROOT/go.mod" ]; then
  if command -v govulncheck >/dev/null 2>&1; then
    log_info "Running govulncheck..."
    ran_any=1
    if ! out=$(cd "$PROJECT_ROOT" && govulncheck ./... 2>&1); then
      if echo "$out" | grep -qiE 'vulnerability|GO-[0-9]{4}-[0-9]+'; then
        emit_supply_chain "SUPPLY-GO-001" "govulncheck" "Go" "$out"
      fi
    fi
  else
    log_warn "Go project detected but govulncheck not installed — skipping. (go install golang.org/x/vuln/cmd/govulncheck@latest)"
  fi
fi

# ---------------------------------------------------------------------------
# Bun / Node
# ---------------------------------------------------------------------------
if [ -f "$PROJECT_ROOT/package.json" ]; then
  if command -v bun >/dev/null 2>&1 && { [ -f "$PROJECT_ROOT/bun.lockb" ] || [ -f "$PROJECT_ROOT/bun.lock" ]; }; then
    log_info "Running bun audit..."
    ran_any=1
    if ! out=$(cd "$PROJECT_ROOT" && bun audit 2>&1); then
      if echo "$out" | grep -qiE 'vulnerability|critical|high|moderate'; then
        emit_supply_chain "SUPPLY-BUN-001" "bun audit" "Bun" "$out"
      fi
    fi
  elif command -v npm >/dev/null 2>&1; then
    log_info "Running npm audit..."
    ran_any=1
    if ! out=$(cd "$PROJECT_ROOT" && npm audit --audit-level=high 2>&1); then
      if echo "$out" | grep -qiE 'vulnerability|critical|high'; then
        emit_supply_chain "SUPPLY-NPM-001" "npm audit" "Node" "$out"
      fi
    fi
  else
    log_warn "Node project detected but neither bun nor npm available."
  fi
fi

# ---------------------------------------------------------------------------
# Rust
# ---------------------------------------------------------------------------
if [ -f "$PROJECT_ROOT/Cargo.toml" ]; then
  if command -v cargo-audit >/dev/null 2>&1 || cargo audit --version >/dev/null 2>&1; then
    log_info "Running cargo audit..."
    ran_any=1
    if ! out=$(cd "$PROJECT_ROOT" && cargo audit 2>&1); then
      if echo "$out" | grep -qiE 'vulnerability|advisory|RUSTSEC'; then
        emit_supply_chain "SUPPLY-RS-001" "cargo audit" "Rust" "$out"
      fi
    fi
  else
    log_warn "Rust project detected but cargo-audit not installed — skipping. (cargo install cargo-audit)"
  fi
fi

# ---------------------------------------------------------------------------
# Universal: osv-scanner
# ---------------------------------------------------------------------------
if command -v osv-scanner >/dev/null 2>&1; then
  log_info "Running osv-scanner (cross-stack)..."
  ran_any=1
  if ! out=$(cd "$PROJECT_ROOT" && osv-scanner --recursive . 2>&1); then
    if echo "$out" | grep -qiE 'CVE-|GHSA-|RUSTSEC|PYSEC|GO-'; then
      emit_supply_chain "SUPPLY-OSV-001" "osv-scanner" "multi" "$out"
    fi
  fi
fi

if [ "$ran_any" = "0" ]; then
  log_warn "No supply-chain scanner ran. Install at least one of: pip-audit, govulncheck, bun, npm, cargo-audit, osv-scanner."
fi

log_ok "Supply chain audit complete."
