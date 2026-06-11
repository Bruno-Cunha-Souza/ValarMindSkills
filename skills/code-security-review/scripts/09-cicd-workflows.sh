#!/usr/bin/env bash
# Phase 8 — CI/CD workflow audit (static, no live target).
# Audits GitHub Actions workflows for supply-chain misconfigurations.
# Prefers `zizmor` when installed; always runs grep-based fallback checks.
#
# Reads:
#   PROJECT_ROOT (default $PWD)   — repo root containing .github/workflows/
# Writes: out/findings.jsonl
#
# No TARGET and no authorization gate — this reads files only, sends no traffic.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

PROJECT_ROOT="${PROJECT_ROOT:-$PWD}"
WF_DIR="$PROJECT_ROOT/.github/workflows"

if [ ! -d "$WF_DIR" ]; then
  log_warn "No .github/workflows/ under $PROJECT_ROOT — skipping CI/CD audit."
  exit 0
fi

# Collect workflow files (.yml / .yaml).
workflows=()
while IFS= read -r f; do workflows+=("$f"); done < <(find "$WF_DIR" -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) 2>/dev/null)

if [ "${#workflows[@]}" -eq 0 ]; then
  log_warn "No workflow files in $WF_DIR — skipping."
  exit 0
fi

log_info "Auditing ${#workflows[@]} workflow file(s) in $WF_DIR"

# ---------------------------------------------------------------------------
# Preferred: zizmor (Trail of Bits) — purpose-built GitHub Actions analyzer.
# ---------------------------------------------------------------------------
if command -v zizmor >/dev/null 2>&1; then
  log_info "Running zizmor..."
  if out=$(cd "$PROJECT_ROOT" && zizmor --format plain .github/workflows 2>&1); then
    log_ok "zizmor reported no findings."
  else
    excerpt=$(printf '%s' "$out" | head -c 1200 | tr -d '\000-\031')
    emit_finding \
      "CICD-ZIZ-001" "high" "A03:2025 Software Supply Chain Failures" \
      ".github/workflows (zizmor)" \
      "zizmor reported one or more workflow security findings. Review the excerpt for the specific audits (e.g. template-injection, dangerous-triggers, unpinned actions)." \
      "Address each zizmor finding; rerun until clean. See docs.zizmor.sh for per-audit remediation." \
      "$(build_evidence "tool=zizmor" "output_excerpt=$excerpt")"
  fi
else
  log_warn "zizmor not installed — running grep fallback only. (https://github.com/zizmorcore/zizmor)"
fi

# ---------------------------------------------------------------------------
# Fallback grep heuristics (always run; complement zizmor, dedupe by ID).
# ---------------------------------------------------------------------------
for wf in "${workflows[@]}"; do
  rel="${wf#"$PROJECT_ROOT"/}"

  # CICD-001 — third-party `uses:` not pinned to a 40-hex commit SHA.
  # Skip local actions (./...) and reusable-workflow refs we can't resolve cleanly.
  unpinned=$(grep -nE '^\s*-?\s*uses:\s*[^@#[:space:]]+@' "$wf" 2>/dev/null \
    | grep -vE 'uses:\s*\./' \
    | grep -vE '@[0-9a-f]{40}([[:space:]]|$|#)' || true)
  if [ -n "$unpinned" ]; then
    count=$(printf '%s\n' "$unpinned" | grep -c . || true)
    excerpt=$(printf '%s' "$unpinned" | head -c 500 | tr -d '\000-\031')
    emit_finding \
      "CICD-001" "high" "A03:2025 Software Supply Chain Failures / CWE-829" \
      "$rel" \
      "$count action reference(s) pinned to a mutable tag/branch instead of a full 40-hex commit SHA. A rewritten tag (cf. tj-actions/changed-files, Mar 2025) silently executes attacker code with the workflow's permissions." \
      "Pin every third-party action by full commit SHA: 'uses: owner/action@<40-hex>  # vX.Y.Z'." \
      "$(build_evidence "file=$rel" "unpinned=$excerpt")"
  fi

  # CICD-002 — pull_request_target + checkout of PR head = "pwn request".
  if grep -qE '^\s*-?\s*pull_request_target' "$wf" 2>/dev/null \
     && grep -qE 'ref:\s*\$\{\{\s*github\.event\.pull_request\.head' "$wf" 2>/dev/null; then
    emit_finding \
      "CICD-002" "critical" "A03:2025 Software Supply Chain Failures / CWE-284" \
      "$rel" \
      "Workflow uses 'pull_request_target' (runs with write perms + secrets) AND checks out the PR head ref. Untrusted PR code then executes with full repository credentials (pwn request)." \
      "Use 'pull_request' for untrusted contributions, or never check out / execute PR contents under 'pull_request_target'." \
      "$(build_evidence "file=$rel" "trigger=pull_request_target" "checkout=pr_head")"
  fi

  # CICD-003 — secrets interpolated directly into a run: shell string.
  secrun=$(grep -nE '\$\{\{\s*secrets\.' "$wf" 2>/dev/null | grep -viE 'env:|with:' || true)
  if [ -n "$secrun" ]; then
    excerpt=$(printf '%s' "$secrun" | head -c 400 | tr -d '\000-\031')
    emit_finding \
      "CICD-003" "medium" "A03:2025 Software Supply Chain Failures / CWE-532" \
      "$rel" \
      "Secret expression interpolated into workflow steps outside an 'env:'/'with:' mapping. Textual substitution into a 'run:' shell enables injection and can leak the secret to logs." \
      "Pass secrets via 'env:' and reference them as shell variables (\$MY_SECRET), never inline \${{ secrets.* }} in run: text." \
      "$(build_evidence "file=$rel" "matches=$excerpt")"
  fi

  # CICD-004 — no top-level permissions: key (inherits broad defaults).
  if ! grep -qE '^permissions:' "$wf" 2>/dev/null; then
    emit_finding \
      "CICD-004" "medium" "A02:2025 Security Misconfiguration" \
      "$rel" \
      "Workflow declares no top-level 'permissions:' block, so the GITHUB_TOKEN inherits the repository default (often broad/write)." \
      "Add 'permissions: contents: read' at the top level and escalate per-job only where required." \
      "$(build_evidence "file=$rel" "permissions=absent")"
  fi

  # CICD-005 — self-hosted runner (cannot verify isolation here; flag for review).
  if grep -qE 'runs-on:.*self-hosted' "$wf" 2>/dev/null; then
    emit_finding \
      "CICD-005" "info" "A03:2025 Software Supply Chain Failures" \
      "$rel" \
      "Workflow targets a self-hosted runner. On a public repo, untrusted PRs could run on it; persistence between jobs can leak state. Cannot verify isolation statically — review." \
      "Restrict self-hosted runners to trusted workflows; use ephemeral runners; never expose them to public-PR triggers." \
      "$(build_evidence "file=$rel" "runner=self-hosted")"
  fi
done

log_ok "CI/CD workflow audit complete."
