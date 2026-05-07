//! `ctxopt report` — aggregate findings into Markdown report + summary {JSON, TOON}.
//! Equivalent to legacy lib/report.py.

use crate::cli::ReportFormat;
use crate::finding::{Category, Finding, Severity};
use crate::toon;
use anyhow::{anyhow, Context, Result};
use std::collections::HashMap;
use std::fs::File;
use std::io::{BufRead, BufReader, BufWriter, Write};
use std::path::Path;

const SEVERITY_ORDER: [Severity; 5] = [
    Severity::Critical,
    Severity::High,
    Severity::Medium,
    Severity::Low,
    Severity::Info,
];

const CATEGORY_LABELS: &[(Category, &str)] = &[
    (Category::Cost, "Cost waste"),
    (Category::Cache, "Cache miss"),
    (Category::Quality, "Quality degradation"),
    (Category::Bloat, "Token bloat"),
    (Category::Architecture, "Architecture risk"),
];

fn category_label(c: Category) -> &'static str {
    CATEGORY_LABELS
        .iter()
        .find(|(cat, _)| *cat == c)
        .map(|(_, l)| *l)
        .unwrap_or("Unknown")
}

fn severity_badge(s: Severity) -> &'static str {
    match s {
        Severity::Critical => "[CRITICAL]",
        Severity::High => "[HIGH]",
        Severity::Medium => "[MEDIUM]",
        Severity::Low => "[LOW]",
        Severity::Info => "[INFO]",
    }
}

/// Detect input format by extension and parse into a Vec<Finding>.
pub fn load_findings(path: &Path) -> Result<Vec<Finding>> {
    let ext = path
        .extension()
        .and_then(|e| e.to_str())
        .unwrap_or("")
        .to_lowercase();

    match ext.as_str() {
        "jsonl" => load_jsonl(path),
        "json" => load_json(path),
        "toon" => Err(anyhow!(
            "TOON parser not implemented for input. Use --format=jsonl or --format=json source."
        )),
        _ => {
            // Best-effort: try jsonl first, fall back to json.
            load_jsonl(path).or_else(|_| load_json(path))
        }
    }
}

fn load_jsonl(path: &Path) -> Result<Vec<Finding>> {
    let f = File::open(path).with_context(|| format!("opening {}", path.display()))?;
    let reader = BufReader::new(f);
    let mut out = Vec::new();
    for (lineno, line) in reader.lines().enumerate() {
        let line = match line {
            Ok(l) => l,
            Err(_) => continue,
        };
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        match serde_json::from_str::<Finding>(line) {
            Ok(f) => out.push(f),
            Err(e) => eprintln!(
                "# warning: skipping malformed line {} in {}: {}",
                lineno + 1,
                path.display(),
                e
            ),
        }
    }
    Ok(out)
}

fn load_json(path: &Path) -> Result<Vec<Finding>> {
    let text = std::fs::read_to_string(path)
        .with_context(|| format!("reading {}", path.display()))?;
    let v: Vec<Finding> = serde_json::from_str(&text)
        .with_context(|| format!("parsing JSON array from {}", path.display()))?;
    Ok(v)
}

/// Render the standard Markdown report.
pub fn render_markdown(findings: &[Finding]) -> String {
    let mut counts: HashMap<Severity, usize> = HashMap::new();
    let mut by_phase: HashMap<String, Vec<&Finding>> = HashMap::new();
    let mut by_category: HashMap<Category, usize> = HashMap::new();

    for f in findings {
        *counts.entry(f.severity).or_insert(0) += 1;
        by_phase.entry(f.phase.clone()).or_default().push(f);
        *by_category.entry(f.category).or_insert(0) += 1;
    }

    let total = findings.len();
    let mut lines: Vec<String> = Vec::new();
    lines.push("# Context Optimization — Audit Report".into());
    lines.push(String::new());
    lines.push(format!("_Generated from {total} finding(s)._"));
    lines.push(String::new());

    // Summary by severity
    lines.push("## Summary by severity".into());
    lines.push(String::new());
    lines.push("| Severity | Count |".into());
    lines.push("| --- | --- |".into());
    for sev in SEVERITY_ORDER {
        lines.push(format!(
            "| {} | {} |",
            severity_badge(sev),
            counts.get(&sev).copied().unwrap_or(0)
        ));
    }
    lines.push(format!("| **Total** | **{total}** |"));
    lines.push(String::new());

    if findings.is_empty() {
        lines.push(
            "> No findings recorded. Either the context passes the audit or no scripts were run."
                .into(),
        );
        lines.push(String::new());
        return lines.join("\n");
    }

    // Verdict
    let crit = counts.get(&Severity::Critical).copied().unwrap_or(0);
    let high = counts.get(&Severity::High).copied().unwrap_or(0);
    let med = counts.get(&Severity::Medium).copied().unwrap_or(0);
    let low = counts.get(&Severity::Low).copied().unwrap_or(0);
    let verdict = if crit > 0 {
        "REWORK — critical findings present, optimization plan needs immediate adoption"
    } else if high > 0 {
        "REVIEW — high-severity findings require targeted remediation"
    } else if med > 0 {
        "TUNE — medium-severity findings warrant attention"
    } else if low > 0 {
        "PASS WITH NOTES — only low-severity findings"
    } else {
        "PASS — only informational findings"
    };
    lines.push(format!("**Verdict:** {verdict}"));
    lines.push(String::new());

    // Summary by category
    lines.push("## Summary by category".into());
    lines.push(String::new());
    lines.push("| Category | Findings |".into());
    lines.push("| --- | --- |".into());
    let mut cat_keys: Vec<Category> = by_category.keys().copied().collect();
    cat_keys.sort_by_key(|c| category_label(*c));
    for cat in cat_keys {
        lines.push(format!(
            "| {} | {} |",
            category_label(cat),
            by_category[&cat]
        ));
    }
    lines.push(String::new());

    // Findings grouped by severity
    for sev in SEVERITY_ORDER {
        let sev_findings: Vec<&Finding> = findings.iter().filter(|f| f.severity == sev).collect();
        if sev_findings.is_empty() {
            continue;
        }
        lines.push(format!("## {} ({})", severity_badge(sev), sev_findings.len()));
        lines.push(String::new());
        for f in sev_findings {
            lines.push(format!("### `{}` — {}", f.id, f.target));
            lines.push(String::new());
            lines.push(format!("- **Phase:** `{}`", f.phase));
            lines.push(format!("- **Category:** {}", category_label(f.category)));
            lines.push(format!("- **Timestamp:** {}", f.timestamp));
            lines.push(format!("- **Impact:** {}", f.impact));
            lines.push(format!("- **Remediation:** {}", f.remediation));
            if !f.evidence.is_null() && f.evidence != serde_json::json!({}) {
                lines.push(String::new());
                lines.push("```json".into());
                lines.push(serde_json::to_string_pretty(&f.evidence).unwrap_or_default());
                lines.push("```".into());
            }
            lines.push(String::new());
        }
    }

    // By phase
    lines.push("## By phase".into());
    lines.push(String::new());
    lines.push("| Phase | Findings | Highest severity |".into());
    lines.push("| --- | --- | --- |".into());
    let mut phase_keys: Vec<String> = by_phase.keys().cloned().collect();
    phase_keys.sort();
    for phase in &phase_keys {
        let items = &by_phase[phase];
        let highest = SEVERITY_ORDER
            .iter()
            .find(|sev| items.iter().any(|f| f.severity == **sev))
            .map(|s| s.as_str().to_uppercase())
            .unwrap_or_else(|| "—".to_string());
        lines.push(format!("| `{phase}` | {} | {highest} |", items.len()));
    }
    lines.push(String::new());

    lines.join("\n")
}

/// Render the JSON summary used by CI / aggregators.
pub fn render_json_summary(findings: &[Finding]) -> String {
    let mut counts: HashMap<Severity, usize> = HashMap::new();
    let mut by_category: HashMap<Category, usize> = HashMap::new();
    for f in findings {
        *counts.entry(f.severity).or_insert(0) += 1;
        *by_category.entry(f.category).or_insert(0) += 1;
    }
    let summary = serde_json::json!({
        "total": findings.len(),
        "counts": {
            "critical": counts.get(&Severity::Critical).copied().unwrap_or(0),
            "high": counts.get(&Severity::High).copied().unwrap_or(0),
            "medium": counts.get(&Severity::Medium).copied().unwrap_or(0),
            "low": counts.get(&Severity::Low).copied().unwrap_or(0),
            "info": counts.get(&Severity::Info).copied().unwrap_or(0),
        },
        "by_category": {
            "cost": by_category.get(&Category::Cost).copied().unwrap_or(0),
            "cache": by_category.get(&Category::Cache).copied().unwrap_or(0),
            "quality": by_category.get(&Category::Quality).copied().unwrap_or(0),
            "bloat": by_category.get(&Category::Bloat).copied().unwrap_or(0),
            "architecture": by_category.get(&Category::Architecture).copied().unwrap_or(0),
        },
        "verdict_rework": counts.get(&Severity::Critical).copied().unwrap_or(0) > 0,
        "verdict_review": counts.get(&Severity::High).copied().unwrap_or(0) > 0,
    });
    serde_json::to_string_pretty(&summary).unwrap_or_default()
}

/// Render the TOON summary block.
pub fn render_toon_summary(findings: &[Finding]) -> String {
    let mut counts: HashMap<Severity, usize> = HashMap::new();
    let mut by_category: HashMap<Category, usize> = HashMap::new();
    for f in findings {
        *counts.entry(f.severity).or_insert(0) += 1;
        *by_category.entry(f.category).or_insert(0) += 1;
    }
    let mut buf: Vec<u8> = Vec::new();
    let severity_counts: Vec<(&str, usize)> = SEVERITY_ORDER
        .iter()
        .map(|s| (s.as_str(), counts.get(s).copied().unwrap_or(0)))
        .collect();
    let category_counts: Vec<(&str, usize)> = CATEGORY_LABELS
        .iter()
        .map(|(c, _)| (c.as_str(), by_category.get(c).copied().unwrap_or(0)))
        .collect();
    let verdict_rework = counts.get(&Severity::Critical).copied().unwrap_or(0) > 0;
    let verdict_review = counts.get(&Severity::High).copied().unwrap_or(0) > 0;
    let verdict_pass_with_notes = counts.get(&Severity::Low).copied().unwrap_or(0) > 0
        && counts.get(&Severity::Critical).copied().unwrap_or(0) == 0
        && counts.get(&Severity::High).copied().unwrap_or(0) == 0
        && counts.get(&Severity::Medium).copied().unwrap_or(0) == 0;
    toon::write_summary(
        &mut buf,
        findings.len(),
        &severity_counts,
        &category_counts,
        verdict_rework,
        verdict_review,
        verdict_pass_with_notes,
    )
    .ok();
    String::from_utf8(buf).unwrap_or_default()
}

/// Top-level driver for the `report` subcommand.
pub fn run(findings_path: &Path, format: ReportFormat) -> Result<()> {
    let findings = load_findings(findings_path)?;
    let stdout = std::io::stdout();
    let mut handle = stdout.lock();
    match format {
        ReportFormat::Md => handle.write_all(render_markdown(&findings).as_bytes())?,
        ReportFormat::Json => handle.write_all(render_json_summary(&findings).as_bytes())?,
        ReportFormat::Toon => handle.write_all(render_toon_summary(&findings).as_bytes())?,
    }
    handle.write_all(b"\n")?;
    Ok(())
}

/// Helper: write a report file (used by run-all to bundle outputs).
pub fn write_report_files(out_dir: &Path, findings: &[Finding]) -> Result<()> {
    std::fs::create_dir_all(out_dir)?;

    let report_md = out_dir.join("report.md");
    let mut f = BufWriter::new(File::create(&report_md)?);
    f.write_all(render_markdown(findings).as_bytes())?;
    f.write_all(b"\n")?;

    let summary_json = out_dir.join("summary.json");
    let mut f = BufWriter::new(File::create(&summary_json)?);
    f.write_all(render_json_summary(findings).as_bytes())?;
    f.write_all(b"\n")?;

    let summary_toon = out_dir.join("summary.toon");
    let mut f = BufWriter::new(File::create(&summary_toon)?);
    f.write_all(render_toon_summary(findings).as_bytes())?;

    Ok(())
}
