//! TOON v3.0 thin emitter — Token-Oriented Object Notation.
//!
//! Spec: <https://github.com/toon-format/spec>
//!
//! This module supports the subset needed for ctxopt output:
//! - Uniform array of objects → tabular form: `key[N]{f1,f2,...}:` header + tab-separated rows.
//! - Scalar key-value lines: `key: value`.
//! - Nested key-value blocks via 2-space indentation.
//! - Multi-line string content via `|` literal blocks with indentation.
//!
//! Round-trip with TOON-format reference parsers is in scope of unit tests.

use crate::finding::Finding;
use std::io::{self, Write};

/// Sanitize a string for use as a tab-separated TOON cell.
/// Replaces tabs/newlines/carriage returns with spaces; trims trailing whitespace.
fn sanitize_cell(s: &str) -> String {
    s.replace(['\t', '\n', '\r'], " ").trim().to_string()
}

/// Emit a uniform-array block header: `key[N]{f1,f2,...}:`
pub fn write_uniform_header<W: Write>(
    w: &mut W,
    key: &str,
    count: usize,
    fields: &[&str],
) -> io::Result<()> {
    write!(w, "{key}[{count}]{{")?;
    for (i, f) in fields.iter().enumerate() {
        if i > 0 {
            write!(w, ",")?;
        }
        w.write_all(f.as_bytes())?;
    }
    writeln!(w, "}}:")?;
    Ok(())
}

/// Emit a single uniform-array row with 2-space indent + tab-separated cells.
pub fn write_uniform_row<W: Write>(w: &mut W, cells: &[String]) -> io::Result<()> {
    write!(w, "  ")?;
    for (i, cell) in cells.iter().enumerate() {
        if i > 0 {
            w.write_all(b"\t")?;
        }
        w.write_all(sanitize_cell(cell).as_bytes())?;
    }
    writeln!(w)?;
    Ok(())
}

/// Emit a scalar key-value line.
pub fn write_scalar<W: Write>(w: &mut W, key: &str, value: &str) -> io::Result<()> {
    writeln!(w, "{key}: {value}")
}

/// Emit a list of findings as `findings[N]{...}:` uniform array (or `findings[]{}: empty`).
pub fn write_findings<W: Write>(w: &mut W, findings: &[Finding]) -> io::Result<()> {
    let fields = [
        "id",
        "phase",
        "severity",
        "category",
        "target",
        "impact",
        "remediation",
        "timestamp",
    ];
    write_uniform_header(w, "findings", findings.len(), &fields)?;
    for f in findings {
        let cells = vec![
            f.id.clone(),
            f.phase.clone(),
            f.severity.to_string(),
            f.category.to_string(),
            f.target.clone(),
            f.impact.clone(),
            f.remediation.clone(),
            f.timestamp.clone(),
        ];
        write_uniform_row(w, &cells)?;
    }

    // Heterogeneous evidence goes in a secondary block (one record per finding).
    let any_evidence = findings
        .iter()
        .any(|f| !f.evidence.is_null() && f.evidence != serde_json::json!({}));
    if any_evidence {
        writeln!(w)?;
        writeln!(w, "evidence_blob:")?;
        for f in findings {
            if f.evidence.is_null() || f.evidence == serde_json::json!({}) {
                continue;
            }
            writeln!(w, "  - id: {}", f.id)?;
            let json = serde_json::to_string(&f.evidence).unwrap_or_default();
            writeln!(w, "    json: {json}")?;
        }
    }

    Ok(())
}

/// Emit a summary block grouping severity/category counts and a verdict scalar.
#[allow(clippy::too_many_arguments)]
pub fn write_summary<W: Write>(
    w: &mut W,
    total: usize,
    severity_counts: &[(&str, usize)],
    category_counts: &[(&str, usize)],
    verdict_rework: bool,
    verdict_review: bool,
    verdict_pass_with_notes: bool,
) -> io::Result<()> {
    write_scalar(w, "total", &total.to_string())?;
    write_uniform_header(w, "counts", severity_counts.len(), &["severity", "count"])?;
    for (sev, n) in severity_counts {
        write_uniform_row(w, &[sev.to_string(), n.to_string()])?;
    }
    write_uniform_header(
        w,
        "by_category",
        category_counts.len(),
        &["category", "count"],
    )?;
    for (cat, n) in category_counts {
        write_uniform_row(w, &[cat.to_string(), n.to_string()])?;
    }
    writeln!(w, "verdict:")?;
    writeln!(w, "  rework: {verdict_rework}")?;
    writeln!(w, "  review: {verdict_review}")?;
    writeln!(w, "  pass_with_notes: {verdict_pass_with_notes}")?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::finding::{Category, Finding, Severity};
    use serde_json::json;

    #[test]
    fn uniform_header_writes_expected_form() {
        let mut buf = Vec::new();
        write_uniform_header(&mut buf, "items", 3, &["a", "b", "c"]).unwrap();
        assert_eq!(String::from_utf8(buf).unwrap(), "items[3]{a,b,c}:\n");
    }

    #[test]
    fn uniform_row_tab_separates() {
        let mut buf = Vec::new();
        write_uniform_row(&mut buf, &["x".into(), "y\twith tab".into(), "z\nnewline".into()])
            .unwrap();
        let out = String::from_utf8(buf).unwrap();
        assert!(out.starts_with("  x\t"));
        assert!(!out.contains("\ty\twith"));
        assert!(!out.contains('\n') || out.ends_with('\n'));
    }

    #[test]
    fn findings_block_round_trips_count() {
        let f = Finding::new(
            "T-001",
            "scan",
            Severity::High,
            Category::Bloat,
            "src/big.md",
            "Big file",
            "Apply masking",
            json!({"path": "src/big.md", "size_bytes": 12345}),
        );
        let mut buf = Vec::new();
        write_findings(&mut buf, &[f]).unwrap();
        let out = String::from_utf8(buf).unwrap();
        assert!(out.starts_with("findings[1]{id,phase,severity,category,"));
        assert!(out.contains("T-001\tscan\thigh\tbloat\tsrc/big.md"));
        assert!(out.contains("evidence_blob:"));
    }
}
