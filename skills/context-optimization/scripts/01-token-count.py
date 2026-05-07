#!/usr/bin/env python3
"""01-token-count.py — Token counter for context-optimization audit.

Scans PROJECT_ROOT for .md / .json / .jsonl / .txt files. Counts tokens via
tiktoken if available; falls back to chars/4 heuristic with logged warning.
Emits findings.jsonl with id TOK-NNN per file exceeding token thresholds.

Reads:  PROJECT_ROOT (env), ./out/findings.jsonl (appends)
Writes: ./out/findings.jsonl

Optional dep:
    pip install --user tiktoken    # for accurate token counts (Anthropic / OpenAI tokenizers)
Without tiktoken, uses heuristic: tokens ≈ chars / 4 (within ±15% for English).
"""

# pyright: reportAny=false, reportExplicitAny=false, reportUnknownMemberType=false, reportUnknownVariableType=false

from __future__ import annotations

import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

# Thresholds in tokens
THRESHOLD_HIGH = 10_000
THRESHOLD_MEDIUM = 5_000
THRESHOLD_LOW = 2_000

OUT_DIR = Path(os.environ.get("OUT_DIR", "./out"))
FINDINGS_FILE = Path(os.environ.get("FINDINGS_FILE", str(OUT_DIR / "findings.jsonl")))
PROJECT_ROOT = os.environ.get("PROJECT_ROOT")

EXCLUDED_PARTS = {".git", "node_modules", ".venv", "__pycache__", "out"}
EXTENSIONS = {".md", ".json", ".jsonl", ".txt"}


def log_info(msg: str) -> None:
    sys.stderr.write(f"[INFO]  {msg}\n")


def log_warn(msg: str) -> None:
    sys.stderr.write(f"[WARN]  {msg}\n")


def log_error(msg: str) -> None:
    sys.stderr.write(f"[ERR]   {msg}\n")


def log_ok(msg: str) -> None:
    sys.stderr.write(f"[OK]    {msg}\n")


def now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def load_tiktoken() -> Any | None:
    try:
        import tiktoken  # type: ignore[import-untyped]
        log_ok("tiktoken loaded — using accurate token counts")
        return tiktoken.get_encoding("cl100k_base")  # Anthropic-compatible default
    except ImportError:
        log_warn("tiktoken not installed — using heuristic chars/4 (±15% accuracy)")
        log_warn("Install: pip install --user tiktoken")
        return None


def count_tokens(text: str, encoder: Any | None) -> int:
    if encoder is not None:
        return len(encoder.encode(text))
    return len(text) // 4  # heuristic fallback


def is_excluded(path: Path, root: Path) -> bool:
    try:
        rel_parts = path.relative_to(root).parts
    except ValueError:
        return True
    return any(part in EXCLUDED_PARTS for part in rel_parts)


def emit_finding(record: dict[str, Any]) -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    with FINDINGS_FILE.open("a", encoding="utf-8") as f:
        f.write(json.dumps(record, separators=(",", ":")) + "\n")
    sev = record.get("severity", "info").upper()
    target = record.get("target", "?")
    if sev in ("CRITICAL", "HIGH"):
        log_error(f"[{record.get('id')}] {sev} — {target}")
    elif sev in ("MEDIUM", "LOW"):
        log_warn(f"[{record.get('id')}] {sev} — {target}")
    else:
        log_info(f"[{record.get('id')}] {sev} — {target}")


def main() -> int:
    if not PROJECT_ROOT:
        log_error("PROJECT_ROOT environment variable not set.")
        log_warn("Usage: PROJECT_ROOT=/path/to/project python3 01-token-count.py")
        return 1

    root = Path(PROJECT_ROOT)
    if not root.is_dir():
        log_error(f"PROJECT_ROOT not a directory: {root}")
        return 1

    encoder = load_tiktoken()
    using_heuristic = encoder is None

    log_info(f"Counting tokens in {root} ...")

    candidates: list[tuple[Path, int]] = []
    total_tokens = 0
    total_files = 0

    for path in root.rglob("*"):
        if not path.is_file():
            continue
        if path.suffix not in EXTENSIONS:
            continue
        if is_excluded(path, root):
            continue
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except (OSError, UnicodeDecodeError):
            continue
        tokens = count_tokens(text, encoder)
        candidates.append((path, tokens))
        total_tokens += tokens
        total_files += 1

    log_info(f"Scanned {total_files} files; total ~{total_tokens:,} tokens.")

    # Rank by token count, emit top-20
    candidates.sort(key=lambda t: -t[1])
    for rank, (path, tokens) in enumerate(candidates[:20], start=1):
        rel = path.relative_to(root)
        if tokens >= THRESHOLD_HIGH:
            severity = "high"
            impact = (
                f"File consumes ~{tokens:,} tokens. On a 200k window this is "
                f"{tokens * 100 // 200_000}% of budget by itself."
            )
            remediation = (
                "Apply §3 observation masking if this is a tool output, or §6 "
                "verbatim deletion if citation-bound. For monolithic source files, "
                "consider §7 partitioning across sub-agents."
            )
        elif tokens >= THRESHOLD_MEDIUM:
            severity = "medium"
            impact = f"File consumes ~{tokens:,} tokens. Cumulative bloat adds up across files."
            remediation = "Review for §10 dedup opportunities and unused content."
        elif tokens >= THRESHOLD_LOW:
            severity = "low"
            impact = f"File consumes ~{tokens:,} tokens — within budget but tracked."
            remediation = "Track across runs; flag growth."
        else:
            continue

        emit_finding({
            "id": f"TOK-{rank:03d}",
            "phase": "01-token-count",
            "severity": severity,
            "category": "bloat",
            "target": str(rel),
            "evidence": {
                "path": str(rel),
                "tokens": tokens,
                "rank": rank,
                "tokenizer": "tiktoken-cl100k_base" if not using_heuristic else "heuristic-chars/4",
            },
            "impact": impact,
            "remediation": remediation,
            "timestamp": now_iso(),
        })

    # Summary finding (always emit, info-level)
    emit_finding({
        "id": "TOK-SUM",
        "phase": "01-token-count",
        "severity": "info",
        "category": "bloat",
        "target": str(root),
        "evidence": {
            "total_files": total_files,
            "total_tokens": total_tokens,
            "tokenizer": "tiktoken-cl100k_base" if not using_heuristic else "heuristic-chars/4",
            "accuracy": "exact" if not using_heuristic else "±15%",
        },
        "impact": (
            f"Scanned {total_files} files totalling ~{total_tokens:,} tokens "
            f"({'exact' if not using_heuristic else 'heuristic ±15%'})."
        ),
        "remediation": (
            "Use this as Phase 1 inventory baseline. Compare to use-case ceiling "
            "per Phase 5.3 (long-conv-agent ≤ 100k; rag stable prefix ≤ 8k; "
            "sub-agent ≤ 30k; large-doc ≤ 200k)."
        ),
        "timestamp": now_iso(),
    })

    log_ok(f"Token count complete. Findings written to {FINDINGS_FILE}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
