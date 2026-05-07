//! `ctxopt count` — accurate token counter via tiktoken-rs.
//! Equivalent to legacy 01-token-count.py with tiktoken nativo (no chars/4 fallback).

use crate::cli::{Encoding, TokenThresholds};
use crate::emit::{log_finding, FindingWriter};
use crate::finding::{Category, Finding, Severity};
use anyhow::{Context, Result};
use serde_json::json;
use std::path::{Path, PathBuf};
use tiktoken_rs::CoreBPE;
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

fn load_encoder(encoding: Encoding) -> Result<CoreBPE> {
    match encoding {
        Encoding::Cl100kBase => tiktoken_rs::cl100k_base().context("loading cl100k_base"),
        Encoding::O200kBase => tiktoken_rs::o200k_base().context("loading o200k_base"),
    }
}

pub fn run(
    project_root: &Path,
    thresholds: &TokenThresholds,
    encoding: Encoding,
    writer: &mut dyn FindingWriter,
    quiet: bool,
) -> Result<()> {
    let project_root = project_root
        .canonicalize()
        .with_context(|| format!("project_root not readable: {}", project_root.display()))?;

    let encoder = load_encoder(encoding)?;
    if !quiet {
        eprintln!(
            "[INFO]  Counting tokens in {} (tokenizer: {}) ...",
            project_root.display(),
            encoding.name()
        );
    }

    let mut candidates: Vec<(PathBuf, usize)> = Vec::new();
    let mut total_tokens: usize = 0;

    for entry in WalkDir::new(&project_root).into_iter().filter_entry(|e| !is_excluded(e)) {
        let entry = match entry {
            Ok(e) => e,
            Err(_) => continue,
        };
        if !entry.file_type().is_file() || !has_target_extension(entry.path()) {
            continue;
        }
        let path = entry.into_path();
        let text = match std::fs::read_to_string(&path) {
            Ok(t) => t,
            Err(_) => continue,
        };
        let tokens = encoder.encode_with_special_tokens(&text).len();
        total_tokens = total_tokens.saturating_add(tokens);
        candidates.push((path, tokens));
    }

    candidates.sort_by(|a, b| b.1.cmp(&a.1));
    let total_files = candidates.len();

    if !quiet {
        eprintln!(
            "[INFO]  Scanned {total_files} files; total ~{total_tokens} tokens (exact, {}).",
            encoding.name()
        );
    }

    for (rank, (path, tokens)) in candidates.iter().take(20).enumerate() {
        let rank = rank + 1;
        let rel = path
            .strip_prefix(&project_root)
            .unwrap_or(path)
            .to_string_lossy()
            .to_string();

        let (severity, impact, remediation) = if *tokens >= thresholds.threshold_high_tokens {
            (
                Severity::High,
                format!(
                    "File consumes ~{tokens} tokens. On a 200k window this is {}% of budget by itself.",
                    tokens * 100 / 200_000
                ),
                "Apply §3 observation masking if this is a tool output, or §6 verbatim deletion if citation-bound. For monolithic source files, consider §7 partitioning across sub-agents.".to_string(),
            )
        } else if *tokens >= thresholds.threshold_medium_tokens {
            (
                Severity::Medium,
                format!("File consumes ~{tokens} tokens. Cumulative bloat adds up across files."),
                "Review for §10 dedup opportunities and unused content.".to_string(),
            )
        } else if *tokens >= thresholds.threshold_low_tokens {
            (
                Severity::Low,
                format!("File consumes ~{tokens} tokens — within budget but tracked."),
                "Track across runs; flag growth.".to_string(),
            )
        } else {
            continue;
        };

        let evidence = json!({
            "path": rel,
            "tokens": tokens,
            "rank": rank,
            "tokenizer": format!("tiktoken-{}", encoding.name()),
        });

        let finding = Finding::new(
            format!("TOK-{rank:03}"),
            "count",
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

    let summary = Finding::new(
        "TOK-SUM",
        "count",
        Severity::Info,
        Category::Bloat,
        project_root.to_string_lossy(),
        format!(
            "Scanned {total_files} files totalling ~{total_tokens} tokens (exact, {})",
            encoding.name()
        ),
        "Use this as Phase 1 inventory baseline. Compare to use-case ceiling per Phase 5.3 (long-conv-agent ≤ 100k; rag stable prefix ≤ 8k; sub-agent ≤ 30k; large-doc ≤ 200k).",
        json!({
            "total_files": total_files,
            "total_tokens": total_tokens,
            "tokenizer": format!("tiktoken-{}", encoding.name()),
            "accuracy": "exact",
        }),
    );
    log_finding(&summary, quiet);
    writer.write(&summary)?;

    if !quiet {
        eprintln!("[OK]    Token count complete.");
    }
    Ok(())
}
