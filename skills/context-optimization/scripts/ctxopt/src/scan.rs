//! `ctxopt scan` — file-size scanner. Equivalent to legacy 00-context-scan.sh.

use crate::cli::SizeThresholds;
use crate::emit::{log_finding, FindingWriter};
use crate::finding::{Category, Finding, Severity};
use anyhow::{Context, Result};
use serde_json::json;
use std::path::{Path, PathBuf};
use walkdir::{DirEntry, WalkDir};

const TARGET_EXTENSIONS: &[&str] = &["md", "json", "jsonl", "txt"];
const EXCLUDED_PARTS: &[&str] = &[".git", "node_modules", ".venv", "__pycache__", "out", "target"];

fn is_excluded(entry: &DirEntry) -> bool {
    entry
        .path()
        .components()
        .any(|c| EXCLUDED_PARTS.iter().any(|ex| c.as_os_str() == *ex))
}

fn has_target_extension(path: &Path) -> bool {
    path.extension()
        .and_then(|e| e.to_str())
        .map(|e| TARGET_EXTENSIONS.contains(&e))
        .unwrap_or(false)
}

pub fn run(
    project_root: &Path,
    thresholds: &SizeThresholds,
    writer: &mut dyn FindingWriter,
    quiet: bool,
) -> Result<()> {
    let project_root = project_root
        .canonicalize()
        .with_context(|| format!("project_root not readable: {}", project_root.display()))?;

    if !quiet {
        eprintln!(
            "[INFO]  Scanning {} for context candidates ...",
            project_root.display()
        );
    }

    let mut candidates: Vec<(PathBuf, u64)> = Vec::new();
    for entry in WalkDir::new(&project_root).into_iter().filter_entry(|e| !is_excluded(e)) {
        let entry = match entry {
            Ok(e) => e,
            Err(_) => continue,
        };
        if !entry.file_type().is_file() {
            continue;
        }
        if !has_target_extension(entry.path()) {
            continue;
        }
        let size = entry.metadata().map(|m| m.len()).unwrap_or(0);
        candidates.push((entry.into_path(), size));
    }

    candidates.sort_by(|a, b| b.1.cmp(&a.1));

    let total_files = candidates.len();
    let total_bytes: u64 = candidates.iter().map(|(_, s)| s).sum();

    if !quiet {
        eprintln!("[INFO]  Found {total_files} candidate files.");
    }

    if total_files == 0 {
        if !quiet {
            eprintln!("[OK]    No context candidates found in {}", project_root.display());
        }
        return Ok(());
    }

    for (rank, (path, size)) in candidates.iter().take(20).enumerate() {
        let rank = rank + 1;
        let est_tokens = size / 4;
        let rel = path
            .strip_prefix(&project_root)
            .unwrap_or(path)
            .to_string_lossy()
            .to_string();

        let (severity, impact, remediation) = if *size >= thresholds.threshold_high {
            (
                Severity::High,
                format!(
                    "File alone consumes ~{est_tokens} tokens (~{}KB). On a 200k window, this is {}% of total budget.",
                    size / 1024,
                    est_tokens * 100 / 200_000
                ),
                "Apply §3 observation masking if this file is a tool output, or §6 verbatim deletion if citation-bound. For source code in audit scope, consider §7 partitioning.".to_string(),
            )
        } else if *size >= thresholds.threshold_medium {
            (
                Severity::Medium,
                format!(
                    "File consumes ~{est_tokens} tokens. Cumulative bloat across multiple files this size adds up."
                ),
                "Review for dedup opportunities (§10) and unused content.".to_string(),
            )
        } else if *size >= thresholds.threshold_low {
            (
                Severity::Low,
                format!(
                    "File consumes ~{est_tokens} tokens — within typical budget but contributes to total."
                ),
                "Track across runs; flag if this category grows.".to_string(),
            )
        } else {
            continue;
        };

        let evidence = json!({
            "path": rel,
            "size_bytes": size,
            "estimated_tokens": est_tokens,
            "rank": rank,
        });

        let finding = Finding::new(
            format!("CTX-SCAN-{rank:03}"),
            "scan",
            severity,
            Category::Bloat,
            rel,
            impact,
            remediation,
            evidence,
        );
        log_finding(&finding, quiet);
        writer.write(&finding)?;
    }

    let total_kb = total_bytes / 1024;
    let total_est_tokens = total_bytes / 4;
    let summary = Finding::new(
        "CTX-SCAN-SUM",
        "scan",
        Severity::Info,
        Category::Bloat,
        project_root.to_string_lossy(),
        format!(
            "Scanned {total_files} files totalling ~{total_kb} KB (~{total_est_tokens} tokens)"
        ),
        "Use this as the Phase 1 inventory baseline. Compare to use-case ceiling per Phase 5.3.",
        json!({
            "total_files": total_files,
            "total_bytes": total_bytes,
            "total_kb": total_kb,
            "estimated_total_tokens": total_est_tokens,
        }),
    );
    log_finding(&summary, quiet);
    writer.write(&summary)?;

    if !quiet {
        eprintln!("[OK]    Context scan complete.");
    }
    Ok(())
}
