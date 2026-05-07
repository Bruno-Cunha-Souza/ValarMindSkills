#!/usr/bin/env bash
# 02-dedup-detect.sh — Near-duplicate block detector via SHA256 chunks.
#
# Splits .md / .txt files in PROJECT_ROOT into 50-line chunks, hashes each
# chunk, reports duplicate hashes (exact byte-match) across files. A naive
# but useful first-pass for the dedup smell described in TECHNIQUES §10.
#
# Reads:  PROJECT_ROOT (env), ./out/findings.jsonl (appends)
# Writes: ./out/findings.jsonl
#
# Pure bash — uses awk + sha256sum (or shasum on macOS).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_env PROJECT_ROOT
ensure_project_root_readable

# Pick hash command: prefer sha256sum (Linux); fall back to shasum -a 256 (macOS)
if command -v sha256sum >/dev/null 2>&1; then
  HASH_CMD="sha256sum"
elif command -v shasum >/dev/null 2>&1; then
  HASH_CMD="shasum -a 256"
else
  log_error "Neither sha256sum nor shasum available — cannot run dedup detection"
  exit 1
fi

CHUNK_SIZE=50  # lines per chunk

log_info "Scanning $PROJECT_ROOT for duplicate content blocks (${CHUNK_SIZE}-line chunks) ..."

CHUNKS_FILE=$(mktemp)
trap 'rm -f "$CHUNKS_FILE"' EXIT

# For each .md / .txt file: emit "<hash> <path>:<chunk_start_line>"
while IFS= read -r -d '' file; do
  rel_path="${file#"$PROJECT_ROOT"/}"
  awk -v chunk="$CHUNK_SIZE" -v path="$rel_path" '
    {
      buf[NR % chunk] = $0
      if (NR % chunk == 0) {
        for (i = 1; i <= chunk; i++) printf "%s\n", buf[i]
        # delimiter between chunks (will not appear in actual hashed content)
        print "---CHUNK-END---" path ":" (NR - chunk + 1)
      }
    }
    END {
      if (NR % chunk != 0) {
        # tail chunk
        for (i = (NR - (NR % chunk) + 1); i <= NR; i++) printf "%s\n", buf[i % chunk]
        print "---CHUNK-END---" path ":" (NR - (NR % chunk) + 1)
      }
    }
  ' "$file" 2>/dev/null
done < <(find "$PROJECT_ROOT" \
            -type f \
            \( -name "*.md" -o -name "*.txt" \) \
            -not -path "*/.git/*" \
            -not -path "*/node_modules/*" \
            -not -path "*/.venv/*" \
            -not -path "*/__pycache__/*" \
            -not -path "*/out/*" \
            -print0 2>/dev/null) \
  | awk '
      BEGIN { chunk = "" }
      /^---CHUNK-END---/ {
        # Emit hash + location for the accumulated chunk
        location = substr($0, length("---CHUNK-END---") + 1)
        print location "\t" chunk
        chunk = ""
        next
      }
      { chunk = chunk $0 "\n" }
    ' > "$CHUNKS_FILE.raw" 2>/dev/null || true

# Hash each chunk; group by hash
HASHED_FILE=$(mktemp)
trap 'rm -f "$CHUNKS_FILE" "$CHUNKS_FILE.raw" "$HASHED_FILE"' EXIT

# Read raw chunks, hash content, output: <hash>\t<location>
awk -F'\t' '{
  loc = $1
  content = $2
  # Skip empty / near-empty chunks
  gsub(/[[:space:]]/, "", content)
  if (length(content) < 50) next
  # Re-emit content for hashing
  print loc "\t" $2
}' "$CHUNKS_FILE.raw" 2>/dev/null > "$CHUNKS_FILE" || true

# Hash each line's content portion, group by hash
duplicate_count=0

# Use python for robust hashing (avoids awkward bash escapes)
python3 - "$CHUNKS_FILE" "$HASH_CMD" "$FINDINGS_FILE" <<'PY' || true
import hashlib
import json
import os
import sys
from collections import defaultdict
from datetime import datetime, timezone


def now_iso():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def main():
    chunks_path = sys.argv[1]
    findings_path = sys.argv[3]

    by_hash = defaultdict(list)
    try:
        with open(chunks_path, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                if "\t" not in line:
                    continue
                loc, content = line.split("\t", 1)
                # Normalize whitespace for fuzzy match
                normalized = " ".join(content.split())
                if len(normalized) < 50:
                    continue
                h = hashlib.sha256(normalized.encode("utf-8")).hexdigest()[:16]
                by_hash[h].append(loc.strip())
    except FileNotFoundError:
        sys.stderr.write("[INFO]  No chunks to dedup (empty input)\n")
        return 0

    # Find groups with >= 2 occurrences
    duplicate_groups = [(h, locs) for h, locs in by_hash.items() if len(locs) >= 2]
    duplicate_groups.sort(key=lambda t: -len(t[1]))

    rank = 0
    total_dup_chunks = 0
    for h, locs in duplicate_groups[:20]:
        rank += 1
        copies = len(locs)
        total_dup_chunks += copies

        if copies >= 5:
            severity = "high"
        elif copies >= 3:
            severity = "medium"
        else:
            severity = "low"

        impact = f"Same 50-line block appears {copies} times across files. Estimated wasted tokens: ~{(copies - 1) * 50 * 4 // 4} (50 lines × 4 chars/token avg)."
        remediation = "Apply §10 dedup before LLM call. Keep canonical version; replace duplicates with references. Particularly relevant in RAG pipelines and codebases with repeated headers."

        record = {
            "id": f"DUP-{rank:03d}",
            "phase": "02-dedup-detect",
            "severity": severity,
            "category": "bloat",
            "target": locs[0],
            "evidence": {
                "hash_prefix": h,
                "copies": copies,
                "locations": locs[:10],  # cap for evidence sanity
                "chunk_size_lines": 50,
            },
            "impact": impact,
            "remediation": remediation,
            "timestamp": now_iso(),
        }

        os.makedirs(os.path.dirname(findings_path), exist_ok=True)
        with open(findings_path, "a", encoding="utf-8") as fout:
            fout.write(json.dumps(record, separators=(",", ":")) + "\n")

        sys.stderr.write(f"[{'WARN' if severity in ('low','medium') else 'ERR'}]   [{record['id']}] {severity.upper()} — {locs[0]}\n")

    # Summary finding
    summary = {
        "id": "DUP-SUM",
        "phase": "02-dedup-detect",
        "severity": "info",
        "category": "bloat",
        "target": os.environ.get("PROJECT_ROOT", "."),
        "evidence": {
            "duplicate_groups": len(duplicate_groups),
            "total_duplicate_chunks": total_dup_chunks,
        },
        "impact": f"Detected {len(duplicate_groups)} duplicate-chunk group(s) across the corpus.",
        "remediation": "Use as evidence to prioritize §10 dedup in the optimization plan.",
        "timestamp": now_iso(),
    }
    with open(findings_path, "a", encoding="utf-8") as fout:
        fout.write(json.dumps(summary, separators=(",", ":")) + "\n")

    sys.stderr.write(f"[OK]    Dedup detection complete. {len(duplicate_groups)} group(s) found.\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
PY

log_ok "Dedup detection complete. Findings written to $FINDINGS_FILE"
