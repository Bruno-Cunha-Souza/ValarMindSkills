#!/usr/bin/env python3
"""Aggregate findings.jsonl into a human-readable Markdown report.

Usage:
    python3 lib/report.py out/findings.jsonl > out/report.md
    python3 lib/report.py out/findings.jsonl --json > out/summary.json
"""

# Findings are JSON records with intentionally heterogeneous evidence shapes; Any is deliberate.
# pyright: reportAny=false, reportExplicitAny=false, reportUnknownMemberType=false, reportUnknownArgumentType=false, reportUnknownVariableType=false

from __future__ import annotations

import json
import sys
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any

SEVERITY_ORDER: tuple[str, ...] = ("critical", "high", "medium", "low", "info")
SEVERITY_BADGE: dict[str, str] = {
    "critical": "[CRITICAL]",
    "high":     "[HIGH]",
    "medium":   "[MEDIUM]",
    "low":      "[LOW]",
    "info":     "[INFO]",
}

Finding = dict[str, Any]


def load_findings(path: Path) -> list[Finding]:
    findings: list[Finding] = []
    if not path.exists() or path.stat().st_size == 0:
        return findings
    for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = line.strip()
        if not line:
            continue
        try:
            findings.append(json.loads(line))
        except json.JSONDecodeError as e:
            print(f"# warning: skipping malformed line {lineno}: {e}", file=sys.stderr)
    return findings


def render_markdown(findings: list[Finding]) -> str:
    counts: Counter[str] = Counter(str(f.get("severity", "info")) for f in findings)
    by_phase: dict[str, list[Finding]] = defaultdict(list)
    for f in findings:
        by_phase[str(f.get("phase", "unknown"))].append(f)

    lines: list[str] = []
    lines.append("# Code Security Review — Active Probe Report")
    lines.append("")
    lines.append(f"_Generated from {len(findings)} finding(s)._")
    lines.append("")

    # --- Summary table ---
    lines.append("## Summary")
    lines.append("")
    lines.append("| Severity | Count |")
    lines.append("| --- | --- |")
    for sev in SEVERITY_ORDER:
        lines.append(f"| {SEVERITY_BADGE[sev]} | {counts.get(sev, 0)} |")
    lines.append(f"| **Total** | **{len(findings)}** |")
    lines.append("")

    if not findings:
        lines.append("> No findings recorded. Either the API passed all probes or no scripts were run.")
        lines.append("")
        return "\n".join(lines)

    # --- Verdict ---
    if counts.get("critical", 0) > 0:
        verdict = "FAIL — critical findings present, do not deploy"
    elif counts.get("high", 0) > 0:
        verdict = "FAIL — high-severity findings require remediation before deploy"
    elif counts.get("medium", 0) > 0:
        verdict = "REVIEW — medium-severity findings require triage"
    elif counts.get("low", 0) > 0:
        verdict = "PASS WITH NOTES — only low-severity findings"
    else:
        verdict = "PASS — only informational findings"
    lines.append(f"**Verdict:** {verdict}")
    lines.append("")

    # --- Findings grouped by severity ---
    for sev in SEVERITY_ORDER:
        sev_findings = [f for f in findings if f.get("severity") == sev]
        if not sev_findings:
            continue
        lines.append(f"## {SEVERITY_BADGE[sev]} ({len(sev_findings)})")
        lines.append("")
        for f in sev_findings:
            lines.append(f"### `{f.get('id', '?')}` — {f.get('endpoint', '?')}")
            lines.append("")
            lines.append(f"- **Phase:** `{f.get('phase', '?')}`")
            lines.append(f"- **OWASP:** {f.get('owasp', '—')}")
            lines.append(f"- **Timestamp:** {f.get('timestamp', '—')}")
            lines.append(f"- **Impact:** {f.get('impact', '—')}")
            lines.append(f"- **Remediation:** {f.get('remediation', '—')}")
            evidence = f.get("evidence") or {}
            if evidence:
                lines.append("")
                lines.append("```json")
                lines.append(json.dumps(evidence, indent=2, sort_keys=True))
                lines.append("```")
            lines.append("")

    # --- Findings grouped by phase (compact) ---
    lines.append("## By Phase")
    lines.append("")
    lines.append("| Phase | Findings | Highest severity |")
    lines.append("| --- | --- | --- |")
    for phase, items in sorted(by_phase.items()):
        sevs = {item.get("severity") for item in items}
        for sev in SEVERITY_ORDER:
            if sev in sevs:
                highest = sev.upper()
                break
        else:
            highest = "—"
        lines.append(f"| `{phase}` | {len(items)} | {highest} |")
    lines.append("")

    return "\n".join(lines)


def render_json_summary(findings: list[Finding]) -> str:
    counts: Counter[str] = Counter(str(f.get("severity", "info")) for f in findings)
    summary: dict[str, Any] = {
        "total":  len(findings),
        "counts": {sev: counts.get(sev, 0) for sev in SEVERITY_ORDER},
        "verdict_fail": counts.get("critical", 0) > 0 or counts.get("high", 0) > 0,
    }
    return json.dumps(summary, indent=2)


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 1
    path = Path(argv[1])
    findings = load_findings(path)
    if "--json" in argv[2:]:
        print(render_json_summary(findings))
    else:
        print(render_markdown(findings))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
